@echo off
setlocal
cd /d "%~dp0\.."

if not exist build mkdir build

where iverilog >nul 2>nul
if errorlevel 1 (
  echo ERROR: iverilog was not found.
  echo Open this CMD after running OSS CAD Suite environment.bat
  exit /b 1
)

where vvp >nul 2>nul
if errorlevel 1 (
  echo ERROR: vvp was not found. Check your OSS CAD Suite installation.
  exit /b 1
)

echo [1/2] Compiling MX64 integer ALU testbench...
iverilog -g2012 -Wall -s tb_integer_alu -o build\tb_integer_alu.vvp ^
  rtl\common\mx64_pkg.sv ^
  rtl\execution\integer_alu.sv ^
  verification\unit\tb_integer_alu.sv

if errorlevel 1 (
  echo FAIL: Icarus Verilog compilation failed.
  exit /b 1
)

echo.
echo [2/2] Running MX64 integer ALU testbench...
vvp build\tb_integer_alu.vvp

if errorlevel 1 (
  echo FAIL: MX64 integer ALU simulation failed.
  exit /b 1
)

echo.
echo PASS: MX64 integer ALU simulation completed.
exit /b 0
