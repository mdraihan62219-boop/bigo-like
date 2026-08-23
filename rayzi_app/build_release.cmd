@echo off
REM Local release APK build with integration credentials.
REM Set these before running (or put them in your environment):
REM   set GOOGLE_WEB_CLIENT_ID=<id>.apps.googleusercontent.com
REM   set AGORA_APP_ID=<your-agora-app-id>
REM Values left empty produce a build that surfaces clean "not configured"
REM states instead of crashing — safe for UI testing without credentials.

setlocal
cd /d "%~dp0"

if "%GOOGLE_WEB_CLIENT_ID%"=="" echo [warn] GOOGLE_WEB_CLIENT_ID not set - Google sign-in will show "not configured"
if "%AGORA_APP_ID%"=="" echo [warn] AGORA_APP_ID not set - live streaming/calls will show "not configured"

flutter build apk --release ^
  --dart-define=GOOGLE_WEB_CLIENT_ID=%GOOGLE_WEB_CLIENT_ID% ^
  --dart-define=AGORA_APP_ID=%AGORA_APP_ID%

if %ERRORLEVEL%==0 (
  copy /Y "build\app\outputs\flutter-apk\app-release.apk" "..\PHM-Live.apk" >nul
  echo Done: ..\PHM-Live.apk
)
endlocal
