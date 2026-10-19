@echo off
setlocal
cd /d "%~dp0..\.."
taskkill /FI "WINDOWTITLE eq Node-RED*" /T /F >nul 2>&1
docker compose -f "src\docker\docker-compose.yml" stop
echo Servicos parados. Os dados ficam guardados.
pause