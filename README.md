# Instalacja FeedTrack (Klient)

Poniższa instrukcja opisuje proces uruchomienia aplikacji w Twoim środowisku.

## Wymagania wstępne
- Zainstalowany Docker (Docker Desktop dla Windows/Mac, Docker Engine dla Linuxa)
- Zainstalowany Docker Compose
- Klucz dostępu od zespołu FeedTrack (zakodowany w Base64).

## Instalacja

1. Odbierz i rozpakuj pliki instalacyjne. W folderze powinny znajdować się m.in.: `docker-compose.client.yml`, `env.example` oraz skrypty instalacyjne.
2. Uruchom skrypt instalacyjny:
   - Windows: Kliknij dwukrotnie plik `install_win.bat` (lub uruchom z poziomu Wiersza Poleceń).
   - Linux / macOS: Otwórz terminal w folderze, nadaj uprawnienia i uruchom: `chmod +x install.sh && ./install.sh`
3. Postępuj zgodnie z komunikatami w konsoli:
   - Zapytany o port HTTP, wpisz numer portu (lub zostaw puste dla domyślnego 80). Ruch z tego portu jest przekierowywany na HTTPS.
   - Zapytany o port HTTPS, wpisz numer portu (lub zostaw puste dla domyślnego 443).
   - Zapytany o nazwę hosta / adres IP, podaj adres, pod którym będziesz wchodzić do aplikacji (np. `feedtrack.firma.local` albo `192.168.1.50`; domyślnie `localhost`). Ta wartość trafia do certyfikatu — musi pasować do adresu w przeglądarce.
   - Zapytany o klucz dostępu, wklej otrzymany ciąg Base64 i wciśnij Enter.
4. Aplikacja pobierze swoje komponenty z rejestru, wygeneruje certyfikat i uruchomi się automatycznie.

Po zakończeniu logowania i uruchomienia, wejdź w przeglądarce pod wskazany przez instalatora adres (np. `https://localhost`).

## HTTPS i certyfikat self-signed

Aplikacja działa po HTTPS. Instalator automatycznie generuje **certyfikat self-signed** (zapisany w katalogu `./certs` obok plików instalacyjnych, ważny 10 lat) i wpina go do serwera nginx.

Ponieważ certyfikat nie pochodzi od zaufanego urzędu (CA), przy pierwszym wejściu **przeglądarka pokaże ostrzeżenie o niezaufanym połączeniu**. To oczekiwane. Masz dwie opcje:
- Kliknąć „Zaawansowane” → „Przejdź dalej” i zaakceptować wyjątek, albo
- Zaimportować plik `./certs/fullchain.pem` do magazynu zaufanych certyfikatów na stacjach klienckich (zalecane przy wielu użytkownikach).

Uwagi:
- Adres w przeglądarce musi pasować do nazwy/IP podanej podczas instalacji (pole SAN certyfikatu). Wejście pod innym adresem da błąd niezgodności nazwy.
- Wejście po `http://` jest automatycznie przekierowywane na `https://`.
- Aby zmienić nazwę hosta lub wygenerować certyfikat od nowa, usuń katalog `./certs` i uruchom ponownie instalator/aktualizację (`update.sh`).

## Konfiguracja synchronizacji i autoryzacji

Aby aplikacja mogła synchronizować dane z serwerem centralnym, musisz podać swój unikalny token autoryzacyjny.
1. Otwórz plik `.env`, który wygenerował się w folderze instalacyjnym (obok skryptów).
2. Znajdź zmienną `CENTRAL_SYNC_TOKEN` i podmień jej wartość na swój token:
   ```
   CENTRAL_SYNC_TOKEN=twoj-otrzymany-token-autoryzacyjny
   ```
3. Zapisz plik `.env`.
4. Przeładuj aplikację, aby wczytać nową konfigurację uruchamiając w konsoli:
   ```bash
   docker compose -f docker-compose.client.yml restart
   ```

5. **Ważne:** Przekaż zarządcy systemu FeedTrack (centrala) zewnętrzny publiczny adres IP maszyny, na której pracuje ta wersja aplikacji. Bez dodania Twojego IP do białej listy na serwerze centralnym komunikacja (synchronizacja) zostanie odrzucona.

## Zaawansowana konfiguracja (Opcjonalnie)

W pliku `.env` możesz zmienić więcej parametrów (np. hasła do bazy danych, poświadczenia automatycznego konta administratora).
Jeśli wprowadzasz zmiany, które mogłyby wymagać ponownego stworzenia kontenerów (np. porty, nazwy użytkowników do bazy danych we wczesnej fazie), użyj poleceń:
```bash
docker compose -f docker-compose.client.yml down
docker compose -f docker-compose.client.yml up -d
```
