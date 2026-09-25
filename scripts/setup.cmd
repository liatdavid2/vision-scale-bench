@echo off
setlocal
cd /d "%~dp0\.."
echo Running one-time AWS GPU setup inside the backend container...
docker compose exec backend bash scripts/setup.sh
if errorlevel 1 exit /b %errorlevel%
echo.
echo Setup complete. Open http://localhost:7475
