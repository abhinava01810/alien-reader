import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the user's Gemini key lives. Abstracted so tests need no plugin.
abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureSecretStore implements SecretStore {
  SecureSecretStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// The "Process on phone" switch and the user-supplied Gemini key.
///
/// The key is only ever kept in encrypted secure storage on this phone. It is
/// never logged, never put in a URL, and never sent anywhere except to
/// Google's Gemini API in a request header.
class PhoneProcessingSettings {
  PhoneProcessingSettings({SecretStore? secrets})
    : _secrets = secrets ?? SecureSecretStore();

  final SecretStore _secrets;

  static const String _enabledKey = 'process_on_phone_enabled';
  static const String _geminiKey = 'gemini_api_key';

  /// Off unless the user has turned it on.
  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  Future<String?> geminiKey() async {
    final key = (await _secrets.read(_geminiKey))?.trim();
    return (key == null || key.isEmpty) ? null : key;
  }

  Future<bool> hasGeminiKey() async => (await geminiKey()) != null;

  Future<void> saveGeminiKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      await _secrets.delete(_geminiKey);
    } else {
      await _secrets.write(_geminiKey, trimmed);
    }
  }

  Future<void> clearGeminiKey() => _secrets.delete(_geminiKey);

  /// True when app captures should use the on-phone path: switched on and a
  /// key is available.
  Future<bool> isReady() async => (await readyKey()) != null;

  /// The key to use for this capture, or null when captures should keep
  /// using the Pi (switch off, or no key saved).
  Future<String?> readyKey() async =>
      await isEnabled() ? await geminiKey() : null;

  /// "••••1234" for display; never the full key.
  static String mask(String key) {
    final tail = key.length <= 4 ? key : key.substring(key.length - 4);
    return '••••$tail';
  }
}
