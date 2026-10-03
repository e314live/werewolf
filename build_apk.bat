@echo off
REM 宿舍狼人杀 —— 一键出 APK（双击运行即可）
setlocal

set JAVA_HOME=D:\jdk\jdk-17.0.20.1+1
set ANDROID_HOME=D:\Android\Sdk
set PUB_HOSTED_URL=https://mirrors.tuna.tsinghua.edu.cn/dart-pub
set PATH=D:\Dev\flutter\bin;%PATH%

cd /d D:\Dev\Werewolf

echo.
echo [1/3] 拉取依赖...
flutter pub get
if errorlevel 1 goto failed

echo.
echo [2/3] 编译 release APK...
flutter build apk --release --split-per-abi
if errorlevel 1 goto failed

echo.
echo [3/3] 完成！
echo.
echo   APK 在这里：
for /f "delims=" %%f in ('dir /b /s build\app\outputs\apk\release\*.apk') do echo     %%f
echo.
echo   传到手机后直接安装；或在这个目录执行：
echo     adb install app-release.apk
echo.
pause
exit /b 0

:failed
echo.
echo 构建失败，把上面的报错发给我看看。
pause
exit /b 1
