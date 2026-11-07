import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/app_config.dart';
import '../domain/auth_session.dart';

class AuthRepository {
  AuthRepository({
    http.Client? client,
    FlutterSecureStorage? secureStorage,
    this._preferences,
  }) : _client = client ?? http.Client(),
       _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _accessTokenKey = 'auth.access_token';
  static const _refreshTokenKey = 'auth.refresh_token';
  static const _accessExpiresAtKey = 'auth.access_expires_at';
  static const _deviceIdKey = 'auth.device_id';
  static const _usernameKey = 'auth.username';
  static const _firstNameKey = 'auth.first_name';
  static const _lastNameKey = 'auth.last_name';

  final http.Client _client;
  final FlutterSecureStorage _secureStorage;
  SharedPreferences? _preferences;

  Future<AuthSession> login({
    required String username,
    required String password,
    required String deviceId,
  }) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/api/auth/login'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': username.trim(),
              'password': password,
              'device_id': deviceId.trim(),
              'device_name': 'Facturacion Flutter',
            }),
          )
          .timeout(AppConfig.loginTimeout);
    } on TimeoutException {
      throw const AuthException(
        'El servidor no respondió a tiempo. Verifica tu conexión e intenta nuevamente.',
      );
    }

    final body = _decodeBody(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException(
        body['message'] as String? ?? 'No se pudo iniciar sesión.',
      );
    }

    final session = AuthSession.fromJson(body);
    await _saveSession(session);
    return session;
  }

  Future<AuthSession?> loadSession() async {
    final preferences = await _getPreferences();
    final accessToken = await _secureStorage.read(key: _accessTokenKey);
    final refreshToken = await _secureStorage.read(key: _refreshTokenKey);
    final expiresAt = preferences.getString(_accessExpiresAtKey);
    final deviceId = preferences.getString(_deviceIdKey);
    final username = preferences.getString(_usernameKey);

    if (accessToken == null ||
        refreshToken == null ||
        expiresAt == null ||
        deviceId == null ||
        username == null) {
      return null;
    }

    final parsedExpiry = DateTime.tryParse(expiresAt);
    if (parsedExpiry == null || parsedExpiry.isBefore(DateTime.now())) {
      await clearSession();
      return null;
    }

    return AuthSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      accessExpiresAt: parsedExpiry,
      deviceId: deviceId,
      username: username,
      firstName: preferences.getString(_firstNameKey) ?? '',
      lastName: preferences.getString(_lastNameKey) ?? '',
    );
  }

  Future<void> clearSession() async {
    await _secureStorage.delete(key: _accessTokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);
    final preferences = await _getPreferences();
    await preferences.remove(_accessExpiresAtKey);
    await preferences.remove(_deviceIdKey);
    await preferences.remove(_usernameKey);
    await preferences.remove(_firstNameKey);
    await preferences.remove(_lastNameKey);
  }

  Future<void> _saveSession(AuthSession session) async {
    await _secureStorage.write(
      key: _accessTokenKey,
      value: session.accessToken,
    );
    await _secureStorage.write(
      key: _refreshTokenKey,
      value: session.refreshToken,
    );
    final preferences = await _getPreferences();
    await preferences.setString(
      _accessExpiresAtKey,
      session.accessExpiresAt.toIso8601String(),
    );
    await preferences.setString(_deviceIdKey, session.deviceId);
    await preferences.setString(_usernameKey, session.username);
    await preferences.setString(_firstNameKey, session.firstName);
    await preferences.setString(_lastNameKey, session.lastName);
  }

  Future<SharedPreferences> _getPreferences() async {
    return _preferences ??= await SharedPreferences.getInstance();
  }

  Map<String, dynamic> _decodeBody(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // The response is handled as an API protocol error below.
    }
    throw const AuthException('La API devolvió una respuesta inválida.');
  }
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}
