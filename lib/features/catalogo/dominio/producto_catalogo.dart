class ProductoCatalogo {
  final int id;
  final String codigoSku;
  final String nombre;
  final String precioVenta;
  final String? categoria;
  final String? linea;
  final bool esAlmacenable;
  final int estado;
  final String? urlImagen;
  final String naturalezaProducto;

  ProductoCatalogo({
    required this.id,
    required this.codigoSku,
    required this.nombre,
    required this.precioVenta,
    required this.categoria,
    required this.linea,
    required this.esAlmacenable,
    required this.estado,
    required this.urlImagen,
    required this.naturalezaProducto,
  });

  factory ProductoCatalogo.desdeMapa(Map<String, dynamic> mapa) {
    return ProductoCatalogo(
      id: mapa['id'] ?? 0,
      codigoSku: mapa['sku']?.toString() ?? '',
      nombre: mapa['name']?.toString() ?? '',
      precioVenta: mapa['sale_price']?.toString() ?? '0.00',
      categoria: mapa['category_name']?.toString(),
      linea: mapa['line_name']?.toString(),
      esAlmacenable: mapa['is_stockable'] == true,
      estado: mapa['status'] ?? 0,
      urlImagen: mapa['image_url']?.toString(),
      naturalezaProducto: mapa['product_nature']?.toString() ?? 'PRODUCT',
    );
  }

  double get precioDouble {
    return double.tryParse(precioVenta.replaceAll(',', '.')) ?? 0.0;
  }

  int get precioEnCentimos {
    return (precioDouble * 100).round();
  }

  String get precioFormateado {
    return 'S/ ${precioDouble.toStringAsFixed(2)}';
  }

  bool get estaActivo {
    return estado == 1;
  }
}
