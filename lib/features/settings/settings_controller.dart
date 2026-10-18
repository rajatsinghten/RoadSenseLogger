/// Settings state for the UI (Riverpod StateNotifier over [SettingsStore]).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roadsense_logger/data/settings/settings_store.dart';
import 'package:roadsense_logger/domain/models/session_config.dart';

class SettingsController extends StateNotifier<SessionSettings> {
  SettingsController(this._store) : super(const SessionSettings()) {
    _load();
  }

  final SettingsStore _store;

  Future<void> _load() async {
    state = await _store.loadSettings();
  }

  Future<void> update(SessionSettings settings) async {
    state = settings;
    await _store.saveSettings(settings);
  }

  Future<SessionConfig?> loadLastConfig() => _store.loadLastConfig();

  Future<void> saveLastConfig(SessionConfig config) =>
      _store.saveLastConfig(config);
}
