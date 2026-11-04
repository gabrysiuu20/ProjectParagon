import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:projekt_paragon/api.dart';

void main() {
  test('HTTP contract: GET people and POST JSON with Polish name', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final api = ParagonApi('http://127.0.0.1:${server.port}');
    addTearDown(() async {
      api.close();
      await server.close(force: true);
    });
    final served = () async {
      var count = 0;
      await for (final request in server) {
        expect(request.uri.path, '/people');
        request.response.headers.contentType = ContentType.json;
        if (request.method == 'GET') {
          request.response.write(
            jsonEncode([
              {'id': 1, 'name': 'Ala'},
            ]),
          );
        } else {
          expect(request.method, 'POST');
          expect(jsonDecode(await utf8.decoder.bind(request).join()), {
            'name': 'Łukasz',
          });
          request.response.statusCode = 201;
          request.response.write(jsonEncode({'id': 2, 'name': 'Łukasz'}));
        }
        await request.response.close();
        if (++count == 2) break;
      }
    }();
    expect((await api.getPeople()).single.name, 'Ala');
    expect((await api.addPerson(' Łukasz ')).id, 2);
    await served;
  });

  test('Server failures are reported', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final api = ParagonApi('http://127.0.0.1:${server.port}');
    addTearDown(() async {
      api.close();
      await server.close(force: true);
    });
    final served = () async {
      final request = await server.first;
      request.response.statusCode = 500;
      await request.response.close();
    }();
    await expectLater(api.getPeople(), throwsA(isA<ApiException>()));
    await served;
  });
}
