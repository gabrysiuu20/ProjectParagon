import 'dart:async';
import 'dart:convert';
import 'dart:io';

class Person {
  const Person({required this.id, required this.name});
  final int id;
  final String name;

  factory Person.fromJson(Map<String, dynamic> json) =>
      Person(id: json['id'] as int, name: json['name'] as String);
}

class ApiException implements Exception {
  const ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract class PeopleApi {
  Future<List<Person>> getPeople();
  Future<Person> addPerson(String name);
  void close();
}

class ParagonApi implements PeopleApi {
  ParagonApi(String address) : baseUri = validateAddress(address);
  final Uri baseUri;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);

  static Uri validateAddress(String address) {
    final uri = Uri.tryParse(address.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const ApiException('Podaj adres serwera, np. http://10.0.2.2:8000');
    }
    return uri;
  }

  Future<dynamic> _request(String method, String path, [Object? body]) async {
    try {
      return await (() async {
        final request = await _client.openUrl(method, baseUri.resolve(path));
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        if (body != null) {
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode(body));
        }
        final response = await request.close();
        final text = await utf8.decoder.bind(response).join();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw ApiException(
            'Serwer zwrócił błąd ${response.statusCode}. '
            'Sprawdź dane lub spróbuj ponownie później.',
          );
        }
        return jsonDecode(text);
      })().timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const ApiException(
        'Serwer nie odpowiedział w ciągu 15 sekund. '
        'Po dodawaniu osoby odśwież listę przed kolejną próbą.',
      );
    } on SocketException {
      throw const ApiException(
        'Nie można połączyć się z serwerem. Sprawdź adres, '
        'uruchomienie backendu i połączenie z siecią.',
      );
    } on HandshakeException {
      throw const ApiException(
        'Nie udało się nawiązać bezpiecznego połączenia HTTPS.',
      );
    } on HttpException {
      throw const ApiException(
        'Połączenie zostało przerwane. Odśwież listę, aby sprawdzić wynik.',
      );
    } on FormatException {
      throw const ApiException(
        'Serwer zwrócił nieprawidłowe dane. Sprawdź adres API.',
      );
    }
  }

  @override
  Future<List<Person>> getPeople() async {
    final data = await _request('GET', '/people');
    try {
      return (data as List)
          .map((p) => Person.fromJson(p as Map<String, dynamic>))
          .toList();
    } on TypeError {
      throw const ApiException(
        'Odpowiedź serwera nie zawiera poprawnej listy znajomych.',
      );
    }
  }

  @override
  Future<Person> addPerson(String name) async {
    final data = await _request('POST', '/people', {'name': name.trim()});
    try {
      return Person.fromJson(data as Map<String, dynamic>);
    } on TypeError {
      throw const ApiException(
        'Nieprawidłowe potwierdzenie zapisu. Odśwież listę przed ponowną próbą.',
      );
    }
  }

  @override
  void close() => _client.close(force: true);
}
