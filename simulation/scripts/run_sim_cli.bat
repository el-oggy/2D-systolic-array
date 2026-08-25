@echo off
setlocal enabledelayedexpansion

echo ============================================================================
echo   2D Systolic Array - Vivado Automated Simulation Runner
echo ============================================================================

:: Locate Vivado installation
set VIVADO_BIN=C:\Xilinx\2025.1\Vivado\bin
if not exist "%VIVADO_BIN%\xvlog.bat" (
    echo [ERROR] Vivado not found at %VIVADO_BIN%. Please edit this script with your Vivado path.
    exit /b 1
)

set WORKDIR=%~dp0\..\work
if not exist "%WORKDIR%" mkdir "%WORKDIR%"
cd /d "%WORKDIR%"

echo [1/5] Compiling Design Sources into SystemVerilog Work Library...
call "%VIVADO_BIN%\xvlog.bat" -sv -relax ^
    "%~dp0\..\src\processing_element.sv" ^
    "%~dp0\..\src\systolic_array.sv" ^
    "%~dp0\..\src\skew_buffer.sv" ^
    "%~dp0\..\src\controller.sv" ^
    "%~dp0\..\src\systolic_top.sv"
if %errorlevel% neq 0 (
    echo [ERROR] Design compilation failed!
    exit /b %errorlevel%
)

echo.
echo [2/5] Compiling Testbenches...
call "%VIVADO_BIN%\xvlog.bat" -sv -relax ^
    "%~dp0\..\sim\tb_step1_pe.sv" ^
    "%~dp0\..\sim\tb_step2_systolic_2x2.sv" ^
    "%~dp0\..\sim\tb_step3_skew_buffer.sv" ^
    "%~dp0\..\sim\tb_step4_systolic_4x4.sv"
if %errorlevel% neq 0 (
    echo [ERROR] Testbench compilation failed!
    exit /b %errorlevel%
)

echo.
echo ============================================================================
echo   RUNNING STEP 1: Single Processing Element Verification (tb_step1_pe)
echo ============================================================================
call "%VIVADO_BIN%\xelab.bat" -timescale 1ns/1ps -debug typical tb_step1_pe -s sim_step1
call "%VIVADO_BIN%\xsim.bat" sim_step1 -R

echo.
echo ============================================================================
echo   RUNNING STEP 2: 2x2 Systolic Array Grid Test (tb_step2_systolic_2x2)
echo ============================================================================
call "%VIVADO_BIN%\xelab.bat" -timescale 1ns/1ps -debug typical tb_step2_systolic_2x2 -s sim_step2
call "%VIVADO_BIN%\xsim.bat" sim_step2 -R

echo.
echo ============================================================================
echo   RUNNING STEP 3: Skew Buffer Delay Stagger Test (tb_step3_skew_buffer)
echo ============================================================================
call "%VIVADO_BIN%\xelab.bat" -timescale 1ns/1ps -debug typical tb_step3_skew_buffer -s sim_step3
call "%VIVADO_BIN%\xsim.bat" sim_step3 -R

echo.
echo ============================================================================
echo   RUNNING STEP 4: 4x4 Systolic Top Integrated Test (tb_step4_systolic_4x4)
echo ============================================================================
call "%VIVADO_BIN%\xelab.bat" -timescale 1ns/1ps -debug typical tb_step4_systolic_4x4 -s sim_step4
call "%VIVADO_BIN%\xsim.bat" sim_step4 -R

echo.
echo ============================================================================
echo   ALL SIMULATION STEPS FINISHED SUCCESSFULLY!
echo ============================================================================
pause
