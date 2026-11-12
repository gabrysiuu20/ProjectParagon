import 'package:flutter/material.dart';

import 'api.dart';
import 'receipt_page.dart';
import 'welcome_page.dart';

void main() => runApp(const MyApp());

typedef ApiFactory = PeopleApi Function(String address);

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.apiFactory, this.authenticated = false});
  final ApiFactory? apiFactory;
  // The backend does not provide authentication yet. A future auth integration
  // can pass its verified session state here; guest mode never changes it.
  final bool authenticated;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Projekt Paragon',
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
    home: authenticated
        ? PeoplePage(apiFactory: apiFactory ?? ParagonApi.new)
        : Builder(
            builder: (context) => WelcomePage(
              onContinue: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        PeoplePage(apiFactory: apiFactory ?? ParagonApi.new),
                  ),
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Tryb gościa: konto nie zostało utworzone.'),
                  ),
                );
              },
            ),
          ),
  );
}

class PeoplePage extends StatefulWidget {
  const PeoplePage({super.key, required this.apiFactory});
  final ApiFactory apiFactory;
  @override
  State<PeoplePage> createState() => _PeoplePageState();
}

class _PeoplePageState extends State<PeoplePage> {
  final _address = TextEditingController(
    text: const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://10.0.2.2:8000',
    ),
  );
  final _name = TextEditingController();
  final _form = GlobalKey<FormState>();
  PeopleApi? _api;
  List<Person> _people = [];
  bool _busy = false;
  String? _error;
  String? _connectedAddress;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _api?.close();
    _address.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_busy) return;
    try {
      final address = _address.text.trim();
      ParagonApi.validateAddress(address);
      final api = widget.apiFactory(address);
      _api?.close();
      _api = api;
      setState(() {
        _people = [];
        _connectedAddress = null;
        _error = null;
        _busy = true;
      });
      final people = await api.getPeople();
      if (!mounted) return;
      setState(() {
        _people = people;
        _connectedAddress = address;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    if (_busy || _api == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final people = await _api!.getPeople();
      if (mounted) setState(() => _people = people);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPerson() async {
    if (_busy || _connectedAddress == null || !_form.currentState!.validate()) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final person = await _api!.addPerson(_name.text.trim());
      if (!mounted) return;
      setState(() {
        _people = [..._people, person];
        _name.clear();
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Dodano osobę')));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Znajomi'),
      actions: [
        TextButton.icon(
          onPressed: _busy || _connectedAddress == null
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ReceiptPage(address: _connectedAddress!),
                  ),
                ),
          icon: const Icon(Icons.receipt_long),
          label: const Text('Dodaj paragon'),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Projekt Paragon',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text('Dodaj osoby, z którymi będziesz rozliczać zakupy.'),
              const SizedBox(height: 24),
              TextField(
                controller: _address,
                enabled: !_busy,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Adres serwera API',
                  helperText: 'Emulator Androida: http://10.0.2.2:8000',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: _busy ? null : _connect,
                child: const Text('Połącz'),
              ),
              if (_connectedAddress != null)
                Text('Połączono: $_connectedAddress'),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: LinearProgressIndicator(),
                ),
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
              const SizedBox(height: 24),
              Form(
                key: _form,
                child: TextFormField(
                  controller: _name,
                  enabled: !_busy && _connectedAddress != null,
                  maxLength: 100,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Imię lub nazwa osoby',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Wpisz nazwę osoby'
                      : null,
                  onFieldSubmitted: (_) => _addPerson(),
                ),
              ),
              FilledButton.icon(
                onPressed: _busy || _connectedAddress == null
                    ? null
                    : _addPerson,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Dodaj osobę'),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Twoi znajomi (${_people.length})',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: _busy || _connectedAddress == null
                        ? null
                        : _refresh,
                    tooltip: 'Odśwież listę',
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              if (_people.isEmpty && !_busy && _connectedAddress != null)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Nie masz jeszcze znajomych. Dodaj pierwszą osobę.',
                  ),
                ),
              for (final person in _people)
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.person_outline),
                    ),
                    title: Text(person.name),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
