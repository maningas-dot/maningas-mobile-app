String formatPhilippinePeso(double? price) {
  if (price == null || !price.isFinite) return 'Price unavailable';

  final fixedPrice = price.abs().toStringAsFixed(2);
  final decimalIndex = fixedPrice.indexOf('.');
  final integerPart = fixedPrice.substring(0, decimalIndex);
  final groupedInteger = integerPart.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final sign = price < 0 ? '-' : '';
  return '₱$sign$groupedInteger${fixedPrice.substring(decimalIndex)}';
}
