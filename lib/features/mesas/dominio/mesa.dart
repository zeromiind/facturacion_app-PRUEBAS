class Mesa {
  final int id;
  final String codigo;
  final String nombre;
  final int capacidad;
  final String estado;
  final int? pedidoId;
  final String? pedidoEstado;

  Mesa({
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.capacidad,
    required this.estado,
    this.pedidoId,
    this.pedidoEstado,
  });

  factory Mesa.desdeMapa(Map<String, dynamic> mapa) {
    return Mesa(
      id: mapa['id'] ?? 0,
      codigo: mapa['code']?.toString() ?? '',
      nombre: mapa['name']?.toString() ?? '',
      capacidad: mapa['capacity'] ?? 0,
      estado: mapa['status']?.toString() ?? 'AVAILABLE',
    );
  }

  Mesa copiarCon({int? pedidoId, String? pedidoEstado}) {
    return Mesa(
      id: id,
      codigo: codigo,
      nombre: nombre,
      capacidad: capacidad,
      estado: estado,
      pedidoId: pedidoId ?? this.pedidoId,
      pedidoEstado: pedidoEstado ?? this.pedidoEstado,
    );
  }

  bool get estaLibre {
    return estado == 'AVAILABLE';
  }

  bool get estaOcupada {
    return estado == 'OCCUPIED';
  }

  bool get estaReservada {
    return estado == 'RESERVED';
  }

  bool get estaInhabilitada {
    return estado == 'DISABLED';
  }
}
