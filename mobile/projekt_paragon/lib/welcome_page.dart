import 'dart:math' as math;

import 'package:flutter/material.dart';

const _brown = Color(0xFF934413);
const _muted = Color(0xFF828282);
const _assetRoot = 'assets/welcome';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  void _unavailable(String provider) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Logowanie przez $provider nie jest jeszcze dostępne.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = math.max(680.0, constraints.maxHeight);
          return SingleChildScrollView(
            child: Center(
              child: SizedBox(
                width: math.min(375, constraints.maxWidth),
                height: height,
                child: Stack(
                  children: [
                    const _ReceiptDecorations(),
                    const Positioned(
                      top: 64,
                      left: 0,
                      right: 0,
                      child: Text(
                        'MyParagon',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _brown,
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.24,
                        ),
                      ),
                    ),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: _WelcomeContent(
                          onContinue: widget.onContinue,
                          onProvider: _unavailable,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _ReceiptDecorations extends StatelessWidget {
  const _ReceiptDecorations();

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 25,
          left: -1,
          child: Image.asset(
            '$_assetRoot/receipt_shop.png',
            width: 114,
            height: 180,
          ),
        ),
        Positioned(
          top: 21,
          right: -4,
          child: Image.asset(
            '$_assetRoot/receipt_cafe.png',
            width: 92,
            height: 156,
          ),
        ),
        Positioned(
          bottom: -10,
          left: 20,
          child: Image.asset(
            '$_assetRoot/receipt_store.png',
            width: 133,
            height: 183,
          ),
        ),
        Positioned(
          bottom: 0,
          right: -1,
          child: Image.asset(
            '$_assetRoot/receipt_bakery.png',
            width: 111,
            height: 162,
          ),
        ),
      ],
    ),
  );
}

class _WelcomeContent extends StatelessWidget {
  const _WelcomeContent({required this.onContinue, required this.onProvider});

  final VoidCallback onContinue;
  final void Function(String) onProvider;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text(
        'Stwórz konto',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 2),
      const Text(
        'Wprowadź adres email żeby dołączyć',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14),
      ),
      const SizedBox(height: 24),
      SizedBox(
        height: 40,
        child: TextField(
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: InputDecoration(
            hintText: 'email@domain.com',
            hintStyle: const TextStyle(color: _muted, fontSize: 14),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        height: 40,
        child: FilledButton(
          onPressed: onContinue,
          style: FilledButton.styleFrom(
            backgroundColor: _brown,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text(
            'Kontynuuj',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
      ),
      const SizedBox(height: 24),
      const Row(
        children: [
          Expanded(child: Divider(color: Color(0xFFE6E6E6))),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('or', style: TextStyle(color: _muted, fontSize: 14)),
          ),
          Expanded(child: Divider(color: Color(0xFFE6E6E6))),
        ],
      ),
      const SizedBox(height: 24),
      _ProviderButton(
        asset: '$_assetRoot/google.png',
        label: 'Zaloguj się z Google',
        onPressed: () => onProvider('Google'),
      ),
      const SizedBox(height: 8),
      _ProviderButton(
        asset: '$_assetRoot/apple.png',
        label: 'Zaloguj się z Apple',
        onPressed: () => onProvider('Apple'),
      ),
      const SizedBox(height: 24),
      const Text(
        'Klikając kontynuuj akceptujesz nasz Regulamin oraz Politykę Prywatności',
        textAlign: TextAlign.center,
        style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
      ),
    ],
  );
}

class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.asset,
    required this.label,
    required this.onPressed,
  });

  final String asset;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 40,
    child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFEEEEEE),
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(asset, width: 20, height: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    ),
  );
}
