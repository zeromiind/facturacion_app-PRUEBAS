import 'dart:convert';

import '../../../core/api/cliente_api.dart';
import '../../../core/auth/servicio_sesion.dart';
import '../dominio/mesa.dart';

class ServicioMesas {
  static final ServicioMesas instancia = ServicioMesas._();
  ServicioMesas._();

  final ClienteApi _api = ClienteApi.instancia;
  final ServicioSesion _sesion = ServicioSesion.instancia;

  Future<List<Mesa>> obtenerMesas() async {
    final sucursal = await _sesion.obtenerIdSucursal() ?? 4;
    final respuesta = await _api.get('/restaurant/tables', consulta: {'branch_id': '$sucursal'});
    if (respuesta.statusCode != 200) {
      throw Exception('No se pudo cargar las mesas (${respuesta.statusCode})');
    }
    final cuerpo = jsonDecode(respuesta.body) as Map<String, dynamic>;
    final lista = cuerpo['data'] as List<dynamic>? ?? [];
    final mesas = lista.map((e) => Mesa.desdeMapa(Map<String, dynamic>.from(e as Map))).toList();
    return mesas;
  }

  Future<List<Map<String, dynamic>>> obtenerPedidos() async {
    final sucursal = await _sesion.obtenerIdSucursal() ?? 4;
    final respuesta = await _api.get('/restaurant/orders', consulta: {'branch_id': '$sucursal'});
    if (respuesta.statusCode != 200) {
      throw Exception('No se pudo cargar los pedidos (${respuesta.statusCode})');
    }
    final cuerpo = jsonDecode(respuesta.body) as Map<String, dynamic>;
    final lista = cuerpo['data'] as List<dynamic>? ?? [];
    return lista.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> abrirCuenta({
    required int mesaId,
    required int comensales,
  }) async {
    final sucursal = await _sesion.obtenerIdSucursal() ?? 4;
    final almacen = await _sesion.obtenerIdAlmacen() ?? 3;
    final respuesta = await _api.post('/restaurant/orders', cuerpo: {
      'branch_id': sucursal,
      'warehouse_id': almacen,
      'table_id': mesaId,
      'guests': comensales,
      'notes': '',
      'items': [],
    });
    if (respuesta.statusCode != 200 && respuesta.statusCode != 201) {
      String mensaje = 'No se pudo abrir la cuenta';
      try {
        final datos = jsonDecode(respuesta.body) as Map<String, dynamic>;
        if (datos['message'] != null) mensaje = datos['message'].toString();
      } catch (_) {}
      throw Exception(mensaje);
    }
    return jsonDecode(respuesta.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> obtenerPedido(int pedidoId) async {
    final respuesta = await _api.get('/restaurant/orders/$pedidoId');
    if (respuesta.statusCode != 200) {
      throw Exception('No se pudo cargar la cuenta (${respuesta.statusCode})');
    }
    return jsonDecode(respuesta.body) as Map<String, dynamic>;
  }
}
