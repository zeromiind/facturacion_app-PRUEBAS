import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.statusCode,
    this.responseBody = const {},
  });

  final String message;
  final int? statusCode;
  final Map<String, dynamic> responseBody;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({required this.accessToken, http.Client? client})
    : _client = client ?? http.Client();

  final String accessToken;
  final http.Client _client;

  Future<Map<String, dynamic>> get(
    String path, [
    Map<String, String?> query = const {},
  ]) => _send('GET', path, query: query);

  Future<Uint8List> getBytes(
    String path, [
    Map<String, String?> query = const {},
  ]) async {
    final cleanQuery = {
      for (final entry in query.entries)
        if (entry.value != null && entry.value!.isNotEmpty)
          entry.key: entry.value!,
    };
    final uri = Uri.parse(
      '${AppConfig.apiBaseUrl}$path',
    ).replace(queryParameters: cleanQuery.isEmpty ? null : cleanQuery);
    final request = http.Request('GET', uri)
      ..headers.addAll({
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/pdf',
      });

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(AppConfig.apiTimeout),
      );
    } on Exception {
      throw const ApiException('No se pudo conectar con el servidor.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      Map<String, dynamic> decoded = const {};
      try {
        final value = jsonDecode(utf8.decode(response.bodyBytes));
        if (value is Map<String, dynamic>) decoded = value;
      } on FormatException {
        // Se trata como respuesta vacía; el status decide el resultado.
      }
      throw ApiException(
        _errorMessage(decoded) ?? 'Error ${response.statusCode} del servidor.',
        statusCode: response.statusCode,
        responseBody: decoded,
      );
    }

    return response.bodyBytes;
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) =>
      _send('POST', path, body: body);

  Future<Map<String, dynamic>> uploadFile(
    String path, {
    required String fieldName,
    required Uint8List bytes,
    required String filename,
  }) async {
    final request =
        http.MultipartRequest('POST', Uri.parse('${AppConfig.apiBaseUrl}$path'))
          ..headers.addAll({
            'Authorization': '******',
            'Accept': 'application/json',
          })
          ..files.add(
            http.MultipartFile.fromBytes(fieldName, bytes, filename: filename),
          );

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(AppConfig.apiTimeout),
      );
    } on Exception {
      throw const ApiException('No se pudo conectar con el servidor.');
    }

    Map<String, dynamic> decoded = const {};
    try {
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (value is Map<String, dynamic>) decoded = value;
    } on FormatException {
      // El status de la respuesta determina el resultado.
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        _errorMessage(decoded) ?? 'Error ${response.statusCode} del servidor.',
        statusCode: response.statusCode,
        responseBody: decoded,
      );
    }
    return decoded;
  }

  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body) =>
      _send('PUT', path, body: body);

  Future<Map<String, dynamic>> delete(String path) => _send('DELETE', path);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, String?> query = const {},
    Map<String, dynamic>? body,
  }) async {
    final cleanQuery = {
      for (final entry in query.entries)
        if (entry.value != null && entry.value!.isNotEmpty)
          entry.key: entry.value!,
    };
    final uri = Uri.parse(
      '${AppConfig.apiBaseUrl}$path',
    ).replace(queryParameters: cleanQuery.isEmpty ? null : cleanQuery);
    final request = http.Request(method, uri)
      ..headers.addAll({
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      });
    if (body != null) request.body = jsonEncode(body);

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(AppConfig.apiTimeout),
      );
    } on Exception {
      throw const ApiException('No se pudo conectar con el servidor.');
    }

    Map<String, dynamic> decoded = const {};
    try {
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (value is Map<String, dynamic>) decoded = value;
    } on FormatException {
      // Se trata como respuesta vacía; el status decide el resultado.
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        _errorMessage(decoded) ?? 'Error ${response.statusCode} del servidor.',
        statusCode: response.statusCode,
        responseBody: decoded,
      );
    }
    return decoded;
  }

  String? _errorMessage(Map<String, dynamic> body) {
    final errors = body['errors'];
    if (errors is Map && errors.isNotEmpty) {
      final first = errors.values.first;
      if (first is List && first.isNotEmpty) return first.first.toString();
    }
    final message = body['message'];
    return message is String && message.isNotEmpty ? message : null;
  }
}

num toNum(Object? value, [num fallback = 0]) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '') ?? fallback;
}

int? toIntOrNull(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

bool toBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().toLowerCase();
  return text == '1' || text == 'true';
}
