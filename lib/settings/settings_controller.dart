import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../catalog/catalog_db.dart';
import 'app_settings.dart';

/// Holds the current [AppSettings] and persists changes.
class SettingsController extends ChangeNotifier {
  /// Loads the saved settings from [_db]; unreadable data gives the defaults.
  SettingsController(this._db)
    : _value = AppSettings.fromJson(_db.loadSettings());

  final CatalogDb _db;
  AppSettings _value;

  /// The current settings.
  AppSettings get value => _value;

  /// Saves [next] and notifies listeners; does nothing when it equals the
  /// current settings.
  void update(AppSettings next) {
    if (jsonEncode(next.toJson()) == jsonEncode(_value.toJson())) return;
    _value = next;
    _db.saveSettings(next.toJson());
    notifyListeners();
  }

  /// Reads the settings again from the database (after a sync changed them
  /// underneath) and notifies listeners only if they differ.
  void reload() {
    final loaded = AppSettings.fromJson(_db.loadSettings());
    if (jsonEncode(loaded.toJson()) == jsonEncode(_value.toJson())) return;
    _value = loaded;
    notifyListeners();
  }
}
