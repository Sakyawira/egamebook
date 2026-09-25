import 'dart:convert';
import 'dart:io';

import 'package:nocterm/nocterm.dart';

class EdgeheadTheme {
  EdgeheadTheme._(this._colors);

  static final Map<String, Color> _defaults = {
    'story': Colors.blue,
    'status': Colors.cyan,
    'illustration': Colors.brightGreen,
    'music': Colors.brightCyan,
    'choices': Colors.yellow,
    'roll': Colors.yellow,
    'title': Colors.brightCyan,
    'text': Colors.white,
    'muted': Colors.brightBlack,
    'selected': Colors.brightYellow,
    'error': Colors.brightRed,
    'warning': Colors.brightYellow,
    'spectrumHigh': Colors.brightCyan,
    'spectrumLow': Colors.brightGreen,
  };

  final Map<String, Color> _colors;

  Color operator [](String name) => _colors[name]!;

  factory EdgeheadTheme.load(File file) {
    final colors = Map<String, Color>.from(_defaults);
    final Object? data = jsonDecode(file.readAsStringSync());
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Theme must be a JSON object');
    }
    for (final entry in data.entries) {
      if (!colors.containsKey(entry.key)) {
        throw FormatException('Unknown theme color: ${entry.key}');
      }
      final value = entry.value;
      if (value is! String || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
        throw FormatException('Use #RRGGBB for ${entry.key}');
      }
      colors[entry.key] = Color(int.parse(value.substring(1), radix: 16));
    }
    return EdgeheadTheme._(colors);
  }
}
