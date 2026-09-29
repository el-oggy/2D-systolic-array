@echo off
set VIVADO_BIN=C:\Xilinx\2025.1\Vivado\bin
set PROJECT_FILE=%~dp0..\vivado_bd_proj\systolic_16x16_bd_proj.xpr

if not exist "%VIVADO_BIN%\vivado.bat" (
    echo [ERROR] Vivado binary directory not found at: %VIVADO_BIN%
    pause
    exit /b 1
)

if not exist "%PROJECT_FILE%" (
    echo [ERROR] Project file not found at: %PROJECT_FILE%
    echo Please run simulation\scripts\run_block_design.bat first to generate the Block Design project.
    pause
    exit /b 1
)

echo Opening Vivado Block Design project: %PROJECT_FILE%...
start "" "%VIVADO_BIN%\vivado.bat" "%PROJECT_FILE%"
exit /b 0
