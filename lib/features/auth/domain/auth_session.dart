class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAt,
    required this.deviceId,
    required this.username,
    required this.firstName,
    required this.lastName,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAt;
  final String deviceId;
  final String username;
  final String firstName;
  final String lastName;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? const {};
    return AuthSession(
      accessToken: _requiredString(json, 'access_token'),
      refreshToken: _requiredString(json, 'refresh_token'),
      accessExpiresAt: DateTime.parse(
        _requiredString(json, 'access_expires_at'),
      ),
      deviceId: _requiredString(json, 'device_id'),
      username: _requiredString(user, 'username'),
      firstName: (user['first_name'] as String? ?? '').trim(),
      lastName: (user['last_name'] as String? ?? '').trim(),
    );
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException('Respuesta de autenticación incompleta.');
    }
    return value;
  }
}
