@echo off
rem ==============================================
rem  Tutor Fiscal - abre o app em janela propria
rem  (modo aplicativo do Edge ou Chrome)
rem ==============================================
setlocal
set "APPDIR=%~dp0"
set "APPURL=file:///%APPDIR:\=/%index.html"

where msedge >nul 2>nul
if %errorlevel%==0 (
  start "" msedge --app="%APPURL%"
  exit /b
)
where chrome >nul 2>nul
if %errorlevel%==0 (
  start "" chrome --app="%APPURL%"
  exit /b
)
rem Fallback: navegador padrao em aba comum
start "" "%APPDIR%index.html"
