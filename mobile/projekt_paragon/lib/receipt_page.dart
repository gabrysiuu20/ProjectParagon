import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';
import 'receipt_api.dart';
import 'receipt_edit_page.dart';

class ReceiptPage extends StatefulWidget {
  const ReceiptPage({super.key, required this.address, this.picker, this.api});
  final String address;
  final ImagePicker? picker;
  final ReceiptApi? api;

  @override
  State<ReceiptPage> createState() => _ReceiptPageState();
}

class _ReceiptPageState extends State<ReceiptPage> {
  late final _picker = widget.picker ?? ImagePicker();
  late final _api = widget.api ?? ReceiptApi(widget.address);
  Uint8List? _photo;
  UploadedReceipt? _result;
  String? _error;
  bool _busy = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) _recover();
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<void> _recover() => _run(() async {
    final lost = await _picker.retrieveLostData();
    if (lost.exception != null) throw lost.exception!;
    if (lost.files?.isNotEmpty ?? false) await _load(lost.files!.first);
  });

  Future<void> _load(XFile file) async {
    if (await file.length() > maxPhotoBytes) {
      throw const ApiException(
        'Zdjęcie przekracza limit 10 MB. Wybierz mniejsze zdjęcie.',
      );
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > maxPhotoBytes) {
      throw const ApiException(
        'Wybierz niepuste zdjęcie o rozmiarze do 10 MB.',
      );
    }
    if (mounted) {
      setState(() {
        _photo = bytes;
        _result = null;
      });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on PlatformException {
      if (mounted) {
        setState(
          () => _error = 'Nie można otworzyć aparatu lub galerii. Sprawdź uprawnienia aplikacji w ustawieniach telefonu.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiException ? error.message : 'Nie udało się odczytać zdjęcia lub przesłać danych. Spróbuj ponownie.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _uploading = false;
        });
      }
    }
  }

  Future<void> _pick(ImageSource source) => _run(() async {
    final file = await _picker.pickImage(
      source: source,
      maxWidth: 4000,
      maxHeight: 4000,
      imageQuality: 90,
      requestFullMetadata: false,
    );
    if (file != null) await _load(file);
  });

  Future<void> _upload() => _run(() async {
    setState(() => _uploading = true);
    final result = await _api.upload(_photo!);
    if (mounted) setState(() => _result = result);
  });

  Future<void> _edit(UploadedReceipt receipt) async {
    final updated = await Navigator.of(context).push<UploadedReceipt>(
      MaterialPageRoute(
        builder: (_) => ReceiptEditPage(original: receipt, api: _api),
      ),
    );
    if (mounted && updated != null) setState(() => _result = updated);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Dodaj paragon')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Zrób wyraźne zdjęcie całego paragonu, ustawionego pionowo. Po wybraniu zdjęcia sprawdź podgląd i wyślij je do odczytu.',
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Wybierz z galerii'),
              ),
              if (Platform.isAndroid || Platform.isIOS)
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Zrób zdjęcie'),
                ),
              if (_photo != null) ...[
                const SizedBox(height: 16),
                Image.memory(
                  _photo!,
                  height: 300,
                  fit: BoxFit.contain,
                  cacheWidth: 1200,
                  errorBuilder: (_, error, stack) => const Text(
                    'Podgląd niedostępny. W razie błędu odczytu wybierz zdjęcie JPG lub PNG.',
                  ),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _photo = null;
                          _result = null;
                          _error = null;
                        }),
                  child: const Text('Usuń zdjęcie'),
                ),
                FilledButton.icon(
                  onPressed: _busy || _result != null ? null : _upload,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Wyślij do odczytu'),
                ),
              ],
              if (_busy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
                Text(
                  _uploading
                      ? 'Przesyłanie i odczytywanie paragonu… Pierwszy odczyt może potrwać kilka minut.'
                      : 'Wczytywanie zdjęcia…',
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_result case final result?) ...[
                const SizedBox(height: 20),
                Text(
                  'Zapisano paragon #${result.id}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  'Liczba pozycji: ${(result.receipt['items'] as List).length}',
                ),
                Text(
                  'Suma na paragonie: ${result.receipt['total'] ?? 'nie odczytano'} PLN',
                ),
                if (result.validation?['matches'] case final bool matches)
                  Text(
                    matches ? 'Suma produktów jest zgodna z paragonem.' : 'Suma produktów nie zgadza się z paragonem. Sprawdź pozycje.',
                  ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _edit(result),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edytuj produkty i sumę'),
                ),
                const Text('Sprawdź nazwy i kwoty przed rozliczeniem.'),
                ExpansionTile(
                  title: const Text('Rozpoznane produkty'),
                  initiallyExpanded: true,
                  children: [
                    for (final item in (result.receipt['items'] as List))
                      ListTile(
                        title: Text(item['name'] as String),
                        subtitle: Text(
                          '${item['quantity']} × ${item['unit_price']} PLN'
                          '${item['discount'] != '0.00' ? ' · rabat ${item['discount']} PLN' : ''}',
                        ),
                        trailing: Text('${item['amount']} PLN'),
                      ),
                  ],
                ),
                if ((result.receipt['warnings'] as List).isNotEmpty)
                  const Text('Uwagi z pierwotnego odczytu OCR:'),
                for (final warning in (result.receipt['warnings'] as List))
                  Text('• $warning'),
                ExpansionTile(
                  title: const Text('Odczytany tekst'),
                  children: [
                    SelectableText(result.receipt['raw_text'] as String),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
