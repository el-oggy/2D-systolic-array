@echo off
setlocal enabledelayedexpansion

echo ===============================================================================
echo   RUNNING OOP SYSTEMVERILOG RANDOMIZED VERIFICATION SUITE
echo   Methodology: Transaction, Generator, Driver, Monitor, Scoreboard
echo   Scale: 16x16 Systolic Grid (256 Processing Elements)
echo ===============================================================================

set "SCRIPT_DIR=%~dp0"
set "REPO_ROOT=%SCRIPT_DIR%.."
set "WORK_DIR=%REPO_ROOT%\sim_work_oop"

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
        exit /b 1
    )
)

echo [1/3] Compiling RTL and OOP Verification Classes...
call xvlog --incr --relax -sv ^
    "%REPO_ROOT%\rtl\systolic_pkg.sv" ^
    "%REPO_ROOT%\rtl\processing_element.sv" ^
    "%REPO_ROOT%\rtl\skew_buffer.sv" ^
    "%REPO_ROOT%\rtl\systolic_array.sv" ^
    "%REPO_ROOT%\rtl\controller.sv" ^
    "%REPO_ROOT%\rtl\systolic_top.sv" ^
    "%REPO_ROOT%\tb\oop\matrix_if.sv" ^
    "%REPO_ROOT%\tb\oop\MatrixTransaction.sv" ^
    "%REPO_ROOT%\tb\oop\MatrixGenerator.sv" ^
    "%REPO_ROOT%\tb\oop\MatrixDriver.sv" ^
    "%REPO_ROOT%\tb\oop\MatrixMonitor.sv" ^
    "%REPO_ROOT%\tb\oop\MatrixScoreboard.sv" ^
    "%REPO_ROOT%\tb\oop\MatrixEnvironment.sv" ^
    "%REPO_ROOT%\tb\oop\tb_matrix_top.sv"
if errorlevel 1 (
    echo [ERROR] Compilation failed!
    exit /b 1
)

echo [2/3] Elaborating Design Snapshot...
call xelab --incr --relax --debug typical tb_matrix_top -s oop_sim_snapshot
if errorlevel 1 (
    echo [ERROR] Elaboration failed!
    exit /b 1
)

echo [3/3] Executing 30-Transaction Randomized Verification in XSim...
call xsim oop_sim_snapshot -R

echo ===============================================================================
echo   OOP VERIFICATION COMPLETE!
echo ===============================================================================
endlocal
