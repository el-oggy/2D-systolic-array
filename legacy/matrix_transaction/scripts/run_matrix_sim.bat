@echo off
setlocal enabledelayedexpansion

echo ============================================================================
echo   16x16 2D Systolic Array - SystemVerilog OOP Verification Suite
echo   Vivado xvlog / xelab / xsim Automated Simulation Runner
echo ============================================================================

set VIVADO_BIN=C:\Xilinx\2025.1\Vivado\bin
if not exist "%VIVADO_BIN%\xvlog.bat" (
    echo [ERROR] Vivado binary directory not found at: %VIVADO_BIN%
    echo Please update VIVADO_BIN in this script.
    exit /b 1
)

:: Create working directory
if not exist "work" mkdir work
cd work

echo [STEP 1/3] Compiling RTL and OOP Verification Testbench (xvlog -sv)...
call "%VIVADO_BIN%\xvlog.bat" -sv ^
    -i "../../src" ^
    -i "../../tb" ^
    "../../src/systolic_pkg.sv" ^
    "../../src/processing_element.sv" ^
    "../../src/skew_buffer.sv" ^
    "../../src/controller.sv" ^
    "../../src/systolic_array.sv" ^
    "../../src/systolic_top.sv" ^
    "../../tb/tb_matrix_top.sv"
if %errorlevel% neq 0 (
    echo [ERROR] Compilation failed!
    cd ..
    exit /b %errorlevel%
)

echo [STEP 2/3] Elaborating Simulation Snapshot (xelab)...
call "%VIVADO_BIN%\xelab.bat" -debug typical -top tb_matrix_top -snapshot tb_matrix_top_snapshot
if %errorlevel% neq 0 (
    echo [ERROR] Elaboration failed!
    cd ..
    exit /b %errorlevel%
)

echo [STEP 3/3] Running Simulation with Scoreboard (xsim)...
call "%VIVADO_BIN%\xsim.bat" tb_matrix_top_snapshot -R
if %errorlevel% neq 0 (
    echo [ERROR] Simulation failed!
    cd ..
    exit /b %errorlevel%
)

echo ============================================================================
echo   OOP Verification Suite Completed Successfully!
echo ============================================================================
cd ..
exit /b 0
