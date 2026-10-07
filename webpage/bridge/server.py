#!/usr/bin/env python3
"""Local HTTP bridge for the existing AdaptiveGEMM PYNQ driver."""

from __future__ import annotations

import argparse
import importlib.util
import ipaddress
import json
import logging
import mimetypes
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit

APP_DIR = Path(__file__).resolve().parents[1]
DEFAULT_PROJECT_ROOT = Path(__file__).resolve().parents[3] / "antigravity"
MAX_REQUEST_BYTES = 16 * 1024 * 1024
LOG = logging.getLogger("adaptive-systolic-bridge")


class BridgeError(Exception):
    def __init__(self, status, code, message):
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message


def _positive_dimension(value, label):
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise BridgeError(400, "invalid_input", label + " must be a positive whole number.")
    return value


def validate_compute_payload(payload):
    if not isinstance(payload, dict):
        raise BridgeError(400, "invalid_input", "The request body must be a JSON object.")
    matrices = []
    for key, label in (("matrixA", "Matrix A"), ("matrixB", "Matrix B")):
        matrix = payload.get(key)
        if not isinstance(matrix, list) or not matrix:
            raise BridgeError(400, "invalid_input", label + " must be a non-empty two-dimensional matrix.")
        if any(not isinstance(row, list) or not row for row in matrix):
            raise BridgeError(400, "invalid_input", label + " must be a non-empty two-dimensional matrix.")
        width = len(matrix[0])
        if any(len(row) != width for row in matrix):
            raise BridgeError(400, "invalid_input", label + " rows must all have the same length.")
        normalized = []
        for row_index, row in enumerate(matrix):
            normalized_row = []
            for col_index, value in enumerate(row):
                if isinstance(value, bool) or not isinstance(value, int):
                    raise BridgeError(400, "invalid_input", label + " values must be whole numbers.")
                if value < -128 or value > 127:
                    raise BridgeError(
                        400,
                        "invalid_input",
                        label + " value at row " + str(row_index + 1) + ", column " + str(col_index + 1)
                        + " is outside signed INT8 range (-128 to 127).",
                    )
                normalized_row.append(value)
            normalized.append(normalized_row)
        matrices.append(normalized)

    matrix_a, matrix_b = matrices
    if len(matrix_a[0]) != len(matrix_b):
        raise BridgeError(400, "invalid_input", "Matrix A columns must equal Matrix B rows.")

    active_m = payload.get("activeM", 16)
    active_n = payload.get("activeN", 16)
    for name, value in (("activeM", active_m), ("activeN", active_n)):
        if isinstance(value, bool) or not isinstance(value, int) or value < 1 or value > 16:
            raise BridgeError(400, "invalid_input", name + " must be a whole number from 1 to 16.")
    return {
        "matrixA": matrix_a,
        "matrixB": matrix_b,
        "activeM": active_m,
        "activeN": active_n,
        "shape": {"m": len(matrix_a), "k": len(matrix_a[0]), "n": len(matrix_b[0])},
    }


def validate_bind_address(value):
    """Only listen on an explicit private IPv4 address or loopback."""
    try:
        address = ipaddress.IPv4Address(value)
    except ipaddress.AddressValueError as exc:
        raise argparse.ArgumentTypeError("--bind must be a private IPv4 address or 127.0.0.1") from exc
    if address.is_unspecified or not (address.is_loopback or (address.is_private and not address.is_link_local)):
        raise argparse.ArgumentTypeError("--bind must be a private LAN address or 127.0.0.1; wildcard/public binds are disabled")
    return str(address)


def _load_driver_class(project_root):
    driver_path = Path(project_root) / "pynq" / "adaptive_gemm.py"
    if not driver_path.is_file():
        raise BridgeError(
            503,
            "driver_unavailable",
            "Could not find pynq/adaptive_gemm.py under the configured project directory.",
        )
    spec = importlib.util.spec_from_file_location("adaptive_gemm_project_driver", str(driver_path))
    if spec is None or spec.loader is None:
        raise BridgeError(503, "driver_unavailable", "The existing PYNQ driver could not be imported.")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.AdaptiveGEMM


def _load_overlay(bitstream_path):
    try:
        from pynq import Overlay
    except Exception as exc:
        raise BridgeError(503, "pynq_unavailable", "The PYNQ Python runtime is not available.") from exc
    return Overlay(str(bitstream_path))


