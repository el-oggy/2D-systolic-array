@echo off
setlocal enabledelayedexpansion

echo ===============================================================================
echo   OPENING PYNQ-Z2 VIVADO PROJECT (GUI Mode)
echo ===============================================================================

set "SCRIPT_DIR=%~dp0"
set "REPO_ROOT=%SCRIPT_DIR%.."
set "PROJ_FILE=%REPO_ROOT%\boards\pynq_z2\pynq_z2_vivado_proj\systolic_16x16_pynq_z2.xpr"

if exist "C:\Xilinx\2025.1\Vivado\settings64.bat" (
    call "C:\Xilinx\2025.1\Vivado\settings64.bat" >nul 2>&1
) else if exist "C:\Xilinx\Vivado\2025.1\settings64.bat" (
    call "C:\Xilinx\Vivado\2025.1\settings64.bat" >nul 2>&1
)

if exist "%PROJ_FILE%" (
    echo Opening existing PYNQ-Z2 project: %PROJ_FILE%
    start vivado "%PROJ_FILE%"
) else (
    echo Project does not exist yet. Creating and opening now...
    start vivado -mode tcl -source "%REPO_ROOT%\boards\pynq_z2\create_pynq_z2_proj.tcl"
)

endlocal
