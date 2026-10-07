@echo off
title Adaptive Systolic Array - Web Lab Interface
echo ======================================================================
echo   OPENING ADAPTIVE SYSTOLIC ARRAY HARDWARE WEB LAB
echo ======================================================================
echo.
echo Target PYNQ-Z2 Address: http://192.168.2.99:8765/
echo Hardware Status: 512 MACs, 220 DSPs (Dual-Engine GEMM Accelerator)
echo.
echo Launching your default browser...
start http://192.168.2.99:8765/
echo.
echo Done. Press any key to close this window.
pause >nul
