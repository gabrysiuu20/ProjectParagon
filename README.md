# ProjectParagon

Backend MVP aplikacji Android do ręcznego rozliczania zakupów z paragonów.
Flutter jest w `mobile/projekt_paragon/`; na tym etapie nie jest połączony z API.
Puste pliki w `app/` pozostawiono jako dotychczasowy szkielet. Implementacja jest w `backend/`.

## Plan i zakres

1. Parser, Decimal, weryfikacja sum i testy — zaimplementowane.
2. FastAPI, SQLite, ręczne przypisania i korekty, XLSX — zaimplementowane.
3. OCR: adapter PaddleOCR 3.x — wymaga ręcznej instalacji i oceny na zdjęciach.
4. Flutter: aparat, galeria, korekty i przypisania — kolejny etap.

## Uruchomienie

PowerShell, z katalogu projektu:

```powershell
python -m venv .venv
.\.venv\Scripts\python -m pip install -r backend/requirements.txt
.\.venv\Scripts\python -m uvicorn backend.main:create_app --factory --reload
```

Dokumentacja interaktywna: http://127.0.0.1:8000/docs

```powershell
.\.venv\Scripts\python -m pytest -q
```

OCR jest opcjonalny: podstawowy `requirements.txt` go nie instaluje.
Zależności adaptera są w `backend/requirements-ocr.txt`; silnik PaddlePaddle
(CPU/GPU) należy dobrać i zainstalować osobno według oficjalnej instrukcji:
https://www.paddleocr.ai/main/en/quick_start.html
Przed instalacją sprawdź zgodność wersji Pythona, systemu i silnika;
obecne środowisko Python 3.14 nie zostało zweryfikowane z PaddlePaddle.
Na tym etapie nie zainstalowano PaddleOCR ani nie pobrano modeli.
Model ładuje się przy pierwszym zdjęciu; może wtedy pobierać pliki z sieci,
więc pierwszy odczyt może potrwać dłużej. Brak zależności lub błąd silnika daje HTTP 503,
a pozostałe API działa bez OCR. Adapter korzysta z API `predict()` PaddleOCR 3.x.
Konfiguracja: `PARAGON_DB`, `OCR_LANG=pl`, `OCR_DEVICE=cpu`
(przykład: `backend/.env.example`). Po zmianie konfiguracji zrestartuj backend.
Plik `.env` nie jest automatycznie wczytywany. Klucze API nie są potrzebne.

## API

| Metoda | Ścieżka | Działanie |
|---|---|---|
| GET/POST | `/people` | Lista / dodanie osoby (`name`) |
| POST | `/receipts/parse` | Parsowanie tekstu (`text`) i zapis |
| POST | `/receipts/upload` | Multipart `file`, OCR i zapis |
| GET | `/receipts` | Historia paragonów |
| GET/PUT | `/receipts/{id}` | Odczyt / pełna ręczna korekta obiektu Receipt |
| PUT | `/receipts/{id}/settlement` | Zapis ręcznych przypisań i obliczenia |
| GET | `/receipts/{id}/export` | Plik XLSX |

Przykład przypisania pierwszej pozycji po połowie:

```json
{"assignments": [{"item_index": 0, "person_ids": [1, 2]}]}
```

Osoby muszą istnieć. Każda pozycja może wystąpić raz. Rosnąca kolejność ID wyznacza
odbiorców reszty groszowej. Brak przypisania pozostawia koszt jako nieprzypisany.
Korekta paragonu usuwa poprzednie przypisania, bo indeksy produktów mogą się zmienić.
Kwoty wejściowe przesyłaj jako ciągi dziesiętne, np. `"3.87"`.
SQLite przechowuje pełne produkty i przypisania jako JSON z kwotami tekstowymi;
backend liczy przez Decimal. XLSX zapisuje wartości liczbowe do prezentacji.

## Ograniczenia MVP

Parser obsługuje ilość × cenę, produkty ważone, przecinek/kropkę, VAT, nazwę
w poprzednim wierszu i rabat z pasującą nazwą bezpośrednio po produkcie.
Nie jest uniwersalnym parserem wszystkich sklepów. Niejasne wiersze i rabaty
trafiają do ostrzeżeń; surowy tekst pozostaje do korekty. Zgodność sumy nie oznacza
poprawnego rozpoznania wszystkich nazw. Po OCR przejrzyj dane i ostrzeżenia.
Rozliczenie może być częściowe; odpowiedź API pokazuje oddzielnie nieprzypisany
koszt i zgodność sumy. Brak automatycznych przypisań do osób.

`tests/fixtures/lidl.txt` to ręczna transkrypcja przykładowego paragonu,
nie wynik OCR. Osiem produktów po rabacie daje 34,61 PLN.
Test API używa zastępczego OCR; nie potwierdza jakości odczytu zdjęcia.
Fragmenty PaddleOCR są łączone w wiersze według położenia; dla przekrzywionych
lub nietypowych paragonów kolejność wymaga sprawdzenia. Automatyczne obracanie
i prostowanie dokumentu jest na razie wyłączone; zdjęcie powinno być ustawione pionowo.
Adapter nie ma obecnie limitu czasu wykonywania modelu.
Upload ograniczony do 10 MB, obraz do 25 megapikseli. Zdjęcia nie są zapisywane;
tekst OCR pozostaje w bazie. API nie ma jeszcze logowania ani izolacji użytkowników;
publiczne wdrożenie wymaga osobnego etapu.
