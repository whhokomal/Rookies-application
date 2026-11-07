import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rookies_jeans/widgets/announcement_ticker.dart';
import 'package:rookies_jeans/widgets/trust_strip.dart';

void main() {
  Future<void> pumpOnPhone(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  }

  testWidgets('TrustStrip matches the website\'s four badges', (tester) async {
    await pumpOnPhone(
      tester,
      const Padding(padding: EdgeInsets.all(16), child: TrustStrip()),
    );

    for (final text in [
      'Free Delivery',
      '7-Day Returns',
      'Cash on Delivery',
      'Secure Payments',
      'UPI, cards & net banking',
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('AnnouncementTicker scrolls without overflowing', (tester) async {
    await pumpOnPhone(tester, const AnnouncementTicker());

    final text = find.text(AnnouncementTicker.messages.first).first;
    final start = tester.getTopLeft(text).dx;
    await tester.pump(const Duration(seconds: 1));

    expect(tester.getTopLeft(text).dx, lessThan(start));
    expect(tester.takeException(), isNull);
  });
}
