/// Price and date formatting shared by every screen, so amounts look the
/// same everywhere (e.g. "1,89,999" with Indian digit grouping).
library;

/// Whole-rupee amount with Indian digit grouping, no currency symbol:
/// 1899 -> "1,899", 189999 -> "1,89,999".
String formatInr(num amount) {
  final int rounded = amount.round();
  return '${rounded < 0 ? '-' : ''}${_groupIndian(rounded.abs().toString())}';
}

/// Amount with its currency: "₹1,899" for rupees (paise shown only when
/// there are any, e.g. "₹85.71"), otherwise "USD 12.50".
String formatMoney(num amount, String currencyCode) {
  if (currencyCode != 'INR') {
    return '$currencyCode ${amount.toStringAsFixed(2)}';
  }
  final bool whole = (amount * 100).round() % 100 == 0;
  if (whole) return '₹${formatInr(amount)}';
  final fixed = amount.abs().toStringAsFixed(2);
  final dot = fixed.indexOf('.');
  return '₹${amount < 0 ? '-' : ''}'
      '${_groupIndian(fixed.substring(0, dot))}${fixed.substring(dot)}';
}

String _groupIndian(String digits) {
  if (digits.length <= 3) return digits;
  final lastThree = digits.substring(digits.length - 3);
  final rest = digits
      .substring(0, digits.length - 3)
      .replaceAllMapped(RegExp(r'\B(?=(\d{2})+(?!\d))'), (_) => ',');
  return '$rest,$lastThree';
}
