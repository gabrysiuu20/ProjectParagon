import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

const _brown = Color(0xFF934413);
const _ink = Color(0xFF161823);
const _muted = Color(0xFF828282);
const _border = Color(0xFFE0E0E0);
const _assetRoot = 'assets/dashboard';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.onOpenWorkspace});

  final VoidCallback onOpenWorkspace;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String _query = '';

  static const _products = [
    _SampleProduct('Skyr Piątnica', 'skyr.png'),
    _SampleProduct('Banan luz', 'banana.png'),
    _SampleProduct('Granola One Day More', 'granola.png'),
    _SampleProduct('Hummus', 'hummus.png'),
  ];
  static const _stores = [
    _SampleStore('Biedronka', 'Sklep spożywczy', 'biedronka.png'),
    _SampleStore('Action', 'Sklep wielobranżowy', 'action.png'),
    _SampleStore('Lidl', 'Sklep spożywczy', 'lidl.png'),
  ];

  void _explainExamples() => ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'To przykłady z projektu. Historia Twoich zakupów nie jest jeszcze dostępna na tym ekranie.',
      ),
    ),
  );

  void _notAvailable(String feature) => ScaffoldMessenger.of(context)
      .showSnackBar(
        SnackBar(
          content: Text(
            '$feature: ta część aplikacji nie jest jeszcze dostępna.',
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final products = [
      for (final product in _products)
        if (product.name.toLowerCase().contains(query)) product,
    ];
    final stores = [
      for (final store in _stores)
        if (store.name.toLowerCase().contains(query)) store,
    ];
    // Keep the store cards near the bottom tabs on taller phones. Put any
    // extra room above the store section, where it cannot hide product text.
    final media = MediaQuery.of(context);
    final listHeight = media.size.height - media.padding.vertical - 44;
    final storeOffset = math.max(0.0, listHeight - 747);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 375),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    children: [
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SizedBox(
                          height: 40,
                          child: TextField(
                            onChanged: (value) =>
                                setState(() => _query = value),
                            textInputAction: TextInputAction.search,
                            decoration: InputDecoration(
                              hintText: 'Search',
                              hintStyle: const TextStyle(
                                color: _muted,
                                fontSize: 16,
                              ),
                              prefixIcon: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: SvgPicture.asset(
                                  '$_assetRoot/search.svg',
                                  width: 24,
                                  height: 24,
                                ),
                              ),
                              prefixIconConstraints: const BoxConstraints(
                                minWidth: 48,
                                minHeight: 40,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 8,
                              ),
                              border: _searchBorder,
                              enabledBorder: _searchBorder,
                              focusedBorder: _searchBorder,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 32,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                _Shortcut(
                                  icon: 'favorite.svg',
                                  label: 'Favorites',
                                  onTap: () => _notAvailable('Ulubione'),
                                ),
                                const SizedBox(width: 8),
                                _Shortcut(
                                  icon: 'history.svg',
                                  label: 'History',
                                  onTap: () => _notAvailable('Historia'),
                                ),
                                const SizedBox(width: 8),
                                _Shortcut(
                                  icon: 'following.svg',
                                  label: 'Following',
                                  onTap: widget.onOpenWorkspace,
                                ),
                                const SizedBox(width: 8),
                                _Shortcut(
                                  icon: 'order.svg',
                                  label: 'Orders',
                                  onTap: widget.onOpenWorkspace,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: const [
                            Expanded(
                              child: _BalanceCard(title: 'Jesteś dłużny:'),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: _BalanceCard(title: 'Inni są Ci winni:'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SectionTitle(
                        title: 'Twoje ostatnio zakupione produkty',
                        icon: 'chevron.svg',
                        onTap: _explainExamples,
                      ),
                      SizedBox(
                        height: 160,
                        child: products.isEmpty
                            ? const _NoSearchResults()
                            : ListView.separated(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  8,
                                  16,
                                  0,
                                ),
                                itemCount: products.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 24),
                                itemBuilder: (context, index) => _ProductCard(
                                  product: products[index],
                                  onTap: _explainExamples,
                                ),
                              ),
                      ),
                      SizedBox(height: storeOffset),
                      _SectionTitle(
                        title: 'Miejsca, w których kupujesz',
                        icon: 'section_chevron.svg',
                        onTap: _explainExamples,
                      ),
                      SizedBox(
                        height: 239,
                        child: stores.isEmpty
                            ? const _NoSearchResults()
                            : ListView.separated(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  8,
                                  16,
                                  0,
                                ),
                                itemCount: stores.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 12),
                                itemBuilder: (context, index) => _StoreCard(
                                  store: stores[index],
                                  onTap: _explainExamples,
                                ),
                              ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
                _BottomTabs(
                  onOpenWorkspace: widget.onOpenWorkspace,
                  onNotifications: () => _notAvailable('Powiadomienia'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final _searchBorder = OutlineInputBorder(
  borderRadius: BorderRadius.circular(8),
  borderSide: const BorderSide(color: _border),
);

class _Shortcut extends StatelessWidget {
  const _Shortcut({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final String icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFEEEEEE),
        border: Border.all(color: const Color(0xFFE6E6E6)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset('$_assetRoot/$icon', width: 18, height: 18),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 14, color: _ink)),
        ],
      ),
    ),
  );
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Container(
    height: 128,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      border: Border.all(color: _border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          '— zł',
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _brown,
            fontSize: 28,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.56,
          ),
        ),
        const Spacer(),
        const Text(
          'Brak danych o saldzie',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: _muted, fontSize: 12),
        ),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: SizedBox(
      height: 38,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _brown,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.32,
                ),
              ),
            ),
            const SizedBox(width: 10),
            SvgPicture.asset('$_assetRoot/$icon', width: 20, height: 20),
          ],
        ),
      ),
    ),
  );
}

