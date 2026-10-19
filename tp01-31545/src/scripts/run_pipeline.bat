@echo off
setlocal
REM Executa o pipeline sem interface (NodePit Batch).
REM Caminhos relativos a raiz do projeto (dois niveis acima deste script).
cd /d "%~dp0..\.."
set "KNIME_EXE=%LOCALAPPDATA%\Programs\KNIME\knime.exe"

docker info >nul 2>&1
if errorlevel 1 (
  echo [%date% %time%] ERRO: o Docker Desktop nao esta a correr.
  exit /b 1
)
docker compose -f "src\docker\docker-compose.yml" up -d
REM Espera ~5 s pelo PostgreSQL (ping funciona tambem quando chamado pelo Node-RED)
ping -n 6 127.0.0.1 >nul

echo [%date% %time%] Inicio da execucao do pipeline
start "" /wait "%KNIME_EXE%" -nosplash -consoleLog --launcher.suppressErrors ^
  -data "%CD%" ^
  -application com.nodepit.batch.application.NodePitBatchExecutor ^
  -r --no-save ^
  "%CD%\dataintegration\01_extracao"
set "RC=%ERRORLEVEL%"
echo [%date% %time%] Fim (codigo %RC%)
exit /b %RC%