class BridgeController:
    """Serializes hardware actions and exposes only bridge-confirmed results."""

    ADDR_CTRL = 0x00
    ADDR_STATUS = 0x04
    ADDR_CYCLES = 0x1C
    ADDR_TILES = 0x20
    STATUS_BUSY = 1 << 0
    STATUS_DONE = 1 << 1
    STATUS_OVERFLOW = 1 << 2
    STATUS_INVALID = 1 << 3
    STATUS_A_LOADED = 1 << 4
    STATUS_B_LOADED = 1 << 5

    def __init__(self, project_root, bitstream_path, overlay_loader=None, driver_factory=None):
        self.project_root = Path(project_root)
        self.bitstream_path = Path(bitstream_path)
        self.overlay_loader = overlay_loader or _load_overlay
        self.driver_factory = driver_factory
        self.overlay = None
        self.driver = None
        self.operation_state = "idle"
        self.last_error = None
        self.last_result_metrics = None
        self._lock = threading.Lock()
        self._state_lock = threading.RLock()

    @property
    def hardware_available(self):
        return bool(self.driver is not None and getattr(self.driver, "hardware_available", False))

    def _enter_action(self, state):
        if not self._lock.acquire(blocking=False):
            raise BridgeError(409, "hardware_busy", "The hardware bridge is already handling an operation.")
        with self._state_lock:
            self.operation_state = state
            self.last_error = None

    def _leave_action(self, state=None):
        with self._state_lock:
            if state is not None:
                self.operation_state = state
            self._lock.release()

    def initialize(self):
        if any(engine["busy"] for engine in self._read_engines()):
            raise BridgeError(409, "hardware_busy", "The accelerator is busy and cannot be reinitialized.")
        self._enter_action("initializing")
        try:
            self.overlay = None
            self.driver = None
            self.last_result_metrics = None
            if not self.bitstream_path.is_file():
                raise BridgeError(503, "overlay_unavailable", "The configured .bit file was not found.")
            metadata_path = self.bitstream_path.with_suffix(".hwh")
            if not metadata_path.is_file():
                raise BridgeError(503, "overlay_unavailable", "The matching .hwh file was not found beside the .bit file.")
            driver_class = self.driver_factory or _load_driver_class(self.project_root)
            try:
                overlay = self.overlay_loader(self.bitstream_path)
                driver = driver_class(overlay)
            except BridgeError:
                raise
            except Exception as exc:
                LOG.exception("Overlay initialization failed")
                raise BridgeError(503, "overlay_unavailable", "The FPGA overlay could not be initialized.") from exc
            if not getattr(driver, "hardware_available", False):
                self.overlay = overlay
                self.driver = driver
                raise BridgeError(
                    503,
                    "hardware_unavailable",
                    "The overlay loaded, but no supported accelerator and DMA pair was detected.",
                )
            self.overlay = overlay
            self.driver = driver
            engines = self._read_engines()
            if not engines or not all(engine["telemetryAvailable"] for engine in engines):
                raise BridgeError(
                    503,
                    "hardware_unavailable",
                    "The overlay loaded, but accelerator status registers could not be read.",
                )
            self.last_result_metrics = None
            self._leave_action("idle")
            return self.status()
        except BridgeError as exc:
            with self._state_lock:
                self.last_error = {"code": exc.code, "message": exc.message}
            self._leave_action("error")
            raise
        except Exception as exc:
            LOG.exception("Unexpected overlay initialization error")
            with self._state_lock:
                self.last_error = {"code": "overlay_unavailable", "message": "The FPGA overlay could not be initialized."}
            self._leave_action("error")
            raise BridgeError(503, "overlay_unavailable", "The FPGA overlay could not be initialized.") from exc

    def _read_engines(self):
        if self.driver is None or not getattr(self.driver, "engines", None):
            return []
        engines = []
        for index, engine in enumerate(self.driver.engines):
            regs = engine[0]
            entry = {
                "index": index,
                "name": "Engine " + str(index),
                "telemetryAvailable": False,
                "busy": False,
                "done": False,
                "overflow": False,
                "invalid": False,
                "inputALoaded": False,
                "inputBLoaded": False,
                "cycles": None,
                "tiles": None,
            }
            try:
                status = int(regs.read(self.ADDR_STATUS))
                entry.update({
                    "telemetryAvailable": True,
                    "busy": bool(status & self.STATUS_BUSY),
                    "done": bool(status & self.STATUS_DONE),
                    "overflow": bool(status & self.STATUS_OVERFLOW),
                    "invalid": bool(status & self.STATUS_INVALID),
                    "inputALoaded": bool(status & self.STATUS_A_LOADED),
                    "inputBLoaded": bool(status & self.STATUS_B_LOADED),
                    "cycles": int(regs.read(self.ADDR_CYCLES)),
                    "tiles": int(regs.read(self.ADDR_TILES)),
                })
            except Exception:
                LOG.exception("Could not read status from engine %s", index)
            engines.append(entry)
        return engines

    def status(self):
        engines = self._read_engines()
        any_busy = any(engine["busy"] for engine in engines)
        with self._state_lock:
            operation = self.operation_state
            error = dict(self.last_error) if self.last_error else None
        if operation == "idle" and any_busy:
            operation = "running"
        readable = bool(engines) and all(engine["telemetryAvailable"] for engine in engines)
        if self.driver is None:
            pynq_state = "unavailable" if error and error["code"] == "pynq_unavailable" else "uninitialized"
        elif self.hardware_available and readable:
            pynq_state = "connected"
        else:
            pynq_state = "unavailable"
        overlay_state = "loaded" if self.overlay is not None else "error" if error and error["code"] == "overlay_unavailable" else "not_loaded"
        return {
            "bridge": {"state": "online"},
            "pynq": {
                "state": pynq_state,
                "detail": "Accelerator registers are readable" if pynq_state == "connected" else None,
            },
            "overlay": {
                "state": overlay_state,
                "name": self.bitstream_path.name if self.overlay is not None else None,
                "detail": error["message"] if error else None,
            },
            "hardwareReady": self.hardware_available and readable,
            "busy": operation in ("initializing", "running", "resetting") or any_busy,
            "operation": {"state": operation},
            "engines": engines,
            "lastError": error,
        }

    @staticmethod
    def _validate_driver_result(result, metrics, shape):
        if not isinstance(metrics, dict):
            raise BridgeError(502, "malformed_response", "The PYNQ driver returned malformed metrics.")
        if metrics.get("mode") != "HARDWARE_MEASURED":
            raise BridgeError(
                503,
                "hardware_unavailable",
                "The PYNQ driver did not confirm a hardware-measured result.",
            )
        try:
            import numpy as np
            output = np.asarray(result)
            cycles = int(metrics["cycles"])
            tiles = int(metrics["tiles"])
            overflow = metrics["overflow"]
        except Exception as exc:
            raise BridgeError(502, "malformed_response", "The PYNQ driver returned incomplete result data.") from exc
        if output.shape != (shape["m"], shape["n"]) or output.dtype.kind not in ("i", "u"):
            raise BridgeError(502, "malformed_response", "The PYNQ driver returned an invalid result matrix.")
        if output.size and (int(output.min()) < -2147483648 or int(output.max()) > 2147483647):
            raise BridgeError(502, "malformed_response", "The PYNQ driver returned values outside signed INT32 range.")
        if cycles < 0 or tiles < 0 or not isinstance(overflow, (bool, int)):
            raise BridgeError(502, "malformed_response", "The PYNQ driver returned invalid metrics.")
        return output.astype("int32", copy=False).tolist(), {
            "mode": "HARDWARE_MEASURED",
            "cycles": cycles,
            "tiles": tiles,
            "overflow": bool(overflow),
        }

    def compute(self, payload):
        started = time.perf_counter()
        request = validate_compute_payload(payload)
        if self.driver is None or self.overlay is None:
            raise BridgeError(503, "hardware_unavailable", "Initialize a PYNQ-Z2 overlay before running a computation.")
        if not self.hardware_available:
            raise BridgeError(503, "hardware_unavailable", "The bridge has no supported hardware accelerator available.")
        engine_status = self._read_engines()
        if not engine_status or not all(engine["telemetryAvailable"] for engine in engine_status):
            raise BridgeError(503, "hardware_unavailable", "Accelerator status registers are not readable.")
        if any(engine["busy"] for engine in engine_status):
            raise BridgeError(409, "hardware_busy", "The accelerator is already busy.")
        self._enter_action("running")
        result_state = "error"
        try:
            try:
                import numpy as np
                matrix_a = np.asarray(request["matrixA"], dtype=np.int8)
                matrix_b = np.asarray(request["matrixB"], dtype=np.int8)
                output, driver_metrics = self.driver.multiply(
                    matrix_a,
                    matrix_b,
                    active_m=request["activeM"],
                    active_n=request["activeN"],
                )
            except TimeoutError as exc:
                raise BridgeError(504, "timeout", "The accelerator did not complete before its hardware timeout.") from exc
            except BridgeError:
                raise
            except Exception as exc:
                LOG.exception("Hardware computation failed")
                raise BridgeError(502, "hardware_error", "The hardware computation failed; no result was confirmed.") from exc
            output_values, metrics = self._validate_driver_result(output, driver_metrics, request["shape"])
            metrics["totalElapsedMs"] = round((time.perf_counter() - started) * 1000, 2)
            with self._state_lock:
                self.last_result_metrics = dict(metrics)
            result_state = "completed"
            return {
                "mode": "HARDWARE_MEASURED",
                "matrixC": output_values,
                "metrics": metrics,
            }
        except BridgeError as exc:
            with self._state_lock:
                self.last_error = {"code": exc.code, "message": exc.message}
            raise
        finally:
            self._leave_action(result_state)

    def reset(self):
        if self.driver is None or not self.hardware_available:
            raise BridgeError(503, "hardware_unavailable", "There is no initialized hardware to reset.")
        engine_status = self._read_engines()
        if not engine_status or not all(engine["telemetryAvailable"] for engine in engine_status):
            raise BridgeError(503, "hardware_unavailable", "Accelerator status registers are not readable.")
        if any(engine["busy"] for engine in engine_status):
            raise BridgeError(409, "hardware_busy", "The accelerator is busy and cannot be reset.")
        self._enter_action("resetting")
        try:
            for engine in self.driver.engines:
                regs = engine[0]
                regs.write(self.ADDR_CTRL, 0x02)
                regs.write(self.ADDR_CTRL, 0x00)
            deadline = time.monotonic() + 1.0
            while any(engine["busy"] for engine in self._read_engines()):
                if time.monotonic() >= deadline:
                    raise BridgeError(504, "timeout", "The hardware did not become idle after reset.")
                time.sleep(0.01)
            with self._state_lock:
                self.last_result_metrics = None
            self._leave_action("idle")
            return self.status()
        except BridgeError as exc:
            with self._state_lock:
                self.last_error = {"code": exc.code, "message": exc.message}
            self._leave_action("error")
            raise
        except Exception as exc:
            LOG.exception("Hardware reset failed")
            with self._state_lock:
                self.last_error = {"code": "hardware_error", "message": "The hardware reset failed."}
            self._leave_action("error")
            raise BridgeError(502, "hardware_error", "The hardware reset failed.") from exc


