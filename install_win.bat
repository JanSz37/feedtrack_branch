@echo off
chcp 65001 >nul 2>&1
setlocal EnableDelayedExpansion

:: ============================================================
::  FeedTrack — Skrypt instalacyjny (Windows)
::
::  Uzycie:
::    Kliknij dwukrotnie lub uruchom w CMD: install.bat
::
::  Klient potrzebuje jedynie:
::    1. Ten skrypt (install.bat)
::    2. docker-compose.client.yml
::    3. .env (skopiowany z env.example i uzupelniony)
:: ============================================================

set "REGISTRY=download.feedtrack.pl"
set "COMPOSE_FILE=docker-compose.client.yml"
set "ENV_EXAMPLE=env.example"
set "ENV_FILE=.env"

echo.
echo ========================================
echo    FeedTrack — Instalacja
echo ========================================
echo.

:: ---------- 1. Sprawdzenie wymagan ----------

echo [INFO]  Sprawdzanie wymagan...

where docker >nul 2>&1
if %errorlevel% neq 0 (
    echo [BLAD] Nie znaleziono polecenia 'docker'. Zainstaluj Docker Desktop i uruchom skrypt ponownie.
    goto :error_exit
)
echo [OK]    Znaleziono: docker

:: Sprawdz docker compose v2
docker compose version >nul 2>&1
if %errorlevel% equ 0 (
    echo [OK]    Znaleziono: docker compose ^(v2^)
    set "COMPOSE_CMD=docker compose"
) else (
    where docker-compose >nul 2>&1
    if %errorlevel% equ 0 (
        echo [OK]    Znaleziono: docker-compose ^(v1^)
        set "COMPOSE_CMD=docker-compose"
    ) else (
        echo [BLAD] Nie znaleziono 'docker compose' ani 'docker-compose'. Zainstaluj Docker Compose.
        goto :error_exit
    )
)

:: Sprawdz compose file
if not exist "%COMPOSE_FILE%" (
    echo [BLAD] Nie znaleziono pliku '%COMPOSE_FILE%' w biezacym katalogu.
    echo        Upewnij sie, ze uruchamiasz skrypt z katalogu instalacyjnego.
    goto :error_exit
)

:: ---------- 2. Plik .env ----------

echo.
if not exist "%ENV_FILE%" (
    if exist "%ENV_EXAMPLE%" (
        echo [INFO]  Tworze plik .env na podstawie %ENV_EXAMPLE%...
        copy "%ENV_EXAMPLE%" "%ENV_FILE%" >nul
        echo [UWAGA] Plik .env zostal utworzony. Otworz go i uzupelnij wartosci:
        echo         - DB_PASSWORD / POSTGRES_PASSWORD
        echo         - SECRET_KEY
        echo         - DJANGO_SUPERUSER_PASSWORD
        echo         - CENTRAL_SYNC_URL i CENTRAL_SYNC_TOKEN
        echo.
        set /p "CONTINUE=Czy kontynuowac instalacje z domyslnymi wartosciami? (t/N): "
        if /i not "!CONTINUE!"=="t" (
            if /i not "!CONTINUE!"=="y" (
                echo [INFO]  Edytuj plik .env, a nastepnie uruchom skrypt ponownie.
                goto :clean_exit
            )
        )
    ) else (
        echo [BLAD] Nie znaleziono pliku '.env' ani '%ENV_EXAMPLE%'.
        echo        Skopiuj env.example do tego katalogu i uzupelnij wartosci.
        goto :error_exit
    )
) else (
    echo [OK]    Plik .env istnieje.
)

:: ---------- 3. Logowanie do Harbor ----------

echo.
echo [INFO]  Logowanie do rejestru obrazow ^(%REGISTRY%^)...
echo.
set /p "HARBOR_KEY=Podaj klucz dostepu (Base64): "

if "!HARBOR_KEY!"=="" (
    echo [BLAD] Klucz nie moze byc pusty.
    goto :error_exit
)

:: Dekodowanie Base64 przez PowerShell → login:haslo
for /f "tokens=1,* delims=:" %%a in ('powershell -NoProfile -Command "[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('%HARBOR_KEY%'))"') do (
    set "HARBOR_USER=%%a"
    set "HARBOR_PASS=%%b"
)

if "!HARBOR_USER!"=="" (
    echo [BLAD] Nie udalo sie odkodowac klucza. Sprawdz, czy jest prawidlowy ^(Base64^).
    goto :error_exit
)
if "!HARBOR_PASS!"=="" (
    echo [BLAD] Odkodowany klucz ma nieprawidlowy format. Oczekiwany: login:haslo ^(zakodowane w Base64^).
    goto :error_exit
)

:: Logowanie — haslo przez stdin
echo !HARBOR_PASS! | docker login "%REGISTRY%" -u "!HARBOR_USER!" --password-stdin
if %errorlevel% neq 0 (
    echo [BLAD] Logowanie do %REGISTRY% nie powiodlo sie. Sprawdz klucz dostepu.
    goto :error_exit
)

echo [OK]    Zalogowano do %REGISTRY% jako !HARBOR_USER!

:: ---------- 4. Uruchomienie aplikacji ----------

echo.
echo [INFO]  Pobieranie obrazow i uruchamianie aplikacji...
echo.

%COMPOSE_CMD% -f "%COMPOSE_FILE%" pull
if %errorlevel% neq 0 (
    echo [BLAD] Pobieranie obrazow nie powiodlo sie.
    goto :error_exit
)

%COMPOSE_CMD% -f "%COMPOSE_FILE%" up -d
if %errorlevel% neq 0 (
    echo [BLAD] Uruchamianie aplikacji nie powiodlo sie.
    goto :error_exit
)

:: ---------- 5. Podsumowanie ----------

echo.
echo ========================================
echo    Instalacja zakonczona pomyslnie!
echo ========================================
echo.
echo [OK]    Aplikacja dziala na: http://localhost
echo.
echo [INFO]  Przydatne polecenia:
echo   Logi:       %COMPOSE_CMD% -f %COMPOSE_FILE% logs -f
echo   Status:     %COMPOSE_CMD% -f %COMPOSE_FILE% ps
echo   Zatrzymaj:  %COMPOSE_CMD% -f %COMPOSE_FILE% down
echo   Aktualizuj: %COMPOSE_CMD% -f %COMPOSE_FILE% pull ^& %COMPOSE_CMD% -f %COMPOSE_FILE% up -d
echo.

goto :clean_exit

:error_exit
echo.
pause
exit /b 1

:clean_exit
echo.
pause
exit /b 0
