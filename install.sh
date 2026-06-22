#!/usr/bin/env bash
# ============================================================
#  FeedTrack — Skrypt instalacyjny
#
#  Użycie:
#    chmod +x install.sh
#    ./install.sh
#
#  Klient potrzebuje jedynie:
#    1. Ten skrypt (install.sh)
#    2. docker-compose.client.yml
#    3. .env (skopiowany z .env.example i uzupełniony)
# ============================================================

set -euo pipefail

# ---------- Kolory ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

REGISTRY="download.feedtrack.pl"
NGINX_IMAGE="download.feedtrack.pl/feedtrack/feedtrack_branch:nginx"
COMPOSE_FILE="docker-compose.client.yml"
ENV_EXAMPLE="env.example"
ENV_FILE=".env"
CERTS_DIR="certs"

# ---------- Funkcje pomocnicze ----------

info()    { echo -e "${CYAN}[INFO]${NC}  $1"; }
success() { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()    { echo -e "${YELLOW}[UWAGA]${NC} $1"; }
error()   { echo -e "${RED}[BŁĄD]${NC} $1"; exit 1; }

check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "Nie znaleziono polecenia '$1'. Zainstaluj je i uruchom skrypt ponownie."
    fi
    success "Znaleziono: $1"
}

# Zapisuje zmienną do .env: nadpisuje jeśli istnieje, w przeciwnym razie dopisuje.
set_env_var() {
    local key="$1" value="$2"
    if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
    else
        echo "${key}=${value}" >> "$ENV_FILE"
    fi
}

