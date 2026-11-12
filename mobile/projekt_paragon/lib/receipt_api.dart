import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api.dart';
import 'receipt_math.dart';

const maxPhotoBytes = 10 * 1024 * 1024;

class UploadedReceipt {
  UploadedReceipt.fromJson(Map<String, dynamic> json)
    : id = json['id'] as int,
      receipt = json['receipt'] as Map<String, dynamic>,
      validation = json['validation'] as Map<String, dynamic>?,
      settlement = json['settlement'] as Map<String, dynamic>? {
    if (receipt['items'] is! List ||
        receipt['raw_text'] is! String ||
        receipt['warnings'] is! List ||
        (receipt['total'] != null && receipt['total'] is! String)) {
      throw const FormatException('Invalid receipt');
    }
  }

  final int id;
  final Map<String, dynamic> receipt;
  final Map<String, dynamic>? validation;
  final Map<String, dynamic>? settlement;
}

class SettlementResult {
  SettlementResult.fromJson(Map<String, dynamic> json)
    : totals = (json['totals'] as Map<String, dynamic>).map((id, amount) {
        final cents = parseMoneyCents(amount.toString());
        if (cents == null) throw const FormatException('Invalid settlement');
        return MapEntry(int.parse(id), cents);
      }),
      unassignedCents = parseMoneyCents(json['unassigned_amount'].toString())!,
      complete = json['complete'] as bool,
      receiptValidation = json['receipt_validation'] as Map<String, dynamic>? {
    if (unassignedCents < BigInt.zero) {
      throw const FormatException('Invalid settlement');
    }
  }

  final Map<int, BigInt> totals;
  final BigInt unassignedCents;
  final bool complete;
  final Map<String, dynamic>? receiptValidation;
}

class ReceiptApi {
  ReceiptApi(String address, {http.Client? client})
    : _baseUri = ParagonApi.validateAddress(address),
      _client = client ?? http.Client();

  final Uri _baseUri;
  final http.Client _client;

  Future<UploadedReceipt> upload(List<int> bytes) async {
    if (bytes.isEmpty || bytes.length > maxPhotoBytes) {
      throw const ApiException(
        'Wybierz niepuste zdjęcie o rozmiarze do 10 MB.',
      );
    }
    try {
      return await (() async {
        final request =
            http.MultipartRequest('POST', _baseUri.resolve('/receipts/upload'))
              ..files.add(
                http.MultipartFile.fromBytes(
                  'file',
                  bytes,
                  filename: 'receipt.jpg',
                ),
              );
        final response = await http.Response.fromStream(
          await _client.send(request),
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw ApiException(switch (response.statusCode) {
            413 => 'Zdjęcie przekracza limit 10 MB. Wybierz mniejsze zdjęcie.',
            422 => 'Nie można odczytać zdjęcia. Wybierz wyraźne zdjęcie JPG lub PNG (do 25 megapikseli).',
            503 => 'OCR jest niedostępny. Sprawdź konfigurację OCR na serwerze i spróbuj ponownie.',
            _ =>
              'Błąd serwera (${response.statusCode}). Spróbuj ponownie później.',
          });
        }
        return UploadedReceipt.fromJson(
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
        );
      })().timeout(const Duration(minutes: 8));
    } on TimeoutException {
      throw const ApiException(
        'Przekroczono czas oczekiwania na OCR (8 minut). Paragon mógł zostać zapisany; ponowienie może utworzyć duplikat.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Utracono połączenie z API. Sprawdź sieć. Jeśli wysyłanie się rozpoczęło, paragon mógł zostać zapisany.',
      );
    } on FormatException {
      throw const ApiException(
        'Nieprawidłowa odpowiedź API. Paragon mógł zostać zapisany.',
      );
    } on TypeError {
      throw const ApiException('Nieprawidłowe potwierdzenie zapisu paragonu.');
    }
  }

  Future<UploadedReceipt> updateReceipt(
    int id,
    Map<String, dynamic> receipt,
  ) async {
    try {
      final response = await _client
          .put(
            _baseUri.resolve('/receipts/$id'),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
            },
            body: jsonEncode(receipt),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 404) {
        throw const ApiException('Nie znaleziono paragonu na serwerze.');
      }
      if (response.statusCode == 422) {
        throw const ApiException(
          'Serwer odrzucił korektę. Sprawdź nazwy i kwoty produktów.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          'Nie udało się zapisać korekty (HTTP ${response.statusCode}).',
        );
      }
      return UploadedReceipt.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
      );
    } on TimeoutException {
      throw const ApiException(
        'Nie otrzymano potwierdzenia zapisu. Korekta mogła zostać zapisana na serwerze.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Utracono połączenie z serwerem. Korekta mogła zostać zapisana.',
      );
    } on FormatException {
      throw const ApiException(
        'Serwer zwrócił nieprawidłowe potwierdzenie korekty.',
      );
    } on TypeError {
      throw const ApiException(
        'Serwer zwrócił nieprawidłowe dane paragonu po korekcie.',
      );
    }
  }

  Future<UploadedReceipt> getReceipt(int id) async {
    try {
      final response = await _client
          .get(_baseUri.resolve('/receipts/$id'))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 404) {
        throw const ApiException('Nie znaleziono paragonu na serwerze.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          'Nie udało się wczytać rozliczenia (HTTP ${response.statusCode}).',
        );
      }
      return UploadedReceipt.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
      );
    } on TimeoutException {
      throw const ApiException(
        'Serwer nie odpowiedział podczas wczytywania rozliczenia.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Utracono połączenie podczas wczytywania rozliczenia.',
      );
    } on FormatException {
      throw const ApiException('Serwer zwrócił nieprawidłowy paragon.');
    } on TypeError {
      throw const ApiException('Serwer zwrócił nieprawidłowy paragon.');
    }
  }

  Future<SettlementResult> updateSettlement(
    int id,
    Map<int, Set<int>> assignments,
  ) async {
    try {
      final indices = assignments.keys.toList()..sort();
      final response = await _client
          .put(
            _baseUri.resolve('/receipts/$id/settlement'),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'assignments': [
                for (final index in indices)
                  if (assignments[index]!.isNotEmpty)
                    {
                      'item_index': index,
                      'person_ids': assignments[index]!.toList()..sort(),
                    },
              ],
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 404) {
        throw const ApiException('Nie znaleziono paragonu na serwerze.');
      }
      if (response.statusCode == 422) {
        throw const ApiException(
          'Nie można zapisać przypisań. Odśwież paragon i listę osób.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          'Nie udało się zapisać podziału (HTTP ${response.statusCode}).',
        );
      }
      return SettlementResult.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
      );
    } on TimeoutException {
      throw const ApiException(
        'Brak potwierdzenia zapisu. Podział mógł zostać zapisany; odśwież ekran.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Utracono połączenie. Podział mógł zostać zapisany; odśwież ekran.',
      );
    } on FormatException {
      throw const ApiException('Serwer zwrócił nieprawidłowe rozliczenie.');
    } on TypeError {
      throw const ApiException('Serwer zwrócił nieprawidłowe rozliczenie.');
    }
  }

  void close() => _client.close();
}
