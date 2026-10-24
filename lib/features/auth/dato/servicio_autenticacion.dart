import 'dart:convert';

import '../../../core/api/cliente_api.dart';
import '../../../core/auth/servicio_sesion.dart';

class ServicioAutenticacion {
  static final ServicioAutenticacion instancia = ServicioAutenticacion._();
  ServicioAutenticacion._();

  final ClienteApi _api = ClienteApi.instancia;
  final ServicioSesion _sesion = ServicioSesion.instancia;

  Future<Map<String, dynamic>> iniciarSesion({
    required String usuario,
    required String contrasena,
  }) async {
    final idDispositivo = await _sesion.obtenerIdDispositivo();
    final respuesta = await _api.post(
      '/auth/login',
      conAuth: false,
      cuerpo: {
        'username': usuario,
        'password': contrasena,
        'device_id': idDispositivo,
        'device_name': 'Flutter Web',
      },
    );

    if (respuesta.statusCode != 200) {
      String mensaje = 'No se pudo iniciar sesión';
      try {
        final datos = jsonDecode(respuesta.body) as Map<String, dynamic>;
        if (datos['message'] != null) {
          mensaje = datos['message'].toString();
        }
      } catch (_) {}
      throw Exception(mensaje);
    }

    final datos = jsonDecode(respuesta.body) as Map<String, dynamic>;
    final tokenAcceso = datos['access_token'] as String;
    final tokenActualizacion = datos['refresh_token'] as String;
    final fechaExpiracion = datos['access_expires_at'] as String;
    final usuarioDatos = datos['user'] as Map<String, dynamic>;

    await _sesion.guardarSesion(
      tokenAcceso: tokenAcceso,
      tokenActualizacion: tokenActualizacion,
      fechaExpiracionAcceso: fechaExpiracion,
      usuario: usuarioDatos,
      idEmpresa: usuarioDatos['company_id'] ?? 0,
      idSucursal: usuarioDatos['branch_id'] ?? 0,
      idAlmacen: null,
    );

    return datos;
  }
}
