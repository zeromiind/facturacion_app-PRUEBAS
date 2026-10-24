import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/servicio_sesion.dart';
import '../config/constantes.dart';

class ClienteApi {
  static final ClienteApi instancia = ClienteApi._();
  ClienteApi._();

  final http.Client _cliente = http.Client();
  final ServicioSesion _sesion = ServicioSesion.instancia;

  Future<Map<String, String>> _cabeceras({bool conAuth = true}) async {
    final cabeceras = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (conAuth) {
      final token = await _sesion.obtenerTokenAcceso();
      if (token != null && token.isNotEmpty) {
        cabeceras['Authorization'] = 'Bearer $token';
      }
    }
    return cabeceras;
  }

  Future<http.Response> get(String ruta, {Map<String, String>? consulta}) async {
    final uri = Uri.parse('${Constantes.urlBaseApi}$ruta').replace(queryParameters: consulta);
    final cabeceras = await _cabeceras();
    var respuesta = await _cliente.get(uri, headers: cabeceras);
    if (respuesta.statusCode == 401) {
      final actualizado = await _intentarActualizarToken();
      if (actualizado) {
        final cabeceras2 = await _cabeceras();
        respuesta = await _cliente.get(uri, headers: cabeceras2);
      } else {
        await _sesion.cerrarSesion();
      }
    }
    return respuesta;
  }

  Future<http.Response> post(String ruta, {Map<String, dynamic>? cuerpo, bool conAuth = true}) async {
    final uri = Uri.parse('${Constantes.urlBaseApi}$ruta');
    final cabeceras = await _cabeceras(conAuth: conAuth);
    var respuesta = await _cliente.post(uri, headers: cabeceras, body: jsonEncode(cuerpo ?? {}));
    if (conAuth && respuesta.statusCode == 401) {
      final actualizado = await _intentarActualizarToken();
      if (actualizado) {
        final cabeceras2 = await _cabeceras(conAuth: conAuth);
        respuesta = await _cliente.post(uri, headers: cabeceras2, body: jsonEncode(cuerpo ?? {}));
      } else {
        await _sesion.cerrarSesion();
      }
    }
    return respuesta;
  }

  Future<http.Response> put(String ruta, {Map<String, dynamic>? cuerpo}) async {
    final uri = Uri.parse('${Constantes.urlBaseApi}$ruta');
    final cabeceras = await _cabeceras();
    var respuesta = await _cliente.put(uri, headers: cabeceras, body: jsonEncode(cuerpo ?? {}));
    if (respuesta.statusCode == 401) {
      final actualizado = await _intentarActualizarToken();
      if (actualizado) {
        final cabeceras2 = await _cabeceras();
        respuesta = await _cliente.put(uri, headers: cabeceras2, body: jsonEncode(cuerpo ?? {}));
      } else {
        await _sesion.cerrarSesion();
      }
    }
    return respuesta;
  }

  Future<bool> _intentarActualizarToken() async {
    try {
      final refresh = await _sesion.obtenerTokenActualizacion();
      final deviceId = await _sesion.obtenerIdDispositivo();
      if (refresh == null || refresh.isEmpty) return false;
      final uri = Uri.parse('${Constantes.urlBaseApi}/auth/refresh');
      final respuesta = await _cliente.post(
        uri,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({'refresh_token': refresh, 'device_id': deviceId}),
      );
      if (respuesta.statusCode == 200) {
        final datos = jsonDecode(respuesta.body) as Map<String, dynamic>;
        final tokenAcceso = datos['access_token'] as String?;
        final tokenActualizacion = datos['refresh_token'] as String?;
        final fechaExpiracion = datos['access_expires_at'] as String?;
        if (tokenAcceso == null || tokenActualizacion == null || fechaExpiracion == null) return false;
        final prefs = await _sesion.obtenerUsuario();
        if (prefs == null) return false;
        await _sesion.guardarSesion(
          tokenAcceso: tokenAcceso,
          tokenActualizacion: tokenActualizacion,
          fechaExpiracionAcceso: fechaExpiracion,
          usuario: {
            'id': prefs.id,
            'company_id': prefs.idEmpresa,
            'branch_id': prefs.idSucursal,
            'username': prefs.nombreUsuario,
            'first_name': prefs.nombres,
            'last_name': prefs.apellidos,
            'email': prefs.correo,
            'role_code': prefs.codigoRol,
            'permissions': prefs.permisos,
          },
          idEmpresa: prefs.idEmpresa,
          idSucursal: prefs.idSucursal ?? 0,
          idAlmacen: await _sesion.obtenerIdAlmacen(),
        );
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
