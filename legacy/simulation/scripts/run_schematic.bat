@echo off
echo ============================================================================
echo   Elaborating RTL Schematic and Generating Netlist Reports
echo ============================================================================

set VIVADO_BIN=C:\Xilinx\2025.1\Vivado\bin
if not exist "%VIVADO_BIN%\vivado.bat" (
    echo [ERROR] Vivado not found at: %VIVADO_BIN%
    exit /b 1
)

call "%VIVADO_BIN%\vivado.bat" -mode batch -source generate_schematic.tcl
if %errorlevel% neq 0 (
    echo [ERROR] Schematic generation failed!
    exit /b %errorlevel%
)

echo ============================================================================
echo   Schematic and Reports Generated Successfully in simulation/reports/
echo ============================================================================
exit /b 0
