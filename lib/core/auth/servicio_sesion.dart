import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../config/constantes.dart';
import 'usuario_sesion.dart';

class ServicioSesion {
  static final ServicioSesion instancia = ServicioSesion._();
  ServicioSesion._();

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _preferencias async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<String> obtenerIdDispositivo() async {
    final prefs = await _preferencias;
    String? id = prefs.getString(Constantes.claveIdDispositivo);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString(Constantes.claveIdDispositivo, id);
    }
    return id;
  }

  Future<void> guardarSesion({
    required String tokenAcceso,
    required String tokenActualizacion,
    required String fechaExpiracionAcceso,
    required Map<String, dynamic> usuario,
    required int idEmpresa,
    required int idSucursal,
    required int? idAlmacen,
  }) async {
    final prefs = await _preferencias;
    await prefs.setString(Constantes.claveTokenAcceso, tokenAcceso);
    await prefs.setString(Constantes.claveTokenActualizacion, tokenActualizacion);
    await prefs.setString(Constantes.claveFechaExpiracionAcceso, fechaExpiracionAcceso);
    await prefs.setString(Constantes.claveDatosUsuario, jsonEncode(usuario));
    await prefs.setInt(Constantes.claveIdEmpresa, idEmpresa);
    await prefs.setInt(Constantes.claveIdSucursal, idSucursal);
    if (idAlmacen != null) {
      await prefs.setInt(Constantes.claveIdAlmacen, idAlmacen);
    } else {
      await prefs.remove(Constantes.claveIdAlmacen);
    }
  }

  Future<String?> obtenerTokenAcceso() async {
    final prefs = await _preferencias;
    return prefs.getString(Constantes.claveTokenAcceso);
  }

  Future<String?> obtenerTokenActualizacion() async {
    final prefs = await _preferencias;
    return prefs.getString(Constantes.claveTokenActualizacion);
  }

  Future<UsuarioSesion?> obtenerUsuario() async {
    final prefs = await _preferencias;
    final datos = prefs.getString(Constantes.claveDatosUsuario);
    if (datos == null) return null;
    try {
      final mapa = jsonDecode(datos) as Map<String, dynamic>;
      return UsuarioSesion.desdeMapa(mapa);
    } catch (_) {
      return null;
    }
  }

  Future<int?> obtenerIdEmpresa() async {
    final prefs = await _preferencias;
    return prefs.getInt(Constantes.claveIdEmpresa);
  }

  Future<int?> obtenerIdSucursal() async {
    final prefs = await _preferencias;
    return prefs.getInt(Constantes.claveIdSucursal);
  }

  Future<int?> obtenerIdAlmacen() async {
    final prefs = await _preferencias;
    return prefs.getInt(Constantes.claveIdAlmacen);
  }

  Future<bool> haySesion() async {
    final token = await obtenerTokenAcceso();
    return token != null && token.isNotEmpty;
  }

  Future<void> cerrarSesion() async {
    final prefs = await _preferencias;
    await prefs.remove(Constantes.claveTokenAcceso);
    await prefs.remove(Constantes.claveTokenActualizacion);
    await prefs.remove(Constantes.claveFechaExpiracionAcceso);
    await prefs.remove(Constantes.claveDatosUsuario);
    await prefs.remove(Constantes.claveIdEmpresa);
    await prefs.remove(Constantes.claveIdSucursal);
    await prefs.remove(Constantes.claveIdAlmacen);
  }
}
