import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:projekt_paragon/dashboard_page.dart';

void main() {
  testWidgets('Dashboard shows honest balances and Figma asset geometry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var openedWorkspace = false;
    await tester.pumpWidget(
      MaterialApp(
        home: DashboardPage(onOpenWorkspace: () => openedWorkspace = true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Jesteś dłużny:'), findsOneWidget);
    expect(find.text('Inni są Ci winni:'), findsOneWidget);
    expect(find.text('— zł'), findsNWidgets(2));
    expect(find.text('15,67 zł'), findsNothing);
    expect(find.byType(SvgPicture), findsWidgets);

    for (final (name, size) in [
      ('skyr.png', const Size(76, 76)),
      ('banana.png', const Size(76, 76)),
      ('granola.png', const Size(76, 76)),
      ('hummus.png', const Size(76, 76)),
      ('biedronka.png', const Size(148, 148)),
      ('action.png', const Size(148, 148)),
      ('lidl.png', const Size(148, 148)),
    ]) {
      final asset = find.byWidgetPredicate((widget) {
        if (widget is! Image) return false;
        final provider = widget.image is ResizeImage
            ? (widget.image as ResizeImage).imageProvider
            : widget.image;
        return provider is AssetImage && provider.assetName.endsWith(name);
      });
      expect(asset, findsOneWidget, reason: name);
      expect(tester.getSize(asset), size, reason: name);
    }
    for (final (name, size) in [
      ('search.svg', const Size(24, 24)),
      ('favorite.svg', const Size(18, 18)),
      ('history.svg', const Size(18, 18)),
      ('following.svg', const Size(18, 18)),
      ('order.svg', const Size(18, 18)),
      ('chevron.svg', const Size(20, 20)),
      ('section_chevron.svg', const Size(20, 20)),
      ('home.svg', const Size(24, 24)),
      ('cart.svg', const Size(24, 24)),
      ('bell.svg', const Size(24, 24)),
      ('person.svg', const Size(24, 24)),
    ]) {
      final asset = find.byWidgetPredicate(
        (widget) =>
            widget is SvgPicture &&
            widget.bytesLoader is SvgAssetLoader &&
            (widget.bytesLoader as SvgAssetLoader).assetName ==
                'assets/dashboard/$name',
      );
      expect(asset, findsOneWidget, reason: name);
      expect(tester.getSize(asset), size, reason: name);
    }
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Paragony'));
    expect(openedWorkspace, isTrue);
  });

  testWidgets('Dashboard search filters examples on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: DashboardPage(onOpenWorkspace: () {})),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextField), 'banan');
    await tester.pumpAndSettle();
    expect(find.text('Banan luz'), findsOneWidget);
    expect(find.text('Skyr Piątnica'), findsNothing);
    expect(find.text('Brak pasujących przykładów.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Store section stays close to bottom tabs on a tall phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: DashboardPage(onOpenWorkspace: () {})),
    );
    await tester.pumpAndSettle();

    final storeName = tester.getRect(find.text('Biedronka'));
    final tabs = tester.getRect(find.byTooltip('Paragony'));
    expect(tabs.top - storeName.bottom, lessThan(60));
    expect(
      tester.getRect(find.text('Miejsca, w których kupujesz')).top,
      greaterThanOrEqualTo(
        tester.getRect(find.text('Granola One Day More')).bottom,
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
