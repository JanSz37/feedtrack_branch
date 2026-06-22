@echo off
chcp 65001 >nul 2>&1
setlocal EnableDelayedExpansion

set "REGISTRY=download.feedtrack.pl"
set "NGINX_IMAGE=download.feedtrack.pl/feedtrack/feedtrack_branch:nginx"
set "COMPOSE_FILE=docker-compose.client.yml"
set "ENV_EXAMPLE=env.example"
set "ENV_FILE=.env"
set "CERTS_DIR=certs"

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
set /p "APP_PORT=Na jakim porcie HTTP (przekierowanie na HTTPS)? (domyslnie 80): "
if "!APP_PORT!"=="" set "APP_PORT=80"
for /f "delims=0123456789" %%i in ("!APP_PORT!") do (
    echo [BLAD] '!APP_PORT!' to nie jest liczba.
    goto :error_exit
)

set /p "HTTPS_PORT=Na jakim porcie HTTPS? (domyslnie 443): "
if "!HTTPS_PORT!"=="" set "HTTPS_PORT=443"
for /f "delims=0123456789" %%i in ("!HTTPS_PORT!") do (
    echo [BLAD] '!HTTPS_PORT!' to nie jest liczba.
    goto :error_exit
)

set /p "SERVER_NAME=Pod jaka nazwa hosta / adresem IP bedzie dostepna aplikacja? (domyslnie localhost): "
if "!SERVER_NAME!"=="" set "SERVER_NAME=localhost"

set "NEW_CSRF=https://!SERVER_NAME!:!HTTPS_PORT!"
if "!HTTPS_PORT!"=="443" set "NEW_CSRF=https://!SERVER_NAME!"

call :set_env "APP_PORT" "!APP_PORT!"
call :set_env "HTTPS_PORT" "!HTTPS_PORT!"
call :set_env "SERVER_NAME" "!SERVER_NAME!"
call :set_env "CSRF_TRUSTED_ORIGINS" "!NEW_CSRF!"
call :set_env "SECURE_COOKIES" "True"

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

REM Certyfikat musi istniec ZANIM wystartuje nginx (montowany jako wolumen).
call :gen_certs "!SERVER_NAME!"
if %errorlevel% neq 0 goto :error_exit

%COMPOSE_CMD% -f "%COMPOSE_FILE%" up -d

echo.
echo ========================================
echo     Instalacja zakonczona!
echo ========================================
if "!HTTPS_PORT!"=="443" (
    echo [OK]    Aplikacja dziala na: https://!SERVER_NAME!
) else (
    echo [OK]    Aplikacja dziala na: https://!SERVER_NAME!:!HTTPS_PORT!
)
echo [UWAGA] Certyfikat jest self-signed - przegladarka pokaze ostrzezenie.
echo         Zaakceptuj wyjatek lub zaimportuj .\%CERTS_DIR%\fullchain.pem do zaufanych.
pause
exit /b 0

REM ---------- Podprogram: zapis zmiennej do .env (nadpisz lub dopisz) ----------
:set_env
powershell -NoProfile -Command "$f='%ENV_FILE%'; $k='%~1'; $v='%~2'; $c=@(Get-Content $f); if ($c -match ('^'+[regex]::Escape($k)+'=')) { $c = $c -replace ('^'+[regex]::Escape($k)+'=.*'), ($k+'='+$v) } else { $c += ($k+'='+$v) }; Set-Content $f $c"
exit /b 0

REM ---------- Podprogram: generowanie self-signed certyfikatu ----------
:gen_certs
set "GC_HOST=%~1"
if not exist "%CERTS_DIR%" mkdir "%CERTS_DIR%"
if exist "%CERTS_DIR%\fullchain.pem" if exist "%CERTS_DIR%\privkey.pem" (
    echo [OK]    Certyfikat juz istnieje w .\%CERTS_DIR% - pomijam generowanie.
    exit /b 0
)

REM SAN: jesli host wyglada jak IPv4 -> wpis IP, w przeciwnym razie DNS.
echo !GC_HOST!| findstr /r "^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$" >nul
if %errorlevel% equ 0 (
    set "SAN=IP:!GC_HOST!,DNS:localhost,IP:127.0.0.1"
) else (
    set "SAN=DNS:!GC_HOST!,DNS:localhost,IP:127.0.0.1"
)

echo [INFO]  Generuje self-signed certyfikat dla '!GC_HOST!' (SAN: !SAN!)...
docker run --rm -v "%CD%\%CERTS_DIR%:/certs" "%NGINX_IMAGE%" openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout /certs/privkey.pem -out /certs/fullchain.pem -subj "/CN=!GC_HOST!" -addext "subjectAltName=!SAN!"
if %errorlevel% neq 0 (
    echo [BLAD] Nie udalo sie wygenerowac certyfikatu.
    exit /b 1
)
echo [OK]    Certyfikat zapisany w .\%CERTS_DIR% (wazny 10 lat).
exit /b 0

:error_exit
echo.
echo Wystapil blad.
pause
exit /b 1

:clean_exit
pause
exit /b 0