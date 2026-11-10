import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:projekt_paragon/receipt_api.dart';
import 'package:projekt_paragon/receipt_edit_page.dart';
import 'package:projekt_paragon/receipt_math.dart';

final originalJson = {
  'id': 12,
  'receipt': {
    'items': [
      {
        'name': 'Chleb',
        'quantity': '1',
        'unit_price': '2.00',
        'amount': '2.00',
        'discount': '0.00',
        'vat': 'C',
      },
    ],
    'total': '2.00',
    'raw_text': 'CHLEB 2,00',
    'warnings': ['Wiersz wymagał sprawdzenia'],
  },
  'validation': {
    'computed_total': '2.00',
    'difference': '0.00',
    'matches': true,
  },
};

void main() {
  test('Decimal checks use exact cents and half-up rounding', () {
    expect(parseMoneyCents('1,5'), BigInt.from(150));
    expect(parseMoneyCents('1,234'), isNull);
    expect(parseMoneyCents('-1'), isNull);
    expect(parseQuantityMicros('0,001'), BigInt.from(1000));
    expect(parseQuantityMicros('0'), isNull);
    expect(parseQuantityMicros('123456789.123456'), isNull);
    expect(expectedAmountCents(BigInt.from(500000), BigInt.one), BigInt.one);
    expect(moneyForApi(BigInt.from(150)), '1.50');
  });

  test('PUT sends full corrected receipt and preserves OCR source', () async {
    final api = ReceiptApi(
      'http://localhost:8000',
      client: MockClient((request) async {
        expect(request.method, 'PUT');
        expect(request.url.path, '/receipts/12');
        expect(request.headers['content-type'], startsWith('application/json'));
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['raw_text'], 'CHLEB 2,00');
        expect(payload['items'], hasLength(1));
        expect((payload['items'] as List).first['discount'], '0.50');
        expect(payload['total'], '1.50');
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'id': 12,
              'receipt': payload,
              'validation': {'matches': true},
            }),
          ),
          200,
        );
      }),
    );
    addTearDown(api.close);
    final payload = Map<String, dynamic>.from(originalJson['receipt'] as Map)
      ..['total'] = '1.50'
      ..['items'] = [
        {
          'name': 'Chleb',
          'quantity': '1',
          'unit_price': '2.00',
          'amount': '2.00',
          'discount': '0.50',
          'vat': 'C',
        },
      ];
    expect((await api.updateReceipt(12, payload)).validation?['matches'], true);
  });

  testWidgets('Editor warns, validates discount, and saves corrected values', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    Map<String, dynamic>? saved;
    final api = ReceiptApi(
      'http://localhost',
      client: MockClient((request) async {
        saved = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'id': 12,
              'receipt': saved,
              'validation': {'matches': true},
            }),
          ),
          200,
        );
      }),
    );
    addTearDown(api.close);
    final receipt = UploadedReceipt.fromJson(originalJson);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<UploadedReceipt>(
                  builder: (_) => ReceiptEditPage(original: receipt, api: api),
                ),
              ),
              child: const Text('Otwórz'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Otwórz'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '  Chleb żytni  ');
    await tester.enterText(fields.at(4), '3,00');
    await tester.ensureVisible(find.text('Zapisz korektę'));
    await tester.tap(find.text('Zapisz korektę'));
    await tester.pumpAndSettle();
    expect(
      find.text('Rabat nie może przekraczać wartości pozycji'),
      findsOneWidget,
    );
    expect(saved, isNull);
    await tester.enterText(fields.at(4), '0,50');
    await tester.pump();
    await tester.scrollUntilVisible(
      find.textContaining('Suma pozycji po rabatach'),
      150,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      find.textContaining('Suma pozycji po rabatach: 1,50 PLN'),
      findsOneWidget,
    );
    await tester.enterText(fields.at(5), '1,50');
    await tester.pumpAndSettle();
    expect(find.textContaining('Suma pozycji po rabatach'), findsNothing);
    await tester.tap(find.text('Zapisz korektę'));
    await tester.pumpAndSettle();
    expect((saved!['items'] as List).single['name'], 'Chleb żytni');
    expect((saved!['items'] as List).single['discount'], '0.50');
    expect(saved!['total'], '1.50');
    expect(saved!['raw_text'], 'CHLEB 2,00');
    expect(saved!['warnings'], ['Wiersz wymagał sprawdzenia']);
  });

  testWidgets('Editor adds and removes product rows', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final api = ReceiptApi(
      'http://localhost',
      client: MockClient((_) async => throw StateError('No save')),
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: ReceiptEditPage(
          original: UploadedReceipt.fromJson(originalJson),
          api: api,
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Dodaj produkt'),
      150,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Dodaj produkt'));
    await tester.pumpAndSettle();
    expect(find.text('Produkt 2'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Usuń produkt 2'));
    await tester.tap(find.byTooltip('Usuń produkt 2'));
    await tester.pumpAndSettle();
    expect(find.text('Produkt 2'), findsNothing);
    expect(find.text('Produkt 1'), findsOneWidget);
  });
}
