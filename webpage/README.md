# Adaptive Systolic Array Lab

Vanilla HTML, JavaScript, and CSS provide the browser interface. The Python bridge runs in the PYNQ-Z2 Python environment and calls the existing pynq/adaptive_gemm.py driver; it does not reimplement DMA or register transactions.

## Hardware contract

- Signed INT8 matrix inputs, with each value in the range -128 to 127.
- Each hardware invocation handles one tile up to 16 × 16 × 16. The existing driver tiles larger M, K, and N dimensions.
- Results are returned as signed INT32 values. Host accumulation follows the existing driver's INT32 wrap behavior.
- The visualization shows the two 16 × 16 meshes and their real west-to-east A and north-to-south B topology. The pulsing effect is illustrative: the RTL does not expose per-PE telemetry.
- The UI only shows a hardware result when the driver reports HARDWARE_MEASURED. A software-reference fallback is rejected by the bridge.

## Required board files

The bridge requires a generated .bit file and its matching .hwh metadata file in the same directory on the PYNQ-Z2. It also needs the existing project driver's pynq/adaptive_gemm.py and the PYNQ Python runtime with NumPy. No bitstream or matching HWH was present in the inspected project, and physical-board operation has not been verified. The UI therefore reports the overlay as unavailable until those files are built and loaded successfully.

Copy this webpage directory and the project source directory containing pynq/adaptive_gemm.py to the PYNQ-Z2. Keep the bitstream and matching HWH together. Use the PYNQ board's private IPv4 LAN address as the bind address; the bridge rejects wildcard and public binds. Keep it on a trusted local network and do not configure router port forwarding.

## Serve both page and bridge from the PYNQ-Z2

In the board's PYNQ Python environment, run:

    python3 bridge/server.py --bind 192.168.1.50 --port 8765 --project-root /home/xilinx/antigravity --bitstream /home/xilinx/overlays/adaptive_gemm.bit

Replace the private IP and paths with the board's actual address and deployed file locations. Open http://192.168.1.50:8765 in a browser on the same trusted local network. The page and API share an origin.

## Serve the page on Windows and the bridge on the board

On the PYNQ-Z2, bind the bridge to its private LAN address and allow the exact page origin:

    python3 bridge/server.py --bind 192.168.1.50 --port 8765 --project-root /home/xilinx/antigravity --bitstream /home/xilinx/overlays/adaptive_gemm.bit --allowed-origin http://localhost:8080 --allowed-origin http://127.0.0.1:8080

On Windows, serve the page directory with Python's static server:

    python -m http.server 8080 --directory "C:\Users\adars\OneDrive\Desktop\hackthon\adaptive_systolic_array_docs\webpage"

Open http://localhost:8080, enter http://192.168.1.50:8765 in the Bridge URL field, then choose Connect. The bridge accepts cross-origin requests only from its configured exact origins and its own same-origin page.

## Browser workflow

1. Connect checks GET /api/status; it does not assume that the PYNQ-Z2 is online.
2. Initialize Overlay loads the configured bitstream and matching HWH through PYNQ.
3. Enter or paste signed INT8 matrices with matching inner dimensions. The host driver handles tiling for dimensions larger than 16.
4. Run on FPGA submits the matrices to POST /api/compute. The button remains disabled while the bridge reports busy.
5. The result appears only after the bridge confirms HARDWARE_MEASURED. The optional reference uses signed INT32 wrap and remains visually separate.
6. Reset pulses the RTL soft-reset register while the accelerator is idle. No cancel control is provided.

The API exposes GET /api/status, POST /api/initialize, POST /api/compute, and POST /api/reset. The bridge serializes hardware actions and returns structured errors for invalid input, busy hardware, missing overlay, timeout, and malformed driver output.

## Local checks

From this directory:

    node --test tests/validation.test.js
    python -m unittest discover -s bridge -p test_server.py
    python -m py_compile bridge/server.py

The Python tests use a fake driver for API/controller behavior; they are not evidence of FPGA operation. Hardware acceptance requires the generated overlay and a PYNQ-Z2 run with known, negative-value, irregular, and multi-tile matrices.
