import 'package:flutter/material.dart';
import 'package:rookies_jeans/constants/app_ui.dart';

/// The website's announcement bar: its messages scrolling right to left on
/// a black strip. Keep [messages] in step with the theme's announcement bar,
/// which lives in the theme settings and can't be read from the Storefront
/// API.
class AnnouncementTicker extends StatefulWidget {
  const AnnouncementTicker({super.key});

  static const List<String> messages = [
    'SIGN UP AND GET ₹100 OFF YOUR FIRST ORDER',
    'FREE SHIPPING ON ALL PREPAID ORDERS',
    'CASH ON DELIVERY AVAILABLE',
    'EASY 7-DAY RETURNS',
    'ESTD. 2009',
    'AVAILABLE IN 500+ OUTLETS ACROSS INDIA',
    'RATED 4.5✰, TRUSTED BY OVER 100,000+ CUSTOMERS',
  ];

  static const double height = 28;

  /// Space on each side of a message.
  static const double _gap = 20;
  static const double _pixelsPerSecond = 40;
  static const TextStyle _style = TextStyle(
    fontFamily: AppFonts.accent,
    fontSize: 10.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
    color: Colors.white,
  );

  @override
  State<AnnouncementTicker> createState() => _AnnouncementTickerState();
}

class _AnnouncementTickerState extends State<AnnouncementTicker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  List<double> _itemWidths = const [];
  double _loopWidth = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final widths = [
      for (final message in AnnouncementTicker.messages)
        _textWidth(message, scaler, direction) + AnnouncementTicker._gap * 2,
    ];
    _itemWidths = widths;
    _loopWidth = widths.fold(0, (sum, w) => sum + w);

    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      return;
    }
    final seconds = _loopWidth / AnnouncementTicker._pixelsPerSecond;
    _controller.repeat(
      period: Duration(milliseconds: (seconds * 1000).round()),
    );
  }

  double _textWidth(String text, TextScaler scaler, TextDirection direction) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: AnnouncementTicker._style),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = painter.width.ceilToDouble();
    painter.dispose();
    return width;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Enough copies that the strip stays full as the first one scrolls away.
    final screenWidth = MediaQuery.sizeOf(context).width;
    final copies = (screenWidth / _loopWidth).ceil() + 1;

    return Semantics(
      label: AnnouncementTicker.messages.join('. '),
      child: ExcludeSemantics(
        child: Container(
          height: AnnouncementTicker.height,
          color: Colors.black,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (_, child) => Transform.translate(
                offset: Offset(-_controller.value * _loopWidth, 0),
                child: child,
              ),
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: 0,
                maxWidth: double.infinity,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var copy = 0; copy < copies; copy++)
                      for (var i = 0; i < _itemWidths.length; i++)
                        SizedBox(
                          width: _itemWidths[i],
                          child: Text(
                            AnnouncementTicker.messages[i],
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            softWrap: false,
                            style: AnnouncementTicker._style,
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
