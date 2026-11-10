import 'package:flutter/material.dart';

import 'api.dart';
import 'receipt_api.dart';
import 'receipt_math.dart';

class ReceiptEditPage extends StatefulWidget {
  const ReceiptEditPage({super.key, required this.original, required this.api});

  final UploadedReceipt original;
  final ReceiptApi api;

  @override
  State<ReceiptEditPage> createState() => _ReceiptEditPageState();
}

class _ItemDraft {
  _ItemDraft(Map<String, dynamic> item)
    : name = TextEditingController(text: item['name']?.toString() ?? ''),
      quantity = TextEditingController(
        text: item['quantity']?.toString() ?? '1',
      ),
      unitPrice = TextEditingController(
        text: item['unit_price']?.toString() ?? '0.00',
      ),
      amount = TextEditingController(
        text: item['amount']?.toString() ?? '0.00',
      ),
      discount = TextEditingController(
        text: item['discount']?.toString() ?? '0.00',
      ),
      vat = item['vat']?.toString();

  final TextEditingController name;
  final TextEditingController quantity;
  final TextEditingController unitPrice;
  final TextEditingController amount;
  final TextEditingController discount;
  String? vat;

  void dispose() {
    name.dispose();
    quantity.dispose();
    unitPrice.dispose();
    amount.dispose();
    discount.dispose();
  }

  Map<String, dynamic> toJson() => {
    'name': name.text.trim(),
    'quantity': quantity.text.trim().replaceAll(',', '.'),
    'unit_price': moneyForApi(parseMoneyCents(unitPrice.text)!),
    'amount': moneyForApi(parseMoneyCents(amount.text)!),
    'discount': moneyForApi(parseMoneyCents(discount.text)!),
    'vat': vat,
  };
}