class _SampleProduct {
  const _SampleProduct(this.name, this.image);
  final String name;
  final String image;
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onTap});

  final _SampleProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: SizedBox(
      width: 76,
      child: Column(
        children: [
          ClipOval(
            child: Image.asset(
              '$_assetRoot/${product.image}',
              width: 76,
              height: 76,
              fit: BoxFit.cover,
              cacheWidth: (76 * MediaQuery.devicePixelRatioOf(context)).ceil(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            product.name,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _ink, fontSize: 14, height: 1.4),
          ),
        ],
      ),
    ),
  );
}

class _SampleStore {
  const _SampleStore(this.name, this.category, this.image);
  final String name;
  final String category;
  final String image;
}

class _StoreCard extends StatelessWidget {
  const _StoreCard({required this.store, required this.onTap});

  final _SampleStore store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: SizedBox(
      width: 148,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              '$_assetRoot/${store.image}',
              width: 148,
              height: 148,
              fit: BoxFit.cover,
              cacheWidth: (148 * MediaQuery.devicePixelRatioOf(context)).ceil(),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            store.category,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            store.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 2),
          const Text(
            'Przykład',
            style: TextStyle(
              color: _brown,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}

class _NoSearchResults extends StatelessWidget {
  const _NoSearchResults();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(16),
    child: Text('Brak pasujących przykładów.', style: TextStyle(color: _muted)),
  );
}

class _BottomTabs extends StatelessWidget {
  const _BottomTabs({
    required this.onOpenWorkspace,
    required this.onNotifications,
  });

  final VoidCallback onOpenWorkspace;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) => Container(
    height: 44,
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: Color(0x1A000000), width: 0.5)),
    ),
    child: Row(
      children: [
        _tab('home.svg', 'Strona główna', () {}),
        _tab('cart.svg', 'Paragony', onOpenWorkspace),
        _tab('bell.svg', 'Powiadomienia', onNotifications),
        _tab('person.svg', 'Znajomi i ustawienia', onOpenWorkspace),
      ],
    ),
  );

  Widget _tab(String asset, String tooltip, VoidCallback onPressed) => Expanded(
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: SvgPicture.asset('$_assetRoot/$asset', width: 24, height: 24),
    ),
  );
}
