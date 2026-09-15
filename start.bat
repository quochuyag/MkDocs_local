@echo off
REM ============================================================
REM  Bam dup vao file nay de chay MkDocs local.
REM  Cach dung tu cmd:
REM     start.bat              -> chay server (port 8000)
REM     start.bat sync         -> dong bo lai bai hoc roi chay
REM     start.bat 8080         -> chay o port 8080
REM     start.bat sync 8080    -> dong bo + chay o port 8080
REM ============================================================

setlocal
cd /d "%~dp0"

set "SYNC="
set "PORT=8000"

:parse
if "%~1"=="" goto run
if /i "%~1"=="sync"  (set "SYNC=-Sync" & shift & goto parse)
if /i "%~1"=="-sync" (set "SYNC=-Sync" & shift & goto parse)
echo %~1| findstr /r "^[0-9][0-9]*$" >nul
if not errorlevel 1 (set "PORT=%~1" & shift & goto parse)
echo.
echo  [!] Tham so khong hieu: %~1
echo      Cach dung: start.bat [sync] [port]
echo.
pause
exit /b 1

:run
echo.
echo  Dang khoi dong MkDocs tai http://127.0.0.1:%PORT%
echo  Trinh duyet tu mo khi server san sang (lan build dau ~30s).
echo  Ctrl+C de dung server.
echo.

REM Mo trinh duyet o tien trinh rieng: cho den khi server thuc su len roi moi mo.
REM (Lan build dau ~30s vi site co gan 600 bai.)
start "" /b powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "$u='http://127.0.0.1:%PORT%/'; for($i=0;$i -lt 180;$i++){ try{ $null=Invoke-WebRequest $u -UseBasicParsing -TimeoutSec 2; Start-Process $u; break }catch{ Start-Sleep -Seconds 1 } }"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0serve.ps1" %SYNC% -Port %PORT%

echo.
echo  Server da dung. Bam phim bat ky de dong cua so.
pause >nul
endlocal
