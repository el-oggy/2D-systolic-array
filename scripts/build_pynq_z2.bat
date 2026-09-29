@echo off
setlocal enabledelayedexpansion

echo ===============================================================================
echo   BUILDING PYNQ-Z2 HARDWARE BITSTREAM (Vivado Batch Mode)
echo   Target Part: xc7z020clg400-1 (TUL PYNQ-Z2)
echo ===============================================================================

set "SCRIPT_DIR=%~dp0"
set "REPO_ROOT=%SCRIPT_DIR%.."

if exist "C:\Xilinx\2025.1\Vivado\settings64.bat" (
    call "C:\Xilinx\2025.1\Vivado\settings64.bat" >nul 2>&1
) else if exist "C:\Xilinx\Vivado\2025.1\settings64.bat" (
    call "C:\Xilinx\Vivado\2025.1\settings64.bat" >nul 2>&1
) else (
    where vivado >nul 2>&1
    if errorlevel 1 (
        echo [ERROR] Vivado 2025.1 environment not found!
        exit /b 1
    )
)

echo Launching Vivado to build bitstream...
call vivado -mode batch -source "%REPO_ROOT%\boards\pynq_z2\build_pynq_z2_bitstream.tcl" -notrace

echo ===============================================================================
echo   BATCH BUILD FINISHED!
echo ===============================================================================
endlocal