class _ReceiptEditPageState extends State<ReceiptEditPage> {
  final _form = GlobalKey<FormState>();
  final _items = <_ItemDraft>[];
  late final TextEditingController _total;
  bool _saving = false;
  bool _dirty = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _items.addAll(
      (widget.original.receipt['items'] as List).map(
        (item) => _ItemDraft(item as Map<String, dynamic>),
      ),
    );
    _total = TextEditingController(
      text: widget.original.receipt['total']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.dispose();
    }
    _total.dispose();
    super.dispose();
  }

  List<String> _warnings() {
    final warnings = <String>[];
    var computed = BigInt.zero;
    for (var index = 0; index < _items.length; index++) {
      final item = _items[index];
      final amount = parseMoneyCents(item.amount.text);
      final discount = parseMoneyCents(item.discount.text);
      final quantity = parseQuantityMicros(item.quantity.text);
      final price = parseMoneyCents(item.unitPrice.text);
      if (amount != null && discount != null) computed += amount - discount;
      if (amount != null &&
          quantity != null &&
          price != null &&
          expectedAmountCents(quantity, price) != amount) {
        warnings.add(
          'Pozycja ${index + 1}: ilość × cena nie zgadza się z wartością.',
        );
      }
    }
    if (_items.isEmpty) warnings.add('Paragon nie ma żadnych produktów.');
    if (_total.text.trim().isEmpty) {
      warnings.add('Nie podano sumy paragonu.');
    } else if (parseMoneyCents(_total.text) case final BigInt total) {
      if (computed != total) {
        warnings.add(
          'Suma pozycji po rabatach: ${moneyForDisplay(computed)} PLN; suma paragonu: ${moneyForDisplay(total)} PLN.',
        );
      }
    }
    return warnings;
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final payload = {
        'items': _items.map((item) => item.toJson()).toList(),
        'total': _total.text.trim().isEmpty
            ? null
            : moneyForApi(parseMoneyCents(_total.text)!),
        'raw_text': widget.original.receipt['raw_text'],
        // These are notes from the original OCR. The live checks are shown
        // separately and the API recalculates its validation after saving.
        'warnings': widget.original.receipt['warnings'],
      };
      final updated = await widget.api.updateReceipt(
        widget.original.id,
        payload,
      );
      if (mounted) {
        setState(() => _dirty = false);
        Navigator.of(context).pop(updated);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiException
              ? error.message
              : 'Nie udało się zapisać korekty. Spróbuj ponownie.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _markChanged() => setState(() => _dirty = true);

  void _addItem() => setState(() {
    _dirty = true;
    _items.add(
      _ItemDraft({
        'quantity': '1',
        'unit_price': '0.00',
        'amount': '0.00',
        'discount': '0.00',
      }),
    );
  });

  void _removeItem(_ItemDraft item) {
    setState(() {
      _dirty = true;
      _items.remove(item);
    });
    // The old form subtree must unmount before its controllers are disposed.
    WidgetsBinding.instance.addPostFrameCallback((_) => item.dispose());
  }

  Widget _moneyField(
    String label,
    TextEditingController controller, {
    String? Function(String?)? validator,
  }) => TextFormField(
    controller: controller,
    enabled: !_saving,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: label,
      suffixText: 'PLN',
      border: const OutlineInputBorder(),
    ),
    validator:
        validator ??
        (value) => parseMoneyCents(value ?? '') == null
            ? 'Podaj kwotę z maks. 2 miejscami po przecinku'
            : null,
    onChanged: (_) => _markChanged(),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving && !_dirty,
    onPopInvokedWithResult: (didPop, result) async {
      if (didPop || _saving) return;
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Odrzucić niezapisane zmiany?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Wróć do edycji'),
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
        Navigator.of(this.context).pop();
      }
    },
    child: Scaffold(
      appBar: AppBar(title: Text('Korekta paragonu #${widget.original.id}')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Form(
            key: _form,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Popraw nazwy, ilości, ceny, wartości i rabaty. Wartość pozycji wpisz zgodnie z paragonem; różnica względem ilości × ceny pojawi się jako ostrzeżenie.',
                ),
                const SizedBox(height: 16),
                for (var index = 0; index < _items.length; index++)
                  Card(
                    key: ObjectKey(_items[index]),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Produkt ${index + 1}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                              IconButton(
                                onPressed: _saving
                                    ? null
                                    : () => _removeItem(_items[index]),
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Usuń produkt ${index + 1}',
                              ),
                            ],
                          ),
                          TextFormField(
                            controller: _items[index].name,
                            enabled: !_saving,
                            maxLength: 300,
                            decoration: const InputDecoration(
                              labelText: 'Nazwa',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? 'Wpisz nazwę produktu'
                                : null,
                            onChanged: (_) => _markChanged(),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _items[index].quantity,
                            enabled: !_saving,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Ilość',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) =>
                                parseQuantityMicros(value ?? '') == null
                                ? 'Podaj dodatnią ilość (maks. 6 miejsc po przecinku)'
                                : null,
                            onChanged: (_) => _markChanged(),
                          ),
                          const SizedBox(height: 8),
                          _moneyField(
                            'Cena jednostkowa',
                            _items[index].unitPrice,
                          ),
                          const SizedBox(height: 8),
                          _moneyField(
                            'Wartość pozycji przed rabatem',
                            _items[index].amount,
                          ),
                          const SizedBox(height: 8),
                          _moneyField(
                            'Rabat',
                            _items[index].discount,
                            validator: (value) {
                              final discount = parseMoneyCents(value ?? '');
                              if (discount == null) {
                                return 'Podaj nieujemny rabat z maks. 2 miejscami po przecinku';
                              }
                              final amount = parseMoneyCents(
                                _items[index].amount.text,
                              );
                              if (amount != null && discount > amount) {
                                return 'Rabat nie może przekraczać wartości pozycji';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String?>(
                            initialValue: _items[index].vat,
                            decoration: const InputDecoration(
                              labelText: 'Stawka VAT (oznaczenie z paragonu)',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('Nieznana'),
                              ),
                              for (final code in [
                                'A',
                                'B',
                                'C',
                                'D',
                                'E',
                                'F',
                                'G',
                              ])
                                DropdownMenuItem<String?>(
                                  value: code,
                                  child: Text(code),
                                ),
                            ],
                            onChanged: _saving
                                ? null
                                : (value) => setState(() {
                                    _items[index].vat = value;
                                    _dirty = true;
                                  }),
                          ),
                        ],
                      ),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _addItem,
                  icon: const Icon(Icons.add),
                  label: const Text('Dodaj produkt'),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _total,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Suma na paragonie',
                    suffixText: 'PLN',
                    helperText: 'Zostaw puste, jeśli suma jest nieczytelna',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value == null ||
                          value.trim().isEmpty ||
                          parseMoneyCents(value) != null
                      ? null
                      : 'Podaj kwotę z maks. 2 miejscami po przecinku',
                  onChanged: (_) => _markChanged(),
                ),
                const SizedBox(height: 16),
                Text(
                  'Kontrola kwot',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_warnings().isEmpty)
                  const Text('Ilości, wartości i suma są zgodne.'),
                for (final warning in _warnings())
                  Text(
                    '• $warning',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if ((widget.original.receipt['warnings'] as List)
                    .isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ExpansionTile(
                    title: const Text('Uwagi z pierwotnego odczytu OCR'),
                    children: [
                      for (final warning
                          in (widget.original.receipt['warnings'] as List))
                        ListTile(title: Text('$warning')),
                    ],
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Zapisz korektę'),
                ),
                if (_saving) const LinearProgressIndicator(),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
