class UsuarioSesion {
  final int id;
  final int idEmpresa;
  final int? idSucursal;
  final String nombreUsuario;
  final String nombres;
  final String? apellidos;
  final String? correo;
  final String codigoRol;
  final Map<String, dynamic> permisos;

  UsuarioSesion({
    required this.id,
    required this.idEmpresa,
    required this.idSucursal,
    required this.nombreUsuario,
    required this.nombres,
    required this.apellidos,
    required this.correo,
    required this.codigoRol,
    required this.permisos,
  });

  factory UsuarioSesion.desdeMapa(Map<String, dynamic> mapa) {
    return UsuarioSesion(
      id: mapa['id'] ?? 0,
      idEmpresa: mapa['company_id'] ?? 0,
      idSucursal: mapa['branch_id'],
      nombreUsuario: mapa['username'] ?? '',
      nombres: mapa['first_name'] ?? '',
      apellidos: mapa['last_name'],
      correo: mapa['email'],
      codigoRol: mapa['role_code'] ?? '',
      permisos: mapa['permissions'] ?? {},
    );
  }

  String get nombreCompleto {
    final parts = <String>[];
    parts.add(nombres);
    if (apellidos != null && apellidos!.isNotEmpty) parts.add(apellidos!);
    return parts.join(' ');
  }
}
