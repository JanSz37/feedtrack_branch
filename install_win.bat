@echo off
chcp 65001 >nul 2>&1
setlocal EnableDelayedExpansion

set "REGISTRY=download.feedtrack.pl"
set "COMPOSE_FILE=docker-compose.client.yml"
set "ENV_EXAMPLE=env.example"
set "ENV_FILE=.env"

echo.
echo ========================================
echo     FeedTrack - Instalacja
echo ========================================
echo.

echo [INFO]  Sprawdzanie wymagan...

where docker >nul 2>&1
if %errorlevel% neq 0 (
    echo [BLAD] Nie znaleziono polecenia 'docker'. Zainstaluj Docker Desktop i uruchom skrypt ponownie.
    goto :error_exit
)
echo [OK]    Znaleziono: docker

docker compose version >nul 2>&1
if %errorlevel% equ 0 (
    echo [OK]    Znaleziono: docker compose (v2)
    set "COMPOSE_CMD=docker compose"
    goto :compose_ok
)

where docker-compose >nul 2>&1
if %errorlevel% equ 0 (
    echo [OK]    Znaleziono: docker-compose (v1)
    set "COMPOSE_CMD=docker-compose"
    goto :compose_ok
)

echo [BLAD] Nie znaleziono 'docker compose' ani 'docker-compose'.
goto :error_exit

:compose_ok
if not exist "%COMPOSE_FILE%" (
    echo [BLAD] Nie znaleziono pliku '%COMPOSE_FILE%'.
    goto :error_exit
)

echo.
if not exist "%ENV_FILE%" (
    if exist "%ENV_EXAMPLE%" (
        echo [INFO]  Tworze plik .env na podstawie %ENV_EXAMPLE%...
        copy "%ENV_EXAMPLE%" "%ENV_FILE%" >nul
        echo [UWAGA] Plik .env zostal utworzony. Uzupelnij go.
        echo.
        set /p "CONTINUE=Czy kontynuowac z domyslnymi wartosciami? (t/N): "
        if /i not "!CONTINUE!"=="t" if /i not "!CONTINUE!"=="y" goto :clean_exit
    ) else (
        echo [BLAD] Nie znaleziono pliku '.env' ani '%ENV_EXAMPLE%'.
        goto :error_exit
    )
) else (
    echo [OK]    Plik .env istnieje.
)

echo.
set /p "APP_PORT=Na jakim porcie uruchomic aplikacje? (domyslnie 80): "
if "!APP_PORT!"=="" set "APP_PORT=80"

for /f "delims=0123456789" %%i in ("!APP_PORT!") do (
    echo [BLAD] '!APP_PORT!' to nie jest liczba.
    goto :error_exit
)

set "NEW_CSRF=http://localhost:!APP_PORT!"
if "!APP_PORT!"=="80" set "NEW_CSRF=http://localhost"

findstr /b "APP_PORT=" "%ENV_FILE%" >nul 2>&1
if %errorlevel% equ 0 (
    powershell -NoProfile -Command "(Get-Content '%ENV_FILE%') -replace '^APP_PORT=.*', 'APP_PORT=!APP_PORT!' | Set-Content '%ENV_FILE%'"
) else (
    echo.>> "%ENV_FILE%" & echo APP_PORT=!APP_PORT!>> "%ENV_FILE%"
)

findstr /b "CSRF_TRUSTED_ORIGINS=" "%ENV_FILE%" >nul 2>&1
if %errorlevel% equ 0 (
    powershell -NoProfile -Command "(Get-Content '%ENV_FILE%') -replace '^CSRF_TRUSTED_ORIGINS=.*', 'CSRF_TRUSTED_ORIGINS=!NEW_CSRF!' | Set-Content '%ENV_FILE%'"
) else (
    echo.>> "%ENV_FILE%" & echo CSRF_TRUSTED_ORIGINS=!NEW_CSRF!>> "%ENV_FILE%"
)

echo.
echo [INFO]  Logowanie do %REGISTRY%...
set /p "HARBOR_KEY=Podaj klucz dostepu (Base64): "

if "!HARBOR_KEY!"=="" goto :error_exit

for /f "tokens=1,* delims=:" %%a in ('powershell -NoProfile -Command "[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('%HARBOR_KEY%'))"') do (
    set "HARBOR_USER=%%a"
    set "HARBOR_PASS=%%b"
)

echo !HARBOR_PASS! | docker login "%REGISTRY%" -u "!HARBOR_USER!" --password-stdin
if %errorlevel% neq 0 (
    echo [BLAD] Logowanie nie powiodlo sie.
    goto :error_exit
)

echo.
echo [INFO]  Pobieranie i uruchamianie...
%COMPOSE_CMD% -f "%COMPOSE_FILE%" pull
%COMPOSE_CMD% -f "%COMPOSE_FILE%" up -d

echo.
echo ========================================
echo     Instalacja zakonczona!
echo ========================================
pause
exit /b 0

:error_exit
echo.
echo Wystapil blad.
pause
exit /b 1

:clean_exit
pause
exit /b 0