def make_handler(controller, allowed_origins):
    allowed_origins = set(allowed_origins or [])

    class Handler(BaseHTTPRequestHandler):
        server_version = "AdaptiveSystolicBridge/1.0"

        def log_message(self, format_string, *args):
            LOG.info("%s - %s", self.address_string(), format_string % args)

        def _origin_allowed(self):
            origin = self.headers.get("Origin")
            if not origin:
                return True
            if origin in allowed_origins:
                return True
            try:
                parsed = urlsplit(origin)
                request_host = self.headers.get("Host", "")
                return parsed.scheme == "http" and parsed.netloc.lower() == request_host.lower()
            except Exception:
                return False

        def _cors_headers(self):
            origin = self.headers.get("Origin")
            if origin:
                self.send_header("Access-Control-Allow-Origin", origin)
                self.send_header("Vary", "Origin")
                self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
                self.send_header("Access-Control-Allow-Headers", "Content-Type")
                self.send_header("Access-Control-Max-Age", "600")

        def _send_json(self, status, payload):
            data = json.dumps(payload, separators=(",", ":"), allow_nan=False).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self._cors_headers()
            self.end_headers()
            self.wfile.write(data)

        def _reject_origin(self):
            if self._origin_allowed():
                return False
            self._send_json(403, {"error": {"code": "origin_not_allowed", "message": "This page origin is not allowed by the local bridge."}})
            return True

        def _read_json(self):
            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError as exc:
                raise BridgeError(400, "invalid_input", "Content-Length must be a whole number.") from exc
            if length <= 0:
                raise BridgeError(400, "invalid_input", "A JSON request body is required.")
            if length > MAX_REQUEST_BYTES:
                raise BridgeError(413, "request_too_large", "The request is larger than the local bridge limit.")
            try:
                return json.loads(self.rfile.read(length).decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                raise BridgeError(400, "invalid_input", "The request body must contain valid JSON.") from exc

        def do_OPTIONS(self):
            if self._reject_origin():
                return
            self.send_response(204)
            self._cors_headers()
            self.end_headers()

        def do_GET(self):
            if self._reject_origin():
                return
            parsed = urlsplit(self.path)
            if parsed.path == "/api/status":
                self._send_json(200, controller.status())
                return
            if parsed.path.startswith("/api/"):
                self._send_json(404, {"error": {"code": "not_found", "message": "API route not found."}})
                return
            self._serve_static(parsed.path)

        def do_POST(self):
            if self._reject_origin():
                return
            route = urlsplit(self.path).path
            if route not in ("/api/initialize", "/api/compute", "/api/reset"):
                self._send_json(404, {"error": {"code": "not_found", "message": "API route not found."}})
                return
            try:
                payload = self._read_json()
                if not isinstance(payload, dict):
                    raise BridgeError(400, "invalid_input", "The request body must be a JSON object.")
                if route == "/api/initialize":
                    result = controller.initialize()
                elif route == "/api/compute":
                    result = controller.compute(payload)
                else:
                    result = controller.reset()
                self._send_json(200, result)
            except BridgeError as exc:
                self._send_json(exc.status, {"error": {"code": exc.code, "message": exc.message}})
            except Exception:
                LOG.exception("Unhandled API error")
                self._send_json(500, {"error": {"code": "internal_error", "message": "The local bridge could not complete the request."}})

        def _serve_static(self, request_path):
            decoded = unquote(request_path)
            relative = Path("." if decoded in ("", "/") else decoded.lstrip("/"))
            target = (APP_DIR / relative).resolve()
            try:
                target.relative_to(APP_DIR.resolve())
            except ValueError:
                self._send_json(404, {"error": {"code": "not_found", "message": "File not found."}})
                return
            if target.is_dir():
                target = target / "index.html"
            if not target.is_file():
                self._send_json(404, {"error": {"code": "not_found", "message": "File not found."}})
                return
            try:
                data = target.read_bytes()
            except OSError:
                self._send_json(500, {"error": {"code": "file_error", "message": "The page asset could not be read."}})
                return
            content_type = mimetypes.guess_type(str(target))[0] or "application/octet-stream"
            if content_type in ("text/css", "text/javascript", "application/javascript"):
                content_type += "; charset=utf-8"
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-cache")
            self.send_header("X-Content-Type-Options", "nosniff")
            self._cors_headers()
            self.end_headers()
            self.wfile.write(data)

    return Handler


def create_server(controller, bind, port, allowed_origins=None):
    server = ThreadingHTTPServer((bind, port), make_handler(controller, allowed_origins or []))
    server.daemon_threads = True
    server.allowed_origins = set(allowed_origins or [])
    return server


def main(argv=None):
    parser = argparse.ArgumentParser(description="Serve the Adaptive Systolic Array page and local PYNQ bridge.")
    parser.add_argument("--bind", required=True, type=validate_bind_address, help="Private LAN IP on the PYNQ-Z2 (or 127.0.0.1 for board-local use).")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--project-root", type=Path, default=DEFAULT_PROJECT_ROOT)
    parser.add_argument("--bitstream", type=Path, required=True, help="Path to the generated .bit file; matching .hwh must be beside it.")
    parser.add_argument("--allowed-origin", action="append", default=[], help="Exact browser origin allowed for a separately served page. Repeat as needed.")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args(argv)
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    controller = BridgeController(args.project_root, args.bitstream)
    server = create_server(controller, args.bind, args.port, args.allowed_origin)
    LOG.info("Adaptive Systolic Array bridge listening on %s:%s", args.bind, args.port)
    LOG.info("Serving page from %s", APP_DIR)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        LOG.info("Bridge shutdown requested")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
