@echo off
setlocal EnableExtensions
cd /d "%~dp0\.."

echo ============================================================
echo MX64 - Windows CMD setup and ALU smoke test
echo ============================================================
echo.

REM If Icarus is already on PATH, use it directly.
where iverilog >nul 2>nul
if not errorlevel 1 (
  where vvp >nul 2>nul
  if not errorlevel 1 goto RUN_TEST
)

REM Try a user-supplied OSS CAD Suite root first.
if defined OSS_CAD_SUITE (
  if exist "%OSS_CAD_SUITE%\environment.bat" (
    call "%OSS_CAD_SUITE%\environment.bat"
    goto CHECK_TOOLS
  )
)

REM Common extraction locations. The suite can be extracted anywhere.
for %%D in (
  "C:\tools\oss-cad-suite"
  "%USERPROFILE%\Downloads\oss-cad-suite"
  "%USERPROFILE%\oss-cad-suite"
  "%ProgramFiles%\oss-cad-suite"
  "%~dp0..\tools\oss-cad-suite"
) do (
  if exist "%%~D\environment.bat" (
    call "%%~D\environment.bat"
    goto CHECK_TOOLS
  )
)

echo OSS CAD Suite was not found in the common locations.
echo Enter the FULL folder path that contains environment.bat.
echo Example: C:\Users\mushfiqur\Downloads\oss-cad-suite
set /p "SUITE_DIR=OSS CAD Suite folder: "

if not defined SUITE_DIR (
  echo ERROR: No folder was entered.
  exit /b 2
)
if not exist "%SUITE_DIR%\environment.bat" (
  echo ERROR: environment.bat was not found at:
  echo "%SUITE_DIR%\environment.bat"
  echo Check the folder you extracted from the ZIP.
  exit /b 2
)

call "%SUITE_DIR%\environment.bat"

:CHECK_TOOLS
where iverilog >nul 2>nul
if errorlevel 1 (
  echo ERROR: iverilog is still not available after environment setup.
  exit /b 3
)
where vvp >nul 2>nul
if errorlevel 1 (
  echo ERROR: vvp is still not available after environment setup.
  exit /b 3
)

echo.
echo Detected simulator versions:
iverilog -V
vvp -V

:RUN_TEST
echo.
echo [1/2] Compiling MX64 integer ALU testbench...
if not exist build mkdir build
iverilog -g2012 -Wall -s tb_integer_alu -o build\tb_integer_alu.vvp ^
  rtl\common\mx64_pkg.sv ^
  rtl\execution\integer_alu.sv ^
  verification\unit\tb_integer_alu.sv

if errorlevel 1 (
  echo FAIL: Icarus Verilog compilation failed.
  exit /b 4
)

echo.
echo [2/2] Running MX64 integer ALU testbench...
vvp build\tb_integer_alu.vvp
if errorlevel 1 (
  echo FAIL: MX64 integer ALU simulation failed.
  exit /b 5
)

echo.
echo PASS: MX64 ALU smoke test completed.
echo NOTE: This is an ALU unit test, not full-CPU verification.
exit /b 0