# Generuje self-signed certyfikat (jeśli jeszcze nie istnieje) z SAN na podany host/IP.
# Preferuje openssl z hosta; jeśli go brak — używa openssl z obrazu nginx.
generate_certs() {
    local server_name="$1"
    mkdir -p "$CERTS_DIR"

    if [ -f "$CERTS_DIR/fullchain.pem" ] && [ -f "$CERTS_DIR/privkey.pem" ]; then
        success "Certyfikat już istnieje w ./$CERTS_DIR — pomijam generowanie."
        return 0
    fi

    # Zbuduj listę SAN. Jeśli SERVER_NAME wygląda jak IPv4 — wpis IP, w innym razie DNS.
    # Zawsze dorzucamy localhost/127.0.0.1 dla dostępu z lokalnej maszyny.
    local san
    if [[ "$server_name" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        san="IP:${server_name},DNS:localhost,IP:127.0.0.1"
    else
        san="DNS:${server_name},DNS:localhost,IP:127.0.0.1"
    fi

    info "Generuję self-signed certyfikat dla '${server_name}' (SAN: ${san})..."
    if command -v openssl >/dev/null 2>&1; then
        openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
            -keyout "$CERTS_DIR/privkey.pem" -out "$CERTS_DIR/fullchain.pem" \
            -subj "/CN=${server_name}" -addext "subjectAltName=${san}" \
            || error "Nie udało się wygenerować certyfikatu (openssl z hosta)."
    else
        docker run --rm --entrypoint openssl -v "$(pwd)/$CERTS_DIR":/certs "$NGINX_IMAGE" \
            req -x509 -newkey rsa:2048 -nodes -days 3650 \
            -keyout /certs/privkey.pem -out /certs/fullchain.pem \
            -subj "/CN=${server_name}" -addext "subjectAltName=${san}" \
            || error "Nie udało się wygenerować certyfikatu. Zainstaluj openssl na hoście albo zaktualizuj obraz nginx (z openssl)."
    fi

    success "Certyfikat zapisany w ./$CERTS_DIR (ważny 10 lat)."
}

# ---------- 1. Sprawdzenie wymagań ----------

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}   FeedTrack — Instalacja               ${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

info "Sprawdzanie wymagań..."
check_command "docker"

# Sprawdź czy docker compose (v2) jest dostępny
if docker compose version &> /dev/null; then
    success "Znaleziono: docker compose (v2)"
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    success "Znaleziono: docker-compose (v1)"
    COMPOSE_CMD="docker-compose"
else
    error "Nie znaleziono 'docker compose' ani 'docker-compose'. Zainstaluj Docker Compose."
fi

# Sprawdź czy compose file istnieje
if [ ! -f "$COMPOSE_FILE" ]; then
    error "Nie znaleziono pliku '$COMPOSE_FILE' w bieżącym katalogu.\n       Upewnij się, że uruchamiasz skrypt z katalogu instalacyjnego."
fi

# ---------- 2. Plik .env ----------

echo ""
if [ ! -f "$ENV_FILE" ]; then
    if [ -f "$ENV_EXAMPLE" ]; then
        info "Tworzę plik .env na podstawie .env.example..."
        cp "$ENV_EXAMPLE" "$ENV_FILE"
        warn "Plik .env został utworzony. Otwórz go i uzupełnij wartości:"
        warn "  - DB_PASSWORD / POSTGRES_PASSWORD"
        warn "  - SECRET_KEY"
        warn "  - DJANGO_SUPERUSER_PASSWORD"
        warn "  - CENTRAL_SYNC_URL i CENTRAL_SYNC_TOKEN"
        echo ""
        read -rp "Czy kontynuować instalację z domyślnymi wartościami? (t/N): " CONTINUE
        if [[ ! "$CONTINUE" =~ ^[tTyY]$ ]]; then
            info "Edytuj plik .env, a następnie uruchom skrypt ponownie."
            exit 0
        fi
    else
        error "Nie znaleziono pliku '.env' ani '.env.example'.\n       Skopiuj .env.example do tego katalogu i uzupełnij wartości."
    fi
else
    success "Plik .env istnieje."
fi

# ---------- 3. Porty, host i HTTPS ----------

echo ""
read -rp "Na jakim porcie HTTP (przekierowanie na HTTPS)? (domyślnie 80): " APP_PORT
APP_PORT=${APP_PORT:-80}
if ! [[ "$APP_PORT" =~ ^[0-9]+$ ]]; then
    error "'$APP_PORT' nie jest prawidłowym numerem portu."
fi

read -rp "Na jakim porcie HTTPS? (domyślnie 443): " HTTPS_PORT
HTTPS_PORT=${HTTPS_PORT:-443}
if ! [[ "$HTTPS_PORT" =~ ^[0-9]+$ ]]; then
    error "'$HTTPS_PORT' nie jest prawidłowym numerem portu."
fi

read -rp "Pod jaką nazwą hosta / adresem IP będzie dostępna aplikacja? (domyślnie localhost): " SERVER_NAME
SERVER_NAME=${SERVER_NAME:-localhost}

# Origin dla CSRF — ze schematem https i portem (port pomijany, gdy 443).
if [ "$HTTPS_PORT" = "443" ]; then
    NEW_CSRF="https://$SERVER_NAME"
else
    NEW_CSRF="https://$SERVER_NAME:$HTTPS_PORT"
fi

set_env_var "APP_PORT" "$APP_PORT"
set_env_var "HTTPS_PORT" "$HTTPS_PORT"
set_env_var "SERVER_NAME" "$SERVER_NAME"
set_env_var "CSRF_TRUSTED_ORIGINS" "$NEW_CSRF"
set_env_var "SECURE_COOKIES" "True"
success "Porty: HTTP $APP_PORT → HTTPS $HTTPS_PORT, host: $SERVER_NAME"

# ---------- 4. Logowanie do Harbor ----------

echo ""
info "Logowanie do rejestru obrazów ($REGISTRY)..."
echo ""

read -rp "Podaj klucz dostępu (Base64): " HARBOR_KEY

if [ -z "$HARBOR_KEY" ]; then
    error "Klucz nie może być pusty."
fi

# Dekodowanie Base64 → login:hasło
DECODED=$(echo "$HARBOR_KEY" | base64 -d 2>/dev/null) || error "Nie udało się odkodować klucza. Sprawdź, czy jest prawidłowy (Base64)."

# Rozbicie na login i hasło po pierwszym ':'
HARBOR_USER="${DECODED%%:*}"
HARBOR_PASS="${DECODED#*:}"

if [ -z "$HARBOR_USER" ] || [ -z "$HARBOR_PASS" ]; then
    error "Odkodowany klucz ma nieprawidłowy format. Oczekiwany: login:hasło (zakodowane w Base64)."
fi

# Logowanie (hasło przez stdin, żeby nie było widoczne w historii procesów)
echo "$HARBOR_PASS" | docker login "$REGISTRY" -u "$HARBOR_USER" --password-stdin \
    || error "Logowanie do $REGISTRY nie powiodło się. Sprawdź klucz dostępu."

success "Zalogowano do $REGISTRY jako $HARBOR_USER"

# ---------- 4. Uruchomienie aplikacji ----------

echo ""
info "Pobieranie obrazów i uruchamianie aplikacji..."
echo ""

$COMPOSE_CMD -f "$COMPOSE_FILE" pull

# Certyfikat musi istnieć ZANIM wystartuje nginx (montowany jako wolumen).
generate_certs "$SERVER_NAME"

$COMPOSE_CMD -f "$COMPOSE_FILE" up -d

# ---------- 5. Instalacja narzędzia ftadmin ----------

echo ""
info "Instalacja narzędzia 'ftadmin'..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FTADMIN_SRC="$SCRIPT_DIR/ftadmin"

if [ ! -f "$FTADMIN_SRC" ]; then
    warn "Nie znaleziono pliku 'ftadmin' obok install.sh — pomijam instalację narzędzia."
else
    if [ "$(id -u)" -eq 0 ]; then
        BIN_DIR="/usr/local/bin"; CONF_DIR="/etc/feedtrack"; SUDO=""
    elif command -v sudo >/dev/null 2>&1; then
        BIN_DIR="/usr/local/bin"; CONF_DIR="/etc/feedtrack"; SUDO="sudo"
    else
        BIN_DIR="$HOME/.local/bin"; CONF_DIR="$HOME/.config/feedtrack"; SUDO=""
    fi

    $SUDO mkdir -p "$BIN_DIR" "$CONF_DIR"
    $SUDO cp "$FTADMIN_SRC" "$BIN_DIR/ftadmin"
    $SUDO chmod +x "$BIN_DIR/ftadmin"

    $SUDO tee "$CONF_DIR/ftadmin.conf" >/dev/null <<EOF
INSTALL_DIR=$SCRIPT_DIR
COMPOSE_FILE=$COMPOSE_FILE
EOF

    success "Zainstalowano 'ftadmin' w: $BIN_DIR/ftadmin"
    if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
        warn "Katalog $BIN_DIR nie jest w PATH. Dodaj go do profilu powłoki, np.:"
        warn "  export PATH=\"$BIN_DIR:\$PATH\""
    fi
fi

# ---------- 6. Podsumowanie ----------

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Instalacja zakończona pomyślnie!     ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
if [ "$HTTPS_PORT" = "443" ]; then
    success "Aplikacja działa na: https://$SERVER_NAME"
else
    success "Aplikacja działa na: https://$SERVER_NAME:$HTTPS_PORT"
fi
echo ""
warn "Certyfikat jest self-signed — przeglądarka pokaże ostrzeżenie o niezaufanym połączeniu."
warn "Zaakceptuj wyjątek w przeglądarce lub zaimportuj ./$CERTS_DIR/fullchain.pem do zaufanych certyfikatów."
echo ""
info "Przydatne polecenia:"
echo "  Logi:       $COMPOSE_CMD -f $COMPOSE_FILE logs -f"
echo "  Status:     $COMPOSE_CMD -f $COMPOSE_FILE ps"
echo "  Zatrzymaj:  $COMPOSE_CMD -f $COMPOSE_FILE down"
echo "  Aktualizuj: $COMPOSE_CMD -f $COMPOSE_FILE pull && $COMPOSE_CMD -f $COMPOSE_FILE up -d"
echo "  Administracja: ftadmin help"
echo "  Aktualizacja:  ./update.sh  (zamiast tego skryptu przy kolejnych aktualizacjach)"
echo ""
