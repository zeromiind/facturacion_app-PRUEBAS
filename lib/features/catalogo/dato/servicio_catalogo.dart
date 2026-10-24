import 'dart:convert';

import '../../../core/api/cliente_api.dart';
import '../dominio/producto_catalogo.dart';

class ServicioCatalogo {
  static final ServicioCatalogo instancia = ServicioCatalogo._();
  ServicioCatalogo._();

  final ClienteApi _api = ClienteApi.instancia;

  Future<List<ProductoCatalogo>> obtenerProductos() async {
    final respuesta = await _api.get('/inventory/products');
    if (respuesta.statusCode != 200) {
      throw Exception('No se pudo cargar la carta (${respuesta.statusCode})');
    }
    final cuerpo = jsonDecode(respuesta.body) as Map<String, dynamic>;
    final lista = cuerpo['data'] as List<dynamic>? ?? [];
    final productos = lista
        .map((e) => ProductoCatalogo.desdeMapa(Map<String, dynamic>.from(e as Map)))
        .where((p) => p.estaActivo && p.naturalezaProducto == 'PRODUCT')
        .toList();
    productos.sort((a, b) => a.nombre.compareTo(b.nombre));
    return productos;
  }
}
