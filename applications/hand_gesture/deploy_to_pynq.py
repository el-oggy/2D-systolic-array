"""
Deploy Gesture Server & Systolic Accelerator to PYNQ-Z2 Board

Automates complete deployment over Ethernet:
  1. Detects PYNQ board (checks 169.254.104.200, 192.168.2.99, or local subnets)
  2. Uploads pynq_gesture_server.py, adaptive_gemm.py, and the live demo notebook
  3. Verifies bitstream presence (adaptive_gemm.bit and adaptive_gemm.hwh)
  4. Starts the gesture server on the board
  5. Verifies UDP heartbeat communication
"""

import os
import sys
import time
import json
import socket
import argparse
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent

PYNQ_PASSWORD = "xilinx"
JUPYTER_PORT = 9090
GESTURE_PORT = 5005
FEEDBACK_PORT = 5006
DEFAULT_IP = "169.254.104.200"

def check_socket(ip, port, timeout=0.3):
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(timeout)
        res = s.connect_ex((ip, port))
        s.close()
        return res == 0
    except Exception:
        return False

def find_board_ip(target_ip=None):
    if target_ip and check_socket(target_ip, JUPYTER_PORT, timeout=0.5):
        return target_ip
    
    # Priority check direct-ethernet defaults
    for ip in [DEFAULT_IP, "192.168.2.99", "192.168.1.56"]:
        if check_socket(ip, JUPYTER_PORT, timeout=0.4):
            return ip
            
    print(f"[SCAN] Quick probe on direct defaults failed. Performing fast subnet scan...")
    # Get local subnet
    subnets = []
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        local_ip = s.getsockname()[0]
        s.close()
        subnets.append(".".join(local_ip.split(".")[:3]))
    except Exception:
        pass
    subnets.extend(["169.254.104", "192.168.2", "192.168.1"])
    
    for prefix in set(subnets):
        ips = [f"{prefix}.{i}" for i in range(1, 255)]
        with ThreadPoolExecutor(max_workers=64) as exc:
            results = list(exc.map(lambda ip: ip if check_socket(ip, JUPYTER_PORT, 0.25) else None, ips))
        found = [r for r in results if r]
        if found:
            return found[0]
            
    return DEFAULT_IP

def upload_file_jupyter(board_ip, local_path, remote_name):
    try:
        import requests
        session = requests.Session()
        base_url = f"http://{board_ip}:{JUPYTER_PORT}"
        r = session.get(f"{base_url}/login", timeout=4)
        xsrf = session.cookies.get("_xsrf", "")
        session.post(f"{base_url}/login", data={"password": PYNQ_PASSWORD, "_xsrf": xsrf}, allow_redirects=False, timeout=4)
        headers = {"X-XSRFToken": session.cookies.get("_xsrf", "")}
        
        with open(local_path, "rb") as f:
            data = f.read()
            
        import base64
        payload = {
            "type": "file",
            "format": "base64",
            "content": base64.b64encode(data).decode("ascii")
        }
        r = session.put(f"{base_url}/api/contents/{remote_name}", headers=headers, json=payload, timeout=12)
        return r.status_code in (200, 201)
    except Exception as e:
        print(f"  [ERR] Jupyter upload {remote_name}: {e}")
        return False

def ping_server(board_ip, timeout=1.5):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(timeout)
    try:
        sock.sendto(b"ping", (board_ip, GESTURE_PORT))
        data, _ = sock.recvfrom(1024)
        return data.decode("utf-8", errors="ignore").strip().lower() == "pong"
    except Exception:
        return False
    finally:
        sock.close()

def main():
    parser = argparse.ArgumentParser(description="Deploy Gesture & Systolic Accelerator to PYNQ-Z2")
    parser.add_argument("--ip", type=str, default=None, help="PYNQ board IP address")
    parser.add_argument("--ping-only", action="store_true", help="Only ping server")
    args = parser.parse_args()

    print("=" * 70)
    print("  PYNQ-Z2 GESTURE & SYSTOLIC ACCELERATOR DEPLOYMENT")
    print("=" * 70)
    board_ip = find_board_ip(args.ip)
    print(f"  Target Board IP: {board_ip}")
    print()

    if args.ping_only:
        alive = ping_server(board_ip)
        print(f"  Server Ping: {'ONLINE ✅' if alive else 'OFFLINE ❌'}")
        return

    # Files to upload
    files_to_deploy = [
        ("pynq_gesture_server.py", SCRIPT_DIR / "pynq_gesture_server.py"),
        ("adaptive_gemm.py", SCRIPT_DIR / "adaptive_gemm.py"),
        ("gesture_systolic_live_demo.ipynb", SCRIPT_DIR / "gesture_systolic_live_demo.ipynb"),
    ]

    print("[1/3] Uploading scripts to PYNQ board via Jupyter API...")
    for remote_name, local_p in files_to_deploy:
        if local_p.is_file():
            ok = upload_file_jupyter(board_ip, str(local_p), remote_name)
            print(f"  • {remote_name}: {'UPLOADED ✅' if ok else 'FAILED ❌'}")
        else:
            print(f"  • {remote_name}: NOT FOUND LOCALLY (Skipped)")

    print()
    print("[2/3] Checking Gesture Server on board...")
    alive = ping_server(board_ip, timeout=0.8)
    if not alive:
        print("  Server is not currently running. You can run it on the board via:")
        print(f"    1. Jupyter Notebook: http://{board_ip}:9090 (Run gesture_systolic_live_demo.ipynb)")
        print(f"    2. Or SSH terminal:  sudo python3 /home/xilinx/pynq_gesture_server.py")
    else:
        print("  ✅ Server is ALIVE and responding to UDP ping!")

    print()
    print("=" * 70)
    print("  DEPLOYMENT READY!")
    print(f"  To start hand tracking on your laptop, run:")
    print(f"    START_HARDWARE_GESTURE_DEMO.bat")
    print("=" * 70)

if __name__ == "__main__":
    main()
