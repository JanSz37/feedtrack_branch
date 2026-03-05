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
   - Zapytany o klucz dostępu, wklej otrzymany ciąg Base64 i wciśnij Enter.
   - Zapytany o port aplikacji, wpisz pożądany numer portu (np. 8080 lub zostaw puste dla domyślnego portu 80) i wciśnij Enter.
4. Aplikacja pobierze swoje komponenty z rejestru i uruchomi się automatycznie.

Po zakończeniu logowania i uruchomienia, wejdź w przeglądarce pod wskazany przez instalatora adres (np. http://localhost lub http://localhost:8080).

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
