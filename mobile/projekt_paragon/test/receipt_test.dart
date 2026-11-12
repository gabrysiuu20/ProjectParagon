import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:projekt_paragon/api.dart';
import 'package:projekt_paragon/receipt_api.dart';
import 'package:projekt_paragon/receipt_page.dart';

final receiptJson = {
  'id': 7,
  'receipt': {
    'items': [],
    'total': '12.30',
    'warnings': ['Sprawdź produkty'],
    'raw_text': 'SUMA 12,30',
  },
};
final photo = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
);

class FakePicker extends ImagePicker {
  bool cancel = false;
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async => cancel ? null : XFile.fromData(photo, name: 'test.png');
}

void main() {
  test(
    'Multipart contains photo in file field and parses saved receipt',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/receipts/upload');
        expect(
          request.headers['content-type'],
          startsWith('multipart/form-data; boundary='),
        );
        expect(
          latin1.decode(request.bodyBytes),
          contains('name="file"; filename="receipt.jpg"'),
        );
        expect(
          latin1.decode(request.bodyBytes),
          contains(latin1.decode(photo)),
        );
        return http.Response.bytes(utf8.encode(jsonEncode(receiptJson)), 201);
      });
      final api = ReceiptApi('http://localhost:8000', client: client);
      addTearDown(api.close);
      expect((await api.upload(photo)).id, 7);
    },
  );

  for (final status in [413, 422, 503, 500]) {
    test('Upload reports HTTP $status', () async {
      final api = ReceiptApi(
        'http://localhost',
        client: MockClient((_) async => http.Response('', status)),
      );
      addTearDown(api.close);
      await expectLater(api.upload(photo), throwsA(isA<ApiException>()));
    });
  }

  test('Rejects oversized and empty files before network request', () async {
    final api = ReceiptApi(
      'http://localhost',
      client: MockClient((_) async => throw StateError('Must not send')),
    );
    addTearDown(api.close);
    await expectLater(api.upload([]), throwsA(isA<ApiException>()));
    await expectLater(
      api.upload(List.filled(maxPhotoBytes + 1, 0)),
      throwsA(isA<ApiException>()),
    );
  });

  testWidgets(
    'Cancel preserves preview; upload disables duplicate submissions and shows result',
    (tester) async {
      final picker = FakePicker();
      final response = Completer<http.Response>();
      var calls = 0;
      final api = ReceiptApi(
        'http://localhost',
        client: MockClient((_) {
          calls++;
          return response.future;
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ReceiptPage(
            address: 'http://localhost',
            picker: picker,
            api: api,
          ),
        ),
      );
      await tester.tap(find.text('Wybierz z galerii'));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      picker.cancel = true;
      await tester.tap(find.text('Wybierz z galerii'));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      await tester.ensureVisible(find.text('Wyślij do odczytu'));
      final uploadButton = find.ancestor(
        of: find.text('Wyślij do odczytu'),
        matching: find.byType(FilledButton),
      );
      await tester.tap(find.text('Wyślij do odczytu'));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(uploadButton).onPressed,
        isNull,
      );
      response.complete(
        http.Response.bytes(utf8.encode(jsonEncode(receiptJson)), 201),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Zapisano paragon #7'), 150);
      expect(find.text('Zapisano paragon #7'), findsOneWidget);
      expect(calls, 1);
      expect(
        tester.widget<FilledButton>(uploadButton).onPressed,
        isNull,
      );
    },
  );
}
