import argparse
import json
import tempfile
import threading
import unittest
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

import numpy as np

from server import BridgeController, BridgeError, create_server, validate_bind_address, validate_compute_payload


class FakeRegisters:
    def __init__(self):
        self.values = {0x04: 0, 0x1C: 42, 0x20: 3}
        self.writes = []

    def read(self, address):
        return self.values.get(address, 0)

    def write(self, address, value):
        self.writes.append((address, value))
        if address == 0x00 and value == 0x02:
            self.values[0x04] = 0


class FakeOverlay:
    def __init__(self):
        self.registers = FakeRegisters()


class FakeDriver:
    behavior = "hardware"
    started = None
    release = None

    def __init__(self, overlay):
        self.hardware_available = True
        self.engines = [(overlay.registers, object(), 16)]

    def multiply(self, a, b, active_m=None, active_n=None):
        if self.started is not None:
            self.started.set()
            self.release.wait(timeout=3)
        if self.behavior == "timeout":
            raise TimeoutError("driver timeout")
        if self.behavior == "malformed":
            return np.zeros((1, 1), dtype=np.int32), {"mode": "HARDWARE_MEASURED", "cycles": 1, "tiles": 1, "overflow": False}
        output = (a.astype(np.int64) @ b.astype(np.int64)).astype(np.int32)
        mode = "SOFTWARE_REFERENCE" if self.behavior == "software" else "HARDWARE_MEASURED"
        return output, {"mode": mode, "cycles": 42, "tiles": 3, "overflow": False}


def prepared_controller(temp_path, behavior="hardware", driver=FakeDriver):
    bit = temp_path / "test.bit"
    hwh = temp_path / "test.hwh"
    bit.touch()
    hwh.touch()
    FakeDriver.behavior = behavior
    FakeDriver.started = None
    FakeDriver.release = None
    controller = BridgeController(
        temp_path,
        bit,
        overlay_loader=lambda unused: FakeOverlay(),
        driver_factory=driver,
    )
    controller.initialize()
    return controller


class BridgeValidationTests(unittest.TestCase):
    def setUp(self):
        self.valid = {"matrixA": [[-128, 127]], "matrixB": [[1], [1]]}

    def test_signed_int8_boundaries_and_large_tiled_shapes(self):
        result = validate_compute_payload({
            "matrixA": [[-128] * 17 for _ in range(17)],
            "matrixB": [[127] * 18 for _ in range(17)],
        })
        self.assertEqual(result["shape"], {"m": 17, "k": 17, "n": 18})

    def test_bridge_bind_is_limited_to_private_lan_or_loopback(self):
        self.assertEqual(validate_bind_address("192.168.1.50"), "192.168.1.50")
        self.assertEqual(validate_bind_address("127.0.0.1"), "127.0.0.1")
        for address in ("0.0.0.0", "8.8.8.8", "board.local"):
            with self.subTest(address=address), self.assertRaises(argparse.ArgumentTypeError):
                validate_bind_address(address)

    def test_rejects_non_integer_boolean_ragged_empty_and_out_of_range_values(self):
        cases = [
            {"matrixA": [[True]], "matrixB": [[1]]},
            {"matrixA": [[1.5]], "matrixB": [[1]]},
            {"matrixA": [[1], [1, 2]], "matrixB": [[1], [1]]},
            {"matrixA": [], "matrixB": [[1]]},
            {"matrixA": [[128]], "matrixB": [[1]]},
            {"matrixA": [[1]], "matrixB": [[1]], "activeM": 0},
            {"matrixA": [[1, 2]], "matrixB": [[1]]},
        ]
        for payload in cases:
            with self.subTest(payload=payload):
                with self.assertRaises(BridgeError) as caught:
                    validate_compute_payload(payload)
                self.assertEqual(caught.exception.code, "invalid_input")


class BridgeControllerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name)
        self.payload = {"matrixA": [[1, -2], [3, 4]], "matrixB": [[5, 6], [7, 8]]}

    def tearDown(self):
        FakeDriver.started = None
        FakeDriver.release = None
        self.temp.cleanup()

    def test_missing_bit_or_hwh_keeps_hardware_unavailable(self):
        bit = self.path / "missing.bit"
        controller = BridgeController(self.path, bit, overlay_loader=lambda unused: FakeOverlay(), driver_factory=FakeDriver)
        with self.assertRaises(BridgeError) as caught:
            controller.initialize()
        self.assertEqual(caught.exception.code, "overlay_unavailable")
        self.assertFalse(controller.status()["hardwareReady"])

    def test_hardware_result_contains_measured_metrics_and_int32_matrix(self):
        controller = prepared_controller(self.path)
        response = controller.compute(self.payload)
        self.assertEqual(response["mode"], "HARDWARE_MEASURED")
        self.assertEqual(response["matrixC"], [[-9, -10], [43, 50]])
        self.assertEqual(response["metrics"]["cycles"], 42)
        self.assertEqual(response["metrics"]["tiles"], 3)
        self.assertGreaterEqual(response["metrics"]["totalElapsedMs"], 0)

    def test_software_reference_fallback_is_never_returned_as_hardware(self):
        controller = prepared_controller(self.path, behavior="software")
        with self.assertRaises(BridgeError) as caught:
            controller.compute(self.payload)
        self.assertEqual(caught.exception.code, "hardware_unavailable")

    def test_malformed_driver_output_is_rejected(self):
        controller = prepared_controller(self.path, behavior="malformed")
        with self.assertRaises(BridgeError) as caught:
            controller.compute(self.payload)
        self.assertEqual(caught.exception.code, "malformed_response")

    def test_driver_timeout_is_not_reported_as_completion(self):
        controller = prepared_controller(self.path, behavior="timeout")
        with self.assertRaises(BridgeError) as caught:
            controller.compute(self.payload)
        self.assertEqual(caught.exception.status, 504)
        self.assertEqual(controller.status()["operation"]["state"], "error")

    def test_busy_request_is_rejected_and_reset_is_serialized(self):
        controller = prepared_controller(self.path)
        FakeDriver.started = threading.Event()
        FakeDriver.release = threading.Event()
        worker = threading.Thread(target=lambda: controller.compute(self.payload))
        worker.start()
        self.assertTrue(FakeDriver.started.wait(timeout=1))
        with self.assertRaises(BridgeError) as caught:
            controller.compute(self.payload)
        self.assertEqual(caught.exception.code, "hardware_busy")
        with self.assertRaises(BridgeError) as reset_error:
            controller.reset()
        self.assertEqual(reset_error.exception.code, "hardware_busy")
        FakeDriver.release.set()
        worker.join(timeout=2)
        self.assertFalse(worker.is_alive())

    def test_reset_pulses_existing_soft_reset_register(self):
        controller = prepared_controller(self.path)
        controller.reset()
        regs = controller.driver.engines[0][0]
        self.assertEqual(regs.writes, [(0x00, 0x02), (0x00, 0x00)])

    def test_status_reports_hardware_register_flags(self):
        controller = prepared_controller(self.path)
        controller.driver.engines[0][0].values[0x04] = 0x12
        status = controller.status()
        self.assertEqual(status["pynq"]["state"], "connected")
        self.assertTrue(status["engines"][0]["done"])
        self.assertTrue(status["engines"][0]["inputALoaded"])

    def test_http_status_and_validation_errors_are_structured(self):
        controller = BridgeController(self.path, self.path / "missing.bit")
        server = create_server(controller, "127.0.0.1", 0)
        worker = threading.Thread(target=server.serve_forever)
        worker.start()
        base = "http://127.0.0.1:" + str(server.server_address[1])
        try:
            with urlopen(base + "/api/status", timeout=2) as response:
                status = json.loads(response.read().decode("utf-8"))
                self.assertEqual(response.status, 200)
                self.assertEqual(status["bridge"]["state"], "online")
                self.assertFalse(status["hardwareReady"])

            request = Request(
                base + "/api/compute",
                data=b'{"matrixA":[[1]],"matrixB":[[]]}',
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with self.assertRaises(HTTPError) as caught:
                urlopen(request, timeout=2)
            self.assertEqual(caught.exception.code, 400)
            try:
                error = json.loads(caught.exception.read().decode("utf-8"))
            finally:
                caught.exception.close()
            self.assertEqual(error["error"]["code"], "invalid_input")
        finally:
            server.shutdown()
            server.server_close()
            worker.join(timeout=2)

    def test_cors_allows_only_configured_cross_origin_pages(self):
        controller = BridgeController(self.path, self.path / "missing.bit")
        server = create_server(controller, "127.0.0.1", 0, ["http://localhost:8080"])
        worker = threading.Thread(target=server.serve_forever)
        worker.start()
        base = "http://127.0.0.1:" + str(server.server_address[1])
        try:
            request = Request(base + "/api/status", headers={"Origin": "http://localhost:8080"})
            with urlopen(request, timeout=2) as response:
                self.assertEqual(response.headers.get("Access-Control-Allow-Origin"), "http://localhost:8080")

            request = Request(base + "/api/status", headers={"Origin": "http://example.invalid"})
            with self.assertRaises(HTTPError) as caught:
                urlopen(request, timeout=2)
            self.assertEqual(caught.exception.code, 403)
            caught.exception.close()
        finally:
            server.shutdown()
            server.server_close()
            worker.join(timeout=2)


if __name__ == "__main__":
    unittest.main()
