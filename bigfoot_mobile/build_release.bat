@echo off
cd /d d:\BigFoot\bigfoot_mobile
echo Current directory: %cd%
echo Checking for pubspec.yaml...
dir pubspec.yaml
echo.
echo Starting Flutter release build...
flutter build apk --release --no-tree-shake-icons --dart-define=API_BASE_URL=https://bigfoot.206-189-190-150.sslip.io/v1 --dart-define=WS_URL=wss://bigfoot.206-189-190-150.sslip.io/ws
echo Build completed with exit code: %ERRORLEVEL%
pause
