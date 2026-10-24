import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:rookies_jeans/constants/app_ui.dart';

double _s(BuildContext c, double base) =>
    Responsive.of(c, baseW: 375).s(base);

/// Renders the simple HTML Shopify's rich-text editors produce (policies,
/// pages) as native text: paragraphs, headings, bold/italic, line breaks,
/// bullet and numbered lists, and links. Inline styles, classes and any
/// other tags are ignored, so it follows the app's fonts and theme.
class HtmlContent extends StatefulWidget {
  const HtmlContent({super.key, required this.html});

  final String html;

  @override
  State<HtmlContent> createState() => _HtmlContentState();
}

class _HtmlContentState extends State<HtmlContent> {
  List<_Block> _blocks = const [];
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(HtmlContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html) _parse();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  void _parse() {
    _disposeRecognizers();
    _blocks = _HtmlParser(onLink: (href) {
      final r = TapGestureRecognizer()..onTap = () => _openLink(href);
      _recognizers.add(r);
      return r;
    }).parse(widget.html);
  }

  static Future<void> _openLink(String href) async {
    // The editor leaves stray (encoded) spaces in links, e.g.
    // "mailto:%20%20care@…%20" or "tel:%20+91…".
    final uri = Uri.tryParse(href.replaceAll(RegExp(r'%20|\s'), ''));
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    // As on the website: plain text in grey, bold text in the full text
    // colour so the highlighted sentences stand out.
    final body = TextStyle(
      fontFamily: AppFonts.body,
      fontSize: _s(context, 14).clamp(13.0, 18.0),
      height: 1.55,
      color: AppColors.secondaryText,
    );
    final heading = body.copyWith(
      fontSize: _s(context, 16).clamp(15.0, 21.0),
      fontWeight: FontWeight.w700,
      height: 1.3,
      color: AppColors.primary,
    );

    final children = <Widget>[];
    for (var i = 0; i < _blocks.length; i++) {
      final block = _blocks[i];
      final prev = i > 0 ? _blocks[i - 1] : null;
      final isHeading = block.heading || block.isBoldTitle;
      final gap = prev == null
          ? 0.0
          : isHeading
              ? 28.0
              : block.marker != null && prev.marker != null
                  ? 6.0
                  : 12.0;
      final text = Text.rich(
        TextSpan(
          style: isHeading ? heading : body,
          children: [
            for (final run in block.runs)
              TextSpan(
                text: run.text,
                recognizer: run.recognizer,
                style: TextStyle(
                  color: run.recognizer != null
                      ? AppColors.accentOrange
                      : run.color == _themeColor
                          ? AppColors.primary
                          : run.color ??
                              (run.bold ? AppColors.primary : null),
                  fontWeight: run.bold ? FontWeight.w700 : null,
                  fontStyle: run.italic ? FontStyle.italic : null,
                  decoration:
                      run.recognizer != null ? TextDecoration.underline : null,
                ),
              ),
          ],
        ),
      );

      children.add(Padding(
        padding: EdgeInsets.only(
          top: _s(context, gap),
          left: _s(context, 16) * (block.depth > 0 ? block.depth - 1 : 0),
        ),
        child: block.marker == null
            ? text
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: _s(context, 22),
                    child: Text(block.marker!, style: body),
                  ),
                  Expanded(child: text),
                ],
              ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _Run {
  _Run(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.color,
    this.recognizer,
  });
  String text;
  final bool bold;
  final bool italic;

  /// An inline `color` from the editor (e.g. red), else null.
  final Color? color;
  final TapGestureRecognizer? recognizer;
}

class _Block {
  _Block(this.runs, {this.heading = false, this.marker, this.depth = 0});
  final List<_Run> runs;
  final bool heading;

  /// "•" or "3." for a list item, else null.
  final String? marker;

  /// How many lists this block sits in (for indentation).
  final int depth;

  /// A short line that is all bold (e.g. "Online Store Terms"): the policy
  /// editor's way of writing a section heading.
  bool get isBoldTitle {
    if (marker != null || runs.any((r) => !r.bold)) return false;
    final text = runs.map((r) => r.text).join();
    return text.length <= 60 && !text.contains('\n');
  }
}

/// Stands for an inline black/grey: shown in [AppColors.primary].
const Color _themeColor = Color(0x00000000);

class _ListState {
  _ListState(this.ordered);
  final bool ordered;
  int count = 0;
}

class _HtmlParser {
  _HtmlParser({required this.onLink});

  final TapGestureRecognizer Function(String href) onLink;

  final List<_Block> _blocks = [];
  List<_Run> _runs = [];
  bool _heading = false;
  String? _marker;
  int _bold = 0;
  int _italic = 0;
  final List<String?> _links = [];
  final List<_ListState> _lists = [];

  /// Open tags with the inline colour each set (null = none).
  final List<(String, Color?)> _colors = [];

  static final RegExp _token = RegExp(
    r'<!--[\s\S]*?-->|<(/?)([a-zA-Z][a-zA-Z0-9]*)([^>]*)>|([^<]+)',
  );
  static final RegExp _href = RegExp(r'''href\s*=\s*["']([^"']*)["']''');
  static final RegExp _styleColor = RegExp(
    r'''(?:^|[;"'\s])color\s*:\s*([^;"']+)''',
    caseSensitive: false,
  );
  static const Set<String> _voidTags = {'br', 'hr', 'img', 'input', 'meta'};
  static const Set<String> _blockTags = {
    'p', 'div', 'section', 'article', 'blockquote', 'table', 'tr',
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  };

  List<_Block> parse(String html) {
    final clean = html.replaceAll(
      RegExp(r'<(script|style)\b[\s\S]*?</\1\s*>', caseSensitive: false),
      '',
    );

    for (final m in _token.allMatches(clean)) {
      final text = m.group(4);
      if (text != null) {
        _addText(_decode(text).replaceAll(RegExp(r'\s+'), ' '));
        continue;
      }
      final tag = m.group(2)?.toLowerCase();
      if (tag == null) continue; // comment
      final closing = m.group(1) == '/';

      if (!_voidTags.contains(tag)) {
        if (closing) {
          final i = _colors.lastIndexWhere((c) => c.$1 == tag);
          if (i >= 0) _colors.removeRange(i, _colors.length);
        } else {
          final css = _styleColor.firstMatch(m.group(3) ?? '')?.group(1);
          _colors.add((tag, css == null ? null : _parseColor(css)));
        }
      }

      if (tag == 'br') {
        _addText('\n');
      } else if (tag == 'b' || tag == 'strong') {
        _bold += closing ? -1 : 1;
      } else if (tag == 'i' || tag == 'em') {
        _italic += closing ? -1 : 1;
      } else if (tag == 'a') {
        if (closing) {
          if (_links.isNotEmpty) _links.removeLast();
        } else {
          _links.add(_href.firstMatch(m.group(3) ?? '')?.group(1));
        }
      } else if (tag == 'ul' || tag == 'ol') {
        _flush();
        _marker = null;
        if (closing) {
          if (_lists.isNotEmpty) _lists.removeLast();
        } else {
          _lists.add(_ListState(tag == 'ol'));
        }
      } else if (tag == 'li') {
        _flush();
        _marker = null;
        if (!closing && _lists.isNotEmpty) {
          final list = _lists.last;
          list.count++;
          _marker = list.ordered ? '${list.count}.' : '•';
        }
      } else if (_blockTags.contains(tag)) {
        _flush();
        if (closing) _heading = false;
        if (!closing && tag.length == 2 && tag.startsWith('h')) {
          _heading = true;
        }
      }
    }
    _flush();
    return _blocks;
  }

  void _addText(String text) {
    if (text.isEmpty) return;
    // Collapse whitespace across tags, as a browser would.
    if (text.startsWith(' ')) {
      final last = _runs.isEmpty ? '' : _runs.last.text;
      if (last.isEmpty || last.endsWith(' ') || last.endsWith('\n')) {
        text = text.substring(1);
        if (text.isEmpty) return;
      }
    }
    final href = _links.isEmpty ? null : _links.last;
    _runs.add(_Run(
      text,
      bold: _bold > 0,
      italic: _italic > 0,
      color: _colors.reversed
          .map((c) => c.$2)
          .firstWhere((c) => c != null, orElse: () => null),
      recognizer: href == null || href.isEmpty ? null : onLink(href),
    ));
  }

  void _flush() {
    final runs = _runs;
    while (runs.isNotEmpty && runs.first.text.trim().isEmpty) {
      runs.removeAt(0);
    }
    while (runs.isNotEmpty && runs.last.text.trim().isEmpty) {
      runs.removeLast();
    }
    // Nothing written yet (e.g. the <p> in "<li><p>…"): keep the pending
    // list marker / heading for the text that follows.
    if (runs.isEmpty) return;
    runs.first.text = runs.first.text.trimLeft();
    runs.last.text = runs.last.text.trimRight();
    _blocks.add(_Block(
      runs,
      heading: _heading,
      marker: _marker,
      depth: _lists.length,
    ));
    _runs = [];
    _heading = false;
    _marker = null;
  }

  static const Map<String, int> _namedColors = {
    'red': 0xFFFF0000, 'blue': 0xFF0000FF, 'green': 0xFF008000,
    'orange': 0xFFFFA500, 'purple': 0xFF800080, 'brown': 0xFFA52A2A,
    'crimson': 0xFFDC143C, 'darkred': 0xFF8B0000, 'navy': 0xFF000080,
  };

  /// A CSS colour (name, #rgb, #rrggbb, rgb()). Black, white and greys
  /// become [_themeColor], so the text follows the light/dark theme but
  /// still overrides an outer colour (e.g. black lines inside a red span).
  static Color? _parseColor(String css) {
    final v = css.trim().toLowerCase();
    Color? color;
    final named = _namedColors[v];
    if (named != null) {
      color = Color(named);
    } else if (v.startsWith('#')) {
      var hex = v.substring(1);
      if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
      final n = hex.length == 6 ? int.tryParse(hex, radix: 16) : null;
      if (n != null) color = Color(0xFF000000 | n);
    } else {
      final rgb = RegExp(r'rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)')
          .firstMatch(v);
      if (rgb != null) {
        color = Color.fromARGB(255, int.parse(rgb.group(1)!),
            int.parse(rgb.group(2)!), int.parse(rgb.group(3)!));
      }
    }
    if (color == null) return null;
    return HSLColor.fromColor(color).saturation < 0.25 ? _themeColor : color;
  }

  static const Map<String, String> _entities = {
    'nbsp': ' ', 'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"',
    'apos': "'", 'rsquo': '’', 'lsquo': '‘', 'rdquo': '”', 'ldquo': '“',
    'ndash': '–', 'mdash': '—', 'hellip': '…', 'bull': '•', 'copy': '©',
    'reg': '®', 'trade': '™', 'rupee': '₹',
  };

  static String _decode(String s) => s.replaceAllMapped(
        RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);'),
        (m) {
          final e = m.group(1)!;
          if (e.startsWith('#')) {
            final code = e.startsWith('#x')
                ? int.tryParse(e.substring(2), radix: 16)
                : int.tryParse(e.substring(1));
            return code == null ? m.group(0)! : String.fromCharCode(code);
          }
          return _entities[e.toLowerCase()] ?? m.group(0)!;
        },
      );
}
