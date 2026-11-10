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
Wybór zdjęć korzysta z `image_picker`, upload multipart z `http`.
Po pobraniu zmian uruchom `flutter pub get`. Na Windows pluginy wymagają
włączonego Trybu dewelopera (Ustawienia systemu → Dla deweloperów).

## Zdjęcie paragonu

Po połączeniu z API wybierz „Dodaj paragon” w górnym pasku. Wybierz zdjęcie
z galerii lub użyj aparatu (Android/iOS), sprawdź podgląd i naciśnij „Wyślij do odczytu”.
Na desktopie dostępny jest wybór pliku. Limit wynosi 10 MB; picker zmniejsza zdjęcie
do maksymalnie 4000 × 4000 pikseli. Backend dodatkowo kontroluje limit 25 megapikseli.
Na Androidzie po przerwaniu aplikacji przez system podczas wyboru zdjęcia otwórz
ponownie „Dodaj paragon”, aby odzyskać zdjęcie. Przed wysłaniem sprawdź adres API.
Konfiguracja platform jest zgodna z dokumentacją: https://pub.dev/packages/image_picker.

Wysyłanie obejmuje OCR i zapis; interfejs pokazuje oczekiwanie, a następnie numer
paragonu, listę pozycji, zgodność sumy, ostrzeżenia parsera i odczytany tekst. Zdjęcia nie są
zapisywane na serwerze. Po błędzie zdjęcie pozostaje do ponowienia; anulowanie galerii
zachowuje poprzedni wybór. Po sukcesie ponowne wysłanie tego samego wyboru jest blokowane.
Timeout wynosi 8 minut, ponieważ duże zdjęcie może być przetwarzane długo na CPU.
Backend może kontynuować OCR po utracie połączenia lub
przekroczeniu czasu; ponowienie może wtedy utworzyć duplikat. OCR musi być
zainstalowany na backendzie (patrz główny README); brak silnika daje komunikat błędu.

## Korekta paragonu

Po odczycie wybierz „Edytuj produkty i sumę”. Możesz zmienić nazwę, ilość,
cenę jednostkową, wartość pozycji, rabat i oznaczenie VAT, a także dodać lub
usunąć produkt oraz poprawić sumę paragonu. Pola kwot akceptują przecinek lub
kropkę; zapis używa dokładnych kwot dziesiętnych. Różnice ilość × cena i
niezgodność sumy są pokazywane na bieżąco jako ostrzeżenia. Pusta nazwa,
niepoprawna kwota, niedodatnia ilość lub rabat większy od wartości pozycji
blokują zapis. Niezgodność sumy można zapisać po świadomym przejrzeniu ostrzeżeń.

„Zapisz korektę” wysyła pełny paragon przez `PUT /receipts/{id}`. Tekst OCR i
uwagi z pierwotnego odczytu pozostają dostępne; bieżąca zgodność kwot jest
liczona ponownie przez API. Wyjście z niezapisanymi zmianami wymaga potwierdzenia.
Korekta zapisanego paragonu usuwa wcześniejsze przypisania produktów do osób,
ponieważ indeksy pozycji mogły się zmienić. Do już zapisanych paragonów będzie
można wrócić z historii w kolejnym etapie; obecnie korekta jest dostępna od razu
po przesłaniu zdjęcia.

## Weryfikacja

```powershell
flutter analyze --no-pub
flutter test --no-pub
```

Testy sprawdzają pobieranie i dodawanie przez rzeczywisty lokalny serwer HTTP,
błędy serwera oraz ekran: walidację nazwy, zapis osoby i ponowienie połączenia.
Testy nie zastępują uruchomienia na Androidzie i sprawdzenia sieci telefonu.

Po uruchomieniu sprawdź: połączenie, dodanie osoby, odświeżenie listy i ponowne
uruchomienie aplikacji (osoba powinna pozostać w backendzie). Następnie sprawdź
galerię, anulowanie wyboru, aparat, odmowę dostępu, upload i wynik OCR na prawdziwym
telefonie. Testy automatyczne obejmują multipart, limit rozmiaru, błędy HTTP,
podgląd, anulowanie wyboru, blokowanie podwójnego wysłania, walidację korekty,
zapis i dokładność kwot. Nie sprawdzają systemowych okien aparatu ani jakości OCR.
Przypisania, historia i eksport nie mają jeszcze ekranów mobilnych.
