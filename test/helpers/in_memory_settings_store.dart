import 'package:roadsense_logger/data/settings/settings_store.dart';
import 'package:roadsense_logger/domain/models/session_config.dart';

/// In-memory [SettingsStore] for tests (no plugin channels).
class InMemorySettingsStore implements SettingsStore {
  SessionSettings settings = const SessionSettings();
  SessionConfig? lastConfig;

  @override
  Future<SessionSettings> loadSettings() async => settings;

  @override
  Future<void> saveSettings(SessionSettings settings) async {
    this.settings = settings;
  }

  @override
  Future<SessionConfig?> loadLastConfig() async => lastConfig;

  @override
  Future<void> saveLastConfig(SessionConfig config) async {
    lastConfig = config;
  }
}
