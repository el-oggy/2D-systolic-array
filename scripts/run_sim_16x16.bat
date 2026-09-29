@echo off
setlocal enabledelayedexpansion

echo ===============================================================================
echo   RUNNING 16x16 SYSTOLIC ARRAY HARDWARE ACCELERATOR SIMULATION
echo   Target: Standalone 16x16 Top-Level Verification
echo ===============================================================================

set "SCRIPT_DIR=%~dp0"
set "REPO_ROOT=%SCRIPT_DIR%.."
set "WORK_DIR=%REPO_ROOT%\sim_work_16x16"

if not exist "%WORK_DIR%" mkdir "%WORK_DIR%"
cd /d "%WORK_DIR%"

if exist "C:\Xilinx\2025.1\Vivado\settings64.bat" (
    call "C:\Xilinx\2025.1\Vivado\settings64.bat" >nul 2>&1
) else if exist "C:\Xilinx\Vivado\2025.1\settings64.bat" (
    call "C:\Xilinx\Vivado\2025.1\settings64.bat" >nul 2>&1
) else (
    where xvlog >nul 2>&1
    if errorlevel 1 (
        echo [ERROR] Vivado 2025.1 environment not found!
        echo Please ensure Vivado is installed at C:\Xilinx\2025.1\Vivado
        exit /b 1
    )
)

echo [1/3] Compiling Synthesizable RTL and Testbench...
call xvlog --incr --relax -sv ^
    "%REPO_ROOT%\rtl\systolic_pkg.sv" ^
    "%REPO_ROOT%\rtl\processing_element.sv" ^
    "%REPO_ROOT%\rtl\skew_buffer.sv" ^
    "%REPO_ROOT%\rtl\systolic_array.sv" ^
    "%REPO_ROOT%\rtl\controller.sv" ^
    "%REPO_ROOT%\rtl\systolic_top.sv" ^
    "%REPO_ROOT%\tb\unit\tb_step6_systolic_16x16.sv"
if errorlevel 1 (
    echo [ERROR] Compilation failed!
    exit /b 1
)

echo [2/3] Elaborating Design Snapshot...
call xelab --incr --relax --debug typical tb_step6_systolic_16x16 -s sim_16x16_snapshot
if errorlevel 1 (
    echo [ERROR] Elaboration failed!
    exit /b 1
)

echo [3/3] Executing Simulation in Vivado XSim...
call xsim sim_16x16_snapshot -R

echo ===============================================================================
echo   SIMULATION COMPLETE!
echo ===============================================================================
endlocal
