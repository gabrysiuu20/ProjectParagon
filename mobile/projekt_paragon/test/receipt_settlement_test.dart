import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:projekt_paragon/api.dart';
import 'package:projekt_paragon/receipt_api.dart';
import 'package:projekt_paragon/receipt_settlement_page.dart';
import 'package:projekt_paragon/settlement_math.dart';

const receipt = <String, dynamic>{
  'id': 12,
  'receipt': {
    'items': [
      {
        'name': 'Chleb',
        'quantity': '1',
        'unit_price': '0.05',
        'amount': '0.05',
        'discount': '0.00',
        'vat': 'C',
      },
      {
        'name': 'Jogurt',
        'quantity': '1',
        'unit_price': '2.50',
        'amount': '2.50',
        'discount': '0.50',
        'vat': 'C',
      },
    ],
    'total': '2.05',
    'raw_text': 'CHLEB JOGURT',
    'warnings': <String>[],
  },
  'validation': {'matches': true},
};

class FakePeopleApi implements PeopleApi {
  final people = <Person>[
    const Person(id: 1, name: 'Ala'),
    const Person(id: 2, name: 'Ela'),
  ];

  @override
  Future<List<Person>> getPeople() async => people;

  @override
  Future<Person> addPerson(String name) async {
    final person = Person(id: people.length + 1, name: name);
    people.add(person);
    return person;
  }

  @override
  void close() {}
}

void main() {
  test('Splits discounted net costs and conserves odd cents', () {
    final items =
        (receipt['receipt'] as Map<String, dynamic>)['items'] as List<dynamic>;
    final preview = previewSettlement(items.cast<Map<String, dynamic>>(), {
      0: {3, 1, 2},
    });
    expect(preview.totals, {
      1: BigInt.from(2),
      2: BigInt.from(2),
      3: BigInt.one,
    });
    expect(preview.unassignedCents, BigInt.from(200));
    expect(preview.computedTotalCents, BigInt.from(205));
    expect(preview.complete, isFalse);
    final full = previewSettlement(items.cast<Map<String, dynamic>>(), {
      0: {3, 1, 2},
      1: {2},
    });
    expect(full.totals[2], BigInt.from(202));
    expect(full.unassignedCents, BigInt.zero);
    expect(full.complete, isTrue);
  });

  testWidgets('Assigns, saves and reloads a partial split', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final peopleApi = FakePeopleApi();
    Map<String, dynamic>? saved;
    final api = ReceiptApi(
      'http://localhost:8000',
      client: MockClient((request) async {
        expect(request.url.path, startsWith('/receipts/12'));
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({...receipt, 'settlement': saved}),
            200,
          );
        }
        expect(request.method, 'PUT');
        expect(request.url.path, '/receipts/12/settlement');
        saved = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'totals': {'1': '0.05'},
            'unassigned_amount': '2.00',
            'complete': false,
            'receipt_validation': {'matches': true},
          }),
          200,
        );
      }),
    );
    addTearDown(api.close);

    Widget page() => MaterialApp(
      home: ReceiptSettlementPage(
        receipt: UploadedReceipt.fromJson(receipt),
        api: api,
        address: 'http://localhost:8000',
        peopleApi: peopleApi,
      ),
    );
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text('Nieprzypisane'), findsWidgets);
    await tester.tap(find.text('Chleb'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('item-0-person-1')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Zapisz podział'));
    await tester.tap(find.text('Zapisz podział'));
    await tester.pumpAndSettle();
    expect(saved?['assignments'], [
      {
        'item_index': 0,
        'person_ids': [1],
      },
    ]);
    expect(find.text('Zapisano częściowy podział kosztów.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chleb'));
    await tester.pumpAndSettle();
    final checkbox = tester.widget<CheckboxListTile>(
      find.byKey(const ValueKey('item-0-person-1')),
    );
    expect(checkbox.value, isTrue);
  });

  testWidgets('Can add a person before assigning products', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final peopleApi = FakePeopleApi()..people.clear();
    final api = ReceiptApi(
      'http://localhost:8000',
      client: MockClient(
        (_) async =>
            http.Response(jsonEncode({...receipt, 'settlement': null}), 200),
      ),
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: ReceiptSettlementPage(
          receipt: UploadedReceipt.fromJson(receipt),
          api: api,
          address: 'http://localhost:8000',
          peopleApi: peopleApi,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Dodaj osobę, aby przypisać produkty.'), findsOneWidget);
    await tester.tap(find.text('Dodaj osobę'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  Ola  ');
    await tester.tap(find.widgetWithText(FilledButton, 'Dodaj'));
    await tester.pumpAndSettle();
    expect(peopleApi.people.single.name, 'Ola');
    await tester.tap(find.text('Chleb'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('item-0-person-1')), findsOneWidget);
  });

  testWidgets('Failed refresh cannot save stale assignments', (tester) async {
    final api = ReceiptApi(
      'http://localhost:8000',
      client: MockClient((_) async => http.Response('', 503)),
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: ReceiptSettlementPage(
          receipt: UploadedReceipt.fromJson(receipt),
          api: api,
          address: 'http://localhost:8000',
          peopleApi: FakePeopleApi(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ponów wczytywanie'), findsOneWidget);
    expect(find.text('Zapisz podział'), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
  });
}
