@echo off
setlocal
rem Project-local sbt launcher. The version comes from project/build.properties.

if defined JAVA_HOME (
    set "JAVA_CMD=%JAVA_HOME%\bin\java.exe"
) else (
    set "JAVA_CMD=java.exe"
)

pushd "%~dp0"
if errorlevel 1 exit /b 1
"%JAVA_CMD%" -Xms256m -Xmx2g -Xss4m -jar "%~dp0project\sbt-launch.jar" %*
set "EXIT_CODE=%ERRORLEVEL%"
popd
endlocal & exit /b %EXIT_CODE%
