@echo off
setlocal
echo ==============================================================================
echo   PYNQ-Z2 16x16 Systolic Array Accelerator - 1-Click Bitstream Builder
echo ==============================================================================
echo.

set "VIVADO_BIN=C:\Xilinx\2025.1\Vivado\bin\vivado.bat"
if not exist "%VIVADO_BIN%" (
    where vivado >nul 2>nul
    if %errorlevel% equ 0 (
        set "VIVADO_BIN=vivado"
    ) else (
        echo [ERROR] Vivado executable not found at C:\Xilinx\2025.1\Vivado\bin\vivado.bat or in PATH!
        echo Please ensure Xilinx Vivado is installed.
        pause
        exit /b 1
    )
)

echo [INFO] Using Vivado from: %VIVADO_BIN%
echo [INFO] Starting synthesis, implementation, and bitstream generation...
echo.

call "%VIVADO_BIN%" -mode batch -source "%~dp0build_bitstream.tcl" -nolog -nojournal

if %errorlevel% equ 0 (
    echo.
    echo ==============================================================================
    echo [SUCCESS] Bitstream generation completed successfully!
    echo Output bitstream: %~dp0pynq_z2_systolic_16x16.bit
    echo ==============================================================================
) else (
    echo.
    echo ==============================================================================
    echo [FAILURE] Bitstream generation failed. Please inspect the log above for errors.
    echo ==============================================================================
)

echo.
pause
