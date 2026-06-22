#!/usr/bin/env bash
# FeedTrack — skrypt aktualizacyjny
#
# Użycie (dwa scenariusze):
#   A) ftadmin już zainstalowany: uruchom z dowolnego miejsca
#      ./update.sh
#   B) Pierwsza aktualizacja (bez ftadmin): uruchom z katalogu instalacji
#      (gdzie leżą docker-compose.client.yml i .env)
#      ./update.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $1"; }
success() { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()    { echo -e "${YELLOW}[UWAGA]${NC} $1"; }
error()   { echo -e "${RED}[BŁĄD]${NC}  $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_LOCATIONS=("/etc/feedtrack/ftadmin.conf" "$HOME/.config/feedtrack/ftadmin.conf")
REGISTRY="download.feedtrack.pl"
NGINX_IMAGE="download.feedtrack.pl/feedtrack/feedtrack_branch:nginx"
CERTS_DIR="certs"

# Odczyt wartości z .env (bez sourcowania, odporne na znaki specjalne).
# `|| true` — brak klucza (grep zwraca 1) nie może wywrócić skryptu przez set -e/pipefail.
get_env_val() {
    { grep -E "^$2=" "$1" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '\r'; } || true
}

# Zapis zmiennej do .env: nadpisuje jeśli istnieje, w przeciwnym razie dopisuje.
set_env_val() {
    local file="$1" key="$2" value="$3"
    if grep -q "^${key}=" "$file" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    else
        echo "${key}=${value}" >> "$file"
    fi
}

# Dla starych instalacji (sprzed TLS) migruje .env na HTTPS: ustawia CSRF na https://,
# włącza Secure cookies oraz dopisuje SERVER_NAME/HTTPS_PORT, jeśli brak.
# Idempotentne — przy już zmigrowanym .env nic szkodliwego nie zmienia.
migrate_env_to_https() {
    local env="$1/.env"
    [ -f "$env" ] || return 0

    # SERVER_NAME: użyj istniejącego; w innym razie wyłuskaj host ze starego CSRF;
    # jeśli się nie da (lub to localhost) — dopytaj.
    local server_name; server_name="$(get_env_val "$env" SERVER_NAME)"
    if [ -z "$server_name" ]; then
        local csrf host
        csrf="$(get_env_val "$env" CSRF_TRUSTED_ORIGINS)"
        host="${csrf#*://}"; host="${host%%/*}"; host="${host%%:*}"
        if [ -z "$host" ] || [ "$host" = "localhost" ]; then
            read -rp "Pod jaką nazwą hosta / adresem IP działa aplikacja? (domyślnie localhost): " server_name
            server_name="${server_name:-localhost}"
        else
            server_name="$host"
        fi
    fi

    local https_port; https_port="$(get_env_val "$env" HTTPS_PORT)"; https_port="${https_port:-443}"

    local new_csrf
    if [ "$https_port" = "443" ]; then
        new_csrf="https://$server_name"
    else
        new_csrf="https://$server_name:$https_port"
    fi

    set_env_val "$env" SERVER_NAME "$server_name"
    set_env_val "$env" HTTPS_PORT "$https_port"
    set_env_val "$env" SECURE_COOKIES "True"
    set_env_val "$env" CSRF_TRUSTED_ORIGINS "$new_csrf"
    success "Ustawienia HTTPS w .env zaktualizowane (host: $server_name, CSRF: $new_csrf)."
}

# Dla starych instalacji (sprzed TLS) generuje self-signed cert, jeśli go brak.
# Bez certu kontener nginx z nową konfiguracją HTTPS nie wstanie.
ensure_certs() {
    local dir="$1"
    if [ -f "$dir/$CERTS_DIR/fullchain.pem" ] && [ -f "$dir/$CERTS_DIR/privkey.pem" ]; then
        return 0
    fi

    local server_name="localhost"
    if [ -f "$dir/.env" ]; then
        server_name="$({ grep -E '^SERVER_NAME=' "$dir/.env" 2>/dev/null | head -n1 | cut -d= -f2-; } || true)"
        server_name="${server_name:-localhost}"
    fi

    local san
    if [[ "$server_name" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        san="IP:${server_name},DNS:localhost,IP:127.0.0.1"
    else
        san="DNS:${server_name},DNS:localhost,IP:127.0.0.1"
    fi

    info "Brak certyfikatu — generuję self-signed dla '${server_name}'..."
    mkdir -p "$dir/$CERTS_DIR"
    docker run --rm -v "$dir/$CERTS_DIR":/certs "$NGINX_IMAGE" \
        openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout /certs/privkey.pem -out /certs/fullchain.pem \
        -subj "/CN=${server_name}" \
        -addext "subjectAltName=${san}" \
        || error "Nie udało się wygenerować certyfikatu."
    success "Certyfikat utworzony w $dir/$CERTS_DIR."
}

# Logowanie do rejestru obrazów na podstawie klucza Base64 (login:hasło).
harbor_login() {
    echo ""
    info "Logowanie do rejestru obrazów ($REGISTRY)..."
    read -rp "Podaj klucz dostępu (Base64): " HARBOR_KEY
    [ -n "$HARBOR_KEY" ] || error "Klucz nie może być pusty."

    DECODED=$(echo "$HARBOR_KEY" | base64 -d 2>/dev/null) \
        || error "Nie udało się odkodować klucza. Sprawdź, czy jest prawidłowy (Base64)."

    HARBOR_USER="${DECODED%%:*}"
    HARBOR_PASS="${DECODED#*:}"
    { [ -n "$HARBOR_USER" ] && [ -n "$HARBOR_PASS" ]; } \
        || error "Odkodowany klucz ma nieprawidłowy format. Oczekiwano: login:hasło (Base64)."

    echo "$HARBOR_PASS" | docker login "$REGISTRY" -u "$HARBOR_USER" --password-stdin \
        || error "Logowanie do $REGISTRY nie powiodło się. Sprawdź klucz dostępu."
    success "Zalogowano do $REGISTRY jako $HARBOR_USER"
}

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}   FeedTrack — Aktualizacja             ${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# ---------- 1. Znajdź katalog instalacji ----------

INSTALL_DIR=""
COMPOSE_FILE="docker-compose.client.yml"

for loc in "${CONF_LOCATIONS[@]}"; do
    if [ -f "$loc" ]; then
        # shellcheck disable=SC1090
        . "$loc"
        break
    fi
done

if [ -z "${INSTALL_DIR:-}" ]; then
    if [ -f "$SCRIPT_DIR/docker-compose.client.yml" ]; then
        INSTALL_DIR="$SCRIPT_DIR"
    else
        error "Nie znaleziono instalacji FeedTrack.\nUruchom update.sh z katalogu instalacyjnego lub najpierw zainstaluj przez install.sh."
    fi
fi

[ -f "$INSTALL_DIR/.env" ] || error "Nie znaleziono pliku .env w katalogu instalacji ($INSTALL_DIR)."

info "Katalog instalacji: $INSTALL_DIR"

# ---------- 2. Wykryj polecenie compose ----------

if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
else
    error "Nie znaleziono 'docker compose' ani 'docker-compose'."
fi

# ---------- 3. Zaktualizuj ftadmin ----------

FTADMIN_SRC="$SCRIPT_DIR/ftadmin"

if [ -f "$FTADMIN_SRC" ]; then
    info "Aktualizacja narzędzia 'ftadmin'..."

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
INSTALL_DIR=$INSTALL_DIR
COMPOSE_FILE=$COMPOSE_FILE
EOF

    success "Zaktualizowano 'ftadmin'."
else
    warn "Nie znaleziono pliku 'ftadmin' obok update.sh — pomijam aktualizację narzędzia."
fi

# ---------- 4. Pobierz nowe obrazy i uruchom ----------

echo ""
info "Pobieranie nowych obrazów z rejestru..."
if ! ( cd "$INSTALL_DIR" && $COMPOSE_CMD -f "$COMPOSE_FILE" pull ); then
    warn "Pobieranie nie powiodło się — prawdopodobnie brak autoryzacji do rejestru."
    harbor_login
    info "Ponawiam pobieranie..."
    ( cd "$INSTALL_DIR" && $COMPOSE_CMD -f "$COMPOSE_FILE" pull ) \
        || error "Pobieranie nadal się nie powiodło. Sprawdź klucz dostępu i połączenie."
fi

# Zmigruj .env na HTTPS (CSRF, Secure cookies, SERVER_NAME) — przed generacją certu,
# żeby cert dostał poprawny SERVER_NAME.
migrate_env_to_https "$INSTALL_DIR"

# Upewnij się, że certyfikat istnieje, zanim wystartuje nginx z konfiguracją HTTPS.
ensure_certs "$INSTALL_DIR"

info "Uruchamianie zaktualizowanych kontenerów..."
( cd "$INSTALL_DIR" && $COMPOSE_CMD -f "$COMPOSE_FILE" up -d )

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Aktualizacja zakończona pomyślnie!   ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
success "FeedTrack został zaktualizowany."
echo ""
