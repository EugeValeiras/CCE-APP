import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TileSize { small, medium, large }

extension TileSizeX on TileSize {
  double get tileHeight {
    switch (this) {
      case TileSize.small: return 140;
      case TileSize.medium: return 180;
      case TileSize.large: return 220;
    }
  }

  double get sensorTileHeight {
    switch (this) {
      case TileSize.small: return 130;
      case TileSize.medium: return 160;
      case TileSize.large: return 190;
    }
  }

  double get iconSize {
    switch (this) {
      case TileSize.small: return 28;
      case TileSize.medium: return 40;
      case TileSize.large: return 52;
    }
  }

  double get nameSize {
    switch (this) {
      case TileSize.small: return 14;
      case TileSize.medium: return 16;
      case TileSize.large: return 19;
    }
  }

  double get stateSize {
    switch (this) {
      case TileSize.small: return 13;
      case TileSize.medium: return 15;
      case TileSize.large: return 18;
    }
  }

  double get maxTileExtent {
    switch (this) {
      case TileSize.small: return 200;
      case TileSize.medium: return 260;
      case TileSize.large: return 320;
    }
  }

  double get floorPlanDotSize {
    switch (this) {
      case TileSize.small: return 44;
      case TileSize.medium: return 56;
      case TileSize.large: return 68;
    }
  }

  String get label {
    switch (this) {
      case TileSize.small: return 'Compacto';
      case TileSize.medium: return 'Normal';
      case TileSize.large: return 'Grande';
    }
  }
}

class UiSettingsService extends ChangeNotifier {
  static const _keyTileSize = 'ui.tileSize';
  TileSize _tileSize = TileSize.medium;

  TileSize get tileSize => _tileSize;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyTileSize);
      if (raw != null) {
        _tileSize = TileSize.values.firstWhere(
          (t) => t.name == raw,
          orElse: () => TileSize.medium,
        );
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> cycle() async {
    final next = TileSize.values[(_tileSize.index + 1) % TileSize.values.length];
    _tileSize = next;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyTileSize, next.name);
    } catch (_) {}
  }
}
