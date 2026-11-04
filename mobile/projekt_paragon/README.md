# Projekt Paragon — aplikacja mobilna

Pierwszy ekran zawiera konfigurację API, listę znajomych i dodawanie osób.
Dane zapisuje backend SQLite; lista jest pobierana ponownie przy uruchomieniu.
Zmiana adresu w ekranie obowiązuje po kliknięciu „Połącz” i tylko do zamknięcia aplikacji.
Stały adres początkowy ustaw przez `--dart-define=API_BASE_URL=...`.

## Uruchomienie

Z katalogu głównego repozytorium uruchom backend:

```powershell
.\.venv\Scripts\python -m uvicorn backend.main:create_app --factory --reload --host 0.0.0.0
```

Następnie, w drugim terminalu:

```powershell
cd mobile/projekt_paragon
flutter run -d <identyfikator-urządzenia>
```

Urządzenia wyświetla `flutter devices`. Domyślny adres `http://10.0.2.2:8000`
prowadzi z emulatora Androida do komputera. Na fizycznym telefonie wpisz w ekranie
adres IPv4 komputera, np. `http://192.168.1.20:8000`. Oba urządzenia muszą mieć
łączność w sieci lokalnej, a zapora musi dopuszczać port backendu.
Dla aplikacji Windows użyj `http://127.0.0.1:8000`:

```powershell
flutter run -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

HTTP dla lokalnego backendu jest dozwolone w wariantach Android debug/profile.
Wariant release wymaga HTTPS. Backend nie ma jeszcze logowania: testuj w zaufanej sieci.
Klient używa `dart:io`, więc ten etap obsługuje Android/desktop; przeglądarka nie jest obsługiwana.
Nie dodano nowych pakietów Flutter.

## Weryfikacja

```powershell
flutter analyze --no-pub
flutter test --no-pub
```

Testy sprawdzają pobieranie i dodawanie przez rzeczywisty lokalny serwer HTTP,
błędy serwera oraz ekran: walidację nazwy, zapis osoby i ponowienie połączenia.
Testy nie zastępują uruchomienia na Androidzie i sprawdzenia sieci telefonu.

Po uruchomieniu sprawdź: połączenie, dodanie osoby, odświeżenie listy i ponowne
uruchomienie aplikacji (osoba powinna pozostać w backendzie). Aparat, paragony,
przypisania i eksport nie mają jeszcze ekranów mobilnych.
