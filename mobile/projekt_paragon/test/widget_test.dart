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
  testWidgets('Loads friends, validates input and adds trimmed name', (
    tester,
  ) async {
    final api = FakeApi();
    await tester.pumpWidget(MyApp(apiFactory: (_) => api));
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
    await tester.pumpWidget(MyApp(apiFactory: (_) => api));
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
    await tester.pumpWidget(MyApp(apiFactory: (_) => api));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'bad-address');
    await tester.tap(find.text('Połącz'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Podaj adres serwera'), findsOneWidget);
  });
}
