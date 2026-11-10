/// Decimal arithmetic for the receipt form. Values are kept in cents and
/// millionths of a unit, so warnings never depend on floating-point rounding.
BigInt? parseMoneyCents(String input) {
  final value = input.trim();
  if (!RegExp(r'^\d{1,12}(?:[.,]\d{1,2})?$').hasMatch(value)) return null;
  final parts = value.replaceAll(',', '.').split('.');
  return BigInt.parse(parts[0]) * BigInt.from(100) +
      BigInt.parse(parts.length == 1 ? '0' : parts[1].padRight(2, '0'));
}

BigInt? parseQuantityMicros(String input) {
  final value = input.trim();
  if (!RegExp(r'^\d{1,12}(?:[.,]\d{1,6})?$').hasMatch(value)) return null;
  final parts = value.replaceAll(',', '.').split('.');
  if (parts[0].length + (parts.length == 1 ? 0 : parts[1].length) > 14) {
    return null;
  }
  final result =
      BigInt.parse(parts[0]) * BigInt.from(1000000) +
      BigInt.parse(parts.length == 1 ? '0' : parts[1].padRight(6, '0'));
  return result > BigInt.zero ? result : null;
}

String moneyForApi(BigInt cents) =>
    '${cents ~/ BigInt.from(100)}.${(cents % BigInt.from(100)).toString().padLeft(2, '0')}';

String moneyForDisplay(BigInt cents) => moneyForApi(cents).replaceAll('.', ',');

BigInt expectedAmountCents(BigInt quantityMicros, BigInt unitPriceCents) =>
    (quantityMicros * unitPriceCents + BigInt.from(500000)) ~/
    BigInt.from(1000000);
