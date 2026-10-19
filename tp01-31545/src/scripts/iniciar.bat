@echo off
setlocal
cd /d "%~dp0..\.."
docker info >nul 2>&1
if errorlevel 1 (
  echo Abre primeiro o Docker Desktop e volta a correr este script.
  pause
  exit /b 1
)
docker compose -f "src\docker\docker-compose.yml" up -d
start "Node-RED" /D "%CD%\src\node-red" cmd /k node-red "%CD%\src\node-red\flows.json"
echo.
echo Servicos ligados:
echo   Grafana   http://localhost:3000
echo   Mailpit   http://localhost:8025
echo   Node-RED  http://localhost:1880
echo   PostgreSQL localhost:5432  ^|  SFTP localhost:2222
pause