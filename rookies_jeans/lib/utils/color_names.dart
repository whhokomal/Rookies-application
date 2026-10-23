/// Display colors for apparel color names, used for swatches when a product
/// (each Variant King color is its own product) has no Shopify swatch set.
library;

import 'package:flutter/material.dart';

/// Maps common apparel color words to a display hex code. Keys are
/// lowercase; compounds (e.g. "light brown") are matched first, falling
/// back to the base hue word alone. Extend this as new color names show
/// up in the catalog.
const Map<String, String> _namedColorHex = {
  // compounds — checked before single words
  'light brown': 'B08968',
  'dark brown': '4A2C17',
  'light blue': 'A9C6E8',
  'dark blue': '1B3A6B',
  'light green': '9CC69B',
  'dark green': '234D35',
  'military green': '4B5320',
  'light grey': 'C9C9C9',
  'light gray': 'C9C9C9',
  'dark grey': '4B4B4B',
  'dark gray': '4B4B4B',
  'off white': 'F5F1E8',
  'navy blue': '000080',
  'sky blue': '87CEEB',
  'royal blue': '2551A6',
  'baby pink': 'F7C9D6',
  'hot pink': 'F0508A',
  'dark red': '8B1E1E',
  'light khaki': 'D9C9A3',
  'light olive': '9A9F6A',
  'light moss': '8A9A5B',
  'dark charcoal': '2B2F33',
  // single words
  'white': 'FFFFFF',
  'black': '000000',
  'grey': '808080',
  'gray': '808080',
  'charcoal': '36454F',
  'navy': '000080',
  'blue': '2A4B7C',
  'skyblue': '87CEEB',
  'red': 'C1272D',
  'maroon': '800000',
  'wine': '722F37',
  'burgundy': '800020',
  'green': '2E5339',
  'olive': '708238',
  'moss': '6B7A3A',
  'khaki': 'C3B091',
  'beige': 'D8C4A0',
  'cream': 'FFFDD0',
  'ivory': 'FFFFF0',
  'brown': '5B3A29',
  'tan': 'D2B48C',
  'clay': 'B66A50',
  'mustard': 'E1AD01',
  'yellow': 'F2D51D',
  'orange': 'E2711D',
  'rust': 'B7410E',
  'pink': 'F6A6C1',
  'purple': '6A3FA0',
  'lavender': 'B497D6',
  'teal': '2F6D6D',
  'mint': 'A8E0C5',
  'coral': 'FF6F5E',
  'turquoise': '30D5C8',
  'gold': 'D4AF37',
  'silver': 'C0C0C0',
  'denim': '4A6D8C',
  'indigo': '3F3B6C',
};

/// Parses "#RRGGBB" / "RRGGBB" / "AARRGGBB"; null if it isn't a color.
Color? hexToColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  var h = hex.replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  final value = int.tryParse(h, radix: 16);
  return value != null ? Color(value) : null;
}

/// Resolves a display color from free-text like an option value
/// ("Light Brown") or a handle segment. Tries the full normalized string,
/// then each word from the end backwards (the last word is usually the
/// base hue, e.g. "dusty rose" -> "rose"). Returns null if nothing in
/// [_namedColorHex] matches.
Color? colorFromName(String name) {
  final normalized =
      name.toLowerCase().trim().replaceAll(RegExp(r'[_\-]+'), ' ');
  if (_namedColorHex.containsKey(normalized)) {
    return hexToColor(_namedColorHex[normalized]);
  }
  final words =
      normalized.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  for (final w in words.reversed) {
    if (_namedColorHex.containsKey(w)) {
      return hexToColor(_namedColorHex[w]);
    }
  }
  return null;
}

/// Pulls a display color out of a Variant King child product's handle
/// (e.g. "light-brown-extra-loose-fit-jeans-2233") by trying the first
/// two hyphen-separated tokens as a compound color name, then the first
/// token alone, then the base hue of the compound ("light-moss" -> "moss").
Color? colorFromHandle(String handle) {
  final tokens = handle.toLowerCase().split('-');
  if (tokens.length >= 2) {
    final hex = _namedColorHex['${tokens[0]} ${tokens[1]}'];
    if (hex != null) return hexToColor(hex);
  }
  if (tokens.isNotEmpty) {
    final hex = _namedColorHex[tokens.first];
    if (hex != null) return hexToColor(hex);
  }
  if (tokens.length >= 2) {
    final hex = _namedColorHex[tokens[1]];
    if (hex != null) return hexToColor(hex);
  }
  return null;
}
