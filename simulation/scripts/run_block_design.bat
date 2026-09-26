@echo off
echo ============================================================================
echo   Creating Vivado IP Integrator Block Design (systolic_16x16_bd)
echo ============================================================================

set VIVADO_BIN=C:\Xilinx\2025.1\Vivado\bin
if not exist "%VIVADO_BIN%\vivado.bat" (
    echo [ERROR] Vivado not found at: %VIVADO_BIN%
    exit /b 1
)

call "%VIVADO_BIN%\vivado.bat" -mode batch -source create_block_design.tcl
if %errorlevel% neq 0 (
    echo [ERROR] Block design creation failed!
    exit /b %errorlevel%
)

echo ============================================================================
echo   Block Design Created Successfully!
echo ============================================================================
exit /b 0
