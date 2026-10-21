import 'package:flutter_test/flutter_test.dart';
import 'package:rookies_jeans/utils/format.dart';

void main() {
  test('formatInr uses Indian digit grouping', () {
    expect(formatInr(0), '0');
    expect(formatInr(999), '999');
    expect(formatInr(1899), '1,899');
    expect(formatInr(189999), '1,89,999');
    expect(formatInr(12345678), '1,23,45,678');
    expect(formatInr(1899.6), '1,900');
    expect(formatInr(-2500), '-2,500');
  });

  test('formatMoney shows paise only when there are any', () {
    expect(formatMoney(1899, 'INR'), '₹1,899');
    expect(formatMoney(1899.0, 'INR'), '₹1,899');
    expect(formatMoney(85.71, 'INR'), '₹85.71');
    expect(formatMoney(123456.5, 'INR'), '₹1,23,456.50');
    expect(formatMoney(12.5, 'USD'), 'USD 12.50');
  });
}
