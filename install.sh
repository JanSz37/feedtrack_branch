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
COMPOSE_FILE="docker-compose.client.yml"
ENV_EXAMPLE="env.example"
ENV_FILE=".env"

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

# ---------- 3. Logowanie do Harbor ----------

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
$COMPOSE_CMD -f "$COMPOSE_FILE" up -d

# ---------- 5. Podsumowanie ----------

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Instalacja zakończona pomyślnie!     ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
success "Aplikacja działa na: http://localhost"
echo ""
info "Przydatne polecenia:"
echo "  Logi:       $COMPOSE_CMD -f $COMPOSE_FILE logs -f"
echo "  Status:     $COMPOSE_CMD -f $COMPOSE_FILE ps"
echo "  Zatrzymaj:  $COMPOSE_CMD -f $COMPOSE_FILE down"
echo "  Aktualizuj: $COMPOSE_CMD -f $COMPOSE_FILE pull && $COMPOSE_CMD -f $COMPOSE_FILE up -d"
echo ""
