import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:projekt_paragon/api.dart';
import 'package:projekt_paragon/main.dart';

class FakeApi implements PeopleApi {
  final List<String> added = [];
  bool fail = false;
  @override
  Future<List<Person>> getPeople() async {
    if (fail) throw const ApiException('Brak połączenia');
    return [const Person(id: 1, name: 'Ala')];
  }

  @override
  Future<Person> addPerson(String name) async {
    added.add(name);
    return Person(id: 2, name: name);
  }

  @override
  void close() {}
}

void main() {
  testWidgets('Welcome screen renders every Figma asset at its export size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MyApp());
    const sizes = <String, Size>{
      'receipt_shop.png': Size(114, 180),
      'receipt_cafe.png': Size(92, 156),
      'receipt_store.png': Size(133, 183),
      'receipt_bakery.png': Size(111, 162),
      'google.png': Size(20, 20),
      'apple.png': Size(20, 20),
    };
    for (final entry in sizes.entries) {
      final asset = find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName.endsWith(entry.key),
      );
      expect(asset, findsOneWidget);
      expect(tester.getSize(asset), entry.value);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Welcome screen opens the app only after guest continues', (
    tester,
  ) async {
    final api = FakeApi();
    await tester.pumpWidget(MyApp(apiFactory: (_) => api));
    expect(find.text('MyParagon'), findsOneWidget);
    expect(find.text('Kontynuuj'), findsOneWidget);
    expect(find.text('Znajomi'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Kontynuuj'));
    await tester.pumpAndSettle();
    expect(find.text('Twoje ostatnio zakupione produkty'), findsOneWidget);
    expect(find.text('Ala'), findsNothing);

    await tester.tap(find.byTooltip('Znajomi i ustawienia'));
    await tester.pumpAndSettle();
    expect(find.text('Ala'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Twoje ostatnio zakupione produkty'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(find.text('MyParagon'), findsOneWidget);
  });

  testWidgets('Provider buttons do not create a session', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.text('Zaloguj się z Google'));
    await tester.pump();
    expect(find.textContaining('nie jest jeszcze dostępne'), findsOneWidget);
    expect(find.text('Znajomi'), findsNothing);
  });

  testWidgets('Loads friends, validates input and adds trimmed name', (
    tester,
  ) async {
    final api = FakeApi();
    await tester.pumpWidget(MyApp(apiFactory: (_) => api, authenticated: true));
    await tester.pumpAndSettle();
    expect(find.text('Kontynuuj'), findsNothing);
    await tester.tap(find.byTooltip('Znajomi i ustawienia'));
    await tester.pumpAndSettle();
    expect(find.text('Ala'), findsOneWidget);
    await tester.tap(find.text('Dodaj osobę'));
    await tester.pumpAndSettle();
    expect(find.text('Wpisz nazwę osoby'), findsOneWidget);
    expect(api.added, isEmpty);
    await tester.enterText(find.byType(TextFormField), '  Łukasz  ');
    await tester.tap(find.text('Dodaj osobę'));
    await tester.pumpAndSettle();
    expect(api.added, ['Łukasz']);
    await tester.scrollUntilVisible(
      find.text('Łukasz'),
      150,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Łukasz'), findsOneWidget);
  });

  testWidgets('Connection error allows retry', (tester) async {
    final api = FakeApi()..fail = true;
    await tester.pumpWidget(MyApp(apiFactory: (_) => api, authenticated: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Znajomi i ustawienia'));
    await tester.pumpAndSettle();
    expect(find.text('Brak połączenia'), findsOneWidget);
    api.fail = false;
    await tester.tap(find.text('Połącz'));
    await tester.pumpAndSettle();
    expect(find.text('Ala'), findsOneWidget);
    expect(find.text('Brak połączenia'), findsNothing);
  });

  testWidgets('Rejects invalid server address before connecting', (
    tester,
  ) async {
    final api = FakeApi();
    await tester.pumpWidget(MyApp(apiFactory: (_) => api, authenticated: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Znajomi i ustawienia'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'bad-address');
    await tester.tap(find.text('Połącz'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Podaj adres serwera'), findsOneWidget);
  });
}
