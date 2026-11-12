import 'package:flutter/material.dart';

import 'api.dart';
import 'receipt_api.dart';
import 'receipt_math.dart';
import 'settlement_math.dart';

class ReceiptSettlementPage extends StatefulWidget {
  const ReceiptSettlementPage({
    super.key,
    required this.receipt,
    required this.api,
    required this.address,
    this.peopleApi,
  });

  final UploadedReceipt receipt;
  final ReceiptApi api;
  final String address;
  final PeopleApi? peopleApi;

  @override
  State<ReceiptSettlementPage> createState() => _ReceiptSettlementPageState();
}

class _ReceiptSettlementPageState extends State<ReceiptSettlementPage> {
  late final PeopleApi _peopleApi =
      widget.peopleApi ?? ParagonApi(widget.address);
  List<Person> _people = [];
  late UploadedReceipt _receipt = widget.receipt;
  Map<int, Set<int>> _assignments = {};
  SettlementResult? _savedResult;
  bool _loading = true;
  bool _loaded = false;
  bool _saving = false;
  bool _addingPerson = false;
  bool _dirty = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (widget.peopleApi == null) _peopleApi.close();
    super.dispose();
  }

  Future<void> _load() async {
    if (_saving || _dirty) return;
    setState(() {
      _loading = true;
      _loaded = false;
      _error = null;
    });
    try {
      final loaded = await Future.wait<Object>([
        _peopleApi.getPeople(),
        widget.api.getReceipt(widget.receipt.id),
      ]);
      final receipt = loaded[1] as UploadedReceipt;
      final assignments = <int, Set<int>>{};
      final saved = receipt.settlement?['assignments'] as List<dynamic>? ?? [];
      for (final entry in saved) {
        final data = entry as Map<String, dynamic>;
        assignments[data['item_index'] as int] = {
          for (final id in data['person_ids'] as List<dynamic>) id as int,
        };
      }
      if (!mounted) return;
      setState(() {
        _people = List<Person>.of(loaded[0] as List<Person>);
        _receipt = receipt;
        _assignments = assignments;
        _savedResult = null;
        _loaded = true;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiException
              ? error.message
              : 'Nie udało się wczytać rozliczenia. Spróbuj ponownie.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggle(int index, int personId, bool selected) {
    setState(() {
      final ids = _assignments.putIfAbsent(index, () => <int>{});
      if (selected) {
        ids.add(personId);
      } else {
        ids.remove(personId);
        if (ids.isEmpty) _assignments.remove(index);
      }
      _dirty = true;
      _savedResult = null;
      _error = null;
    });
  }

  Future<void> _addPerson() async {
    if (_addingPerson || _saving) return;
    var draft = '';
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dodaj osobę'),
        content: TextField(
          autofocus: true,
          maxLength: 100,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Imię lub nazwa'),
          onChanged: (value) => draft = value,
          onSubmitted: (_) => Navigator.pop(context, draft.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, draft.trim()),
            child: const Text('Dodaj'),
          ),
        ],
      ),
    );
    if (!mounted || name == null || name.isEmpty) return;
    setState(() {
      _addingPerson = true;
      _error = null;
    });
    try {
      final person = await _peopleApi.addPerson(name);
      if (mounted) setState(() => _people = [..._people, person]);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiException
              ? error.message
              : 'Nie udało się dodać osoby.',
        );
      }
    } finally {
      if (mounted) setState(() => _addingPerson = false);
    }
  }

  Future<void> _save() async {
    if (_loading || _saving || _addingPerson || !_dirty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.api.updateSettlement(
        _receipt.id,
        _assignments,
      );
      if (!mounted) return;
      setState(() {
        _savedResult = result;
        _dirty = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.complete
                ? 'Zapisano pełny podział kosztów.'
                : 'Zapisano częściowy podział kosztów.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiException
              ? error.message
              : 'Nie udało się zapisać podziału. Spróbuj ponownie.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDiscard(bool didPop) async {
    if (didPop || _saving) return;
    if (!_dirty) return;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Odrzucić niezapisany podział?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Wróć do podziału'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Odrzuć'),
          ),
        ],
      ),
    );
    if (mounted && discard == true) {
      setState(() => _dirty = false);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = (_receipt.receipt['items'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final preview = previewSettlement(items, _assignments);
    final totals = _savedResult?.totals ?? preview.totals;
    final unassigned = _savedResult?.unassignedCents ?? preview.unassignedCents;
    final complete = _savedResult?.complete ?? preview.complete;
    final receiptTotal = _receipt.receipt['total'] == null
        ? null
        : parseMoneyCents(_receipt.receipt['total'].toString());
    return PopScope(
      canPop: !_saving && !_dirty,
      onPopInvokedWithResult: (didPop, _) => _confirmDiscard(didPop),
      child: Scaffold(
        appBar: AppBar(title: Text('Podział paragonu #${_receipt.id}')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Wybierz osoby dla każdej pozycji. Kwota po rabacie dzieli się równo; pozostałe grosze trafiają kolejno do osób o niższych identyfikatorach.',
                ),
                const SizedBox(height: 12),
                if (_loading || _saving || _addingPerson)
                  const LinearProgressIndicator(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Wczytywanie paragonu i osób…'),
                  )
                else if (!_loaded)
                  OutlinedButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Ponów wczytywanie'),
                  )
                else ...[
                  if (receiptTotal == null ||
                      receiptTotal != preview.computedTotalCents)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          receiptTotal == null
                              ? 'Brak sumy paragonu. Sprawdź produkty przed podziałem.'
                              : 'Suma pozycji po rabatach (${moneyForDisplay(preview.computedTotalCents)} PLN) różni się od sumy paragonu (${moneyForDisplay(receiptTotal)} PLN).',
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Osoby (${_people.length})',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _addingPerson || _saving ? null : _addPerson,
                        icon: const Icon(Icons.person_add_alt_1),
                        label: const Text('Dodaj osobę'),
                      ),
                    ],
                  ),
                  if (_people.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Dodaj osobę, aby przypisać produkty.'),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Produkty (${items.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Paragon nie ma produktów. Popraw go przed podziałem.',
                      ),
                    ),
                  for (var index = 0; index < items.length; index++)
                    _itemCard(index, items[index]),
                  const SizedBox(height: 16),
                  Text(
                    'Podsumowanie',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  for (final person in _people)
                    ListTile(
                      dense: true,
                      title: Text(person.name),
                      trailing: Text(
                        '${moneyForDisplay(totals[person.id] ?? BigInt.zero)} PLN',
                      ),
                    ),
                  ListTile(
                    dense: true,
                    title: const Text('Nieprzypisane'),
                    trailing: Text('${moneyForDisplay(unassigned)} PLN'),
                  ),
                  Text(
                    complete ? 'Wszystkie produkty zostały przypisane.' : 'Podział jest niepełny. Możesz go zapisać i wrócić do niego z bieżącego ekranu paragonu.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _dirty && !_saving && !_addingPerson
                        ? _save
                        : null,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Zapisz podział'),
                  ),
                  OutlinedButton(
                    onPressed: _dirty || _saving || _addingPerson
                        ? null
                        : _load,
                    child: const Text('Odśwież z serwera'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _itemCard(int index, Map<String, dynamic> item) {
    final selected = _assignments[index] ?? <int>{};
    final names = [
      for (final person in _people)
        if (selected.contains(person.id)) person.name,
    ];
    final amount = netItemCents(item);
    final discount = parseMoneyCents(item['discount']?.toString() ?? '0')!;
    return Card(
      child: ExpansionTile(
        key: ValueKey('item-$index'),
        title: Row(
          children: [
            Expanded(
              child: Text(item['name']?.toString() ?? 'Produkt ${index + 1}'),
            ),
            const SizedBox(width: 8),
            Text('${moneyForDisplay(amount)} PLN'),
          ],
        ),
        subtitle: Text(
          '${names.isEmpty ? 'Nieprzypisany' : names.join(', ')}'
          '${discount > BigInt.zero ? ' · rabat ${moneyForDisplay(discount)} PLN' : ''}',
        ),
        children: [
          for (final person in _people)
            CheckboxListTile(
              key: ValueKey('item-$index-person-${person.id}'),
              dense: true,
              title: Text(person.name),
              value: selected.contains(person.id),
              onChanged: _saving
                  ? null
                  : (value) => _toggle(index, person.id, value ?? false),
            ),
        ],
      ),
    );
  }
}
