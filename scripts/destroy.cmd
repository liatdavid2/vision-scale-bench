@echo off
setlocal
cd /d "%~dp0\.."
echo Destroying Vision Scale Bench AWS resources...
docker compose exec backend bash scripts/destroy.sh
if errorlevel 1 exit /b %errorlevel%
echo Done.
