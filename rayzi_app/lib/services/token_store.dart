import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Central token store.
///
/// Auth tokens are secrets: they live in the platform keystore/keychain via
/// [FlutterSecureStorage] (EncryptedSharedPreferences / Keychain). Any legacy
/// plaintext copy in SharedPreferences is migrated once and deleted.
class TokenStore {
  static const _key = 'access_token';
  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Future<void> save(String token) async {
    await _secure.write(key: _key, value: token);
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_key) != null) {
      await prefs.remove(_key);
    }
  }

  /// Returns the stored token, migrating from the old plaintext location
  /// if one exists.
  static Future<String?> read() async {
    String? token = await _secure.read(key: _key);
    if (token != null && token.isNotEmpty) return token;

    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString(_key);
    if (token != null && token.isNotEmpty) {
      await _secure.write(key: _key, value: token);
      await prefs.remove(_key);
    }
    return token;
  }

  static Future<void> clear() async {
    await _secure.delete(key: _key);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
