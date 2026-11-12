import 'receipt_math.dart';

class SettlementPreview {
  const SettlementPreview({
    required this.totals,
    required this.unassignedCents,
    required this.computedTotalCents,
    required this.complete,
  });

  final Map<int, BigInt> totals;
  final BigInt unassignedCents;
  final BigInt computedTotalCents;
  final bool complete;
}

BigInt netItemCents(Map<String, dynamic> item) {
  final amount = parseMoneyCents(item['amount']?.toString() ?? '');
  final discount = parseMoneyCents(item['discount']?.toString() ?? '0');
  if (amount == null || discount == null || discount > amount) {
    throw const FormatException('Nieprawidłowa kwota produktu.');
  }
  return amount - discount;
}

/// Mirrors the API: an item's amount after discount is shared equally;
/// remaining cents go to the lowest person IDs first.
SettlementPreview previewSettlement(
  List<Map<String, dynamic>> items,
  Map<int, Set<int>> assignments,
) {
  if (assignments.keys.any((index) => index < 0 || index >= items.length)) {
    throw const FormatException('Nieprawidłowy indeks produktu.');
  }
  final totals = <int, BigInt>{};
  var unassigned = BigInt.zero;
  var computed = BigInt.zero;
  var assignedCount = 0;
  for (var index = 0; index < items.length; index++) {
    final cents = netItemCents(items[index]);
    computed += cents;
    final ids = (assignments[index] ?? <int>{}).toList()..sort();
    if (ids.isEmpty) {
      unassigned += cents;
      continue;
    }
    assignedCount++;
    final share = cents ~/ BigInt.from(ids.length);
    final remainder = (cents % BigInt.from(ids.length)).toInt();
    for (var position = 0; position < ids.length; position++) {
      totals.update(
        ids[position],
        (old) =>
            old + share + (position < remainder ? BigInt.one : BigInt.zero),
        ifAbsent: () =>
            share + (position < remainder ? BigInt.one : BigInt.zero),
      );
    }
  }
  return SettlementPreview(
    totals: totals,
    unassignedCents: unassigned,
    computedTotalCents: computed,
    complete: items.isNotEmpty && assignedCount == items.length,
  );
}
