import 'package:flutter/material.dart';

class ColorPreset {
  final String name;
  final int hue;
  final int sat;
  final String colorHex;

  ColorPreset({required this.name, required this.hue, required this.sat, required this.colorHex});

  factory ColorPreset.fromJson(Map<String, dynamic> json) {
    return ColorPreset(
      name: (json['name'] ?? '').toString(),
      hue: (json['hue'] as num?)?.toInt() ?? 0,
      sat: (json['sat'] as num?)?.toInt() ?? 254,
      colorHex: (json['color'] ?? '#ffffff').toString(),
    );
  }

  Color get color {
    final hex = colorHex.replaceFirst('#', '');
    if (hex.length == 6) {
      return Color(int.parse('FF$hex', radix: 16));
    }
    return Colors.white;
  }
}
