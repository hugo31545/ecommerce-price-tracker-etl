@echo off
setlocal
REM Prepara o projeto numa maquina nova. Correr com o KNIME fechado.
cd /d "%~dp0..\.."
if not exist "data\logs" mkdir "data\logs"
if not exist "data\output" mkdir "data\output"
if exist "dataintegration\01_extracao\data" (
  echo A ligacao dataintegration\01_extracao\data ja existe.
) else (
  mklink /J "dataintegration\01_extracao\data" "%CD%\data"
)
pause