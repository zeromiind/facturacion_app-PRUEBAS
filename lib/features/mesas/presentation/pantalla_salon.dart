import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../dato/servicio_mesas.dart';
import '../dominio/mesa.dart';

class PantallaSalon extends StatefulWidget {
  const PantallaSalon({super.key});

  @override
  State<PantallaSalon> createState() => _PantallaSalonState();
}

class _PantallaSalonState extends State<PantallaSalon> {
  final _servicio = ServicioMesas.instancia;
  bool _cargando = true;
  String? _error;
  List<Mesa> _mesas = [];
  Map<int, int> _pedidoPorMesa = {};

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  Future<void> _cargarTodo() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final resultados = await Future.wait([
        _servicio.obtenerMesas(),
        _servicio.obtenerPedidos(),
      ]);
      final mesas = resultados[0] as List<Mesa>;
      final pedidos = resultados[1] as List<Map<String, dynamic>>;
      final mapaPedido = <int, int>{};
      for (final p in pedidos) {
        final mesaId = p['table_id'];
        final pedidoId = p['id'];
        if (mesaId != null && pedidoId != null) {
          mapaPedido[int.parse(mesaId.toString())] = int.parse(pedidoId.toString());
        }
      }
      setState(() {
        _mesas = mesas;
        _pedidoPorMesa = mapaPedido;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _cargando = false;
        });
      }
    }
  }

  Color _colorEstado(Mesa mesa) {
    if (_pedidoPorMesa.containsKey(mesa.id)) {
      return Colors.red.shade400;
    }
    switch (mesa.estado) {
      case 'OCCUPIED':
        return Colors.red.shade400;
      case 'RESERVED':
        return Colors.orange.shade400;
      case 'DISABLED':
        return Colors.grey.shade400;
      case 'AVAILABLE':
      default:
        return Colors.green.shade400;
    }
  }

  String _textoEstado(Mesa mesa) {
    if (_pedidoPorMesa.containsKey(mesa.id)) {
      return 'Ocupada';
    }
    switch (mesa.estado) {
      case 'OCCUPIED':
        return 'Ocupada';
      case 'RESERVED':
        return 'Reservada';
      case 'DISABLED':
        return 'Inhabilitada';
      case 'AVAILABLE':
      default:
        return 'Libre';
    }
  }

  Future<void> _tocarMesa(Mesa mesa) async {
    if (_pedidoPorMesa.containsKey(mesa.id)) {
      final pedidoId = _pedidoPorMesa[mesa.id]!;
      if (mounted) {
        context.push('/cuenta-mesa', extra: {'pedidoId': pedidoId, 'nombreMesa': mesa.nombre});
      }
      return;
    }

    if (!mesa.estaLibre && mesa.estado != 'AVAILABLE') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mesa ${mesa.nombre}: ${_textoEstado(mesa)}')),
      );
      return;
    }

    final comensales = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        int cantidad = 2;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Abrir cuenta - ${mesa.nombre}'),
              content: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: cantidad > 1 ? () => setDialogState(() => cantidad--) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text('$cantidad comensales', style: const TextStyle(fontSize: 18)),
                  ),
                  IconButton(
                    onPressed: () => setDialogState(() => cantidad++),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancelar')),
                FilledButton(onPressed: () => Navigator.of(dialogContext).pop(cantidad), child: const Text('Abrir')),
              ],
            );
          },
        );
      },
    );

    if (comensales == null) return;
    if (!mounted) return;

    setState(() => _cargando = true);
    try {
      final resultado = await _servicio.abrirCuenta(mesaId: mesa.id, comensales: comensales);
      final pedidoId = resultado['id'] ?? resultado['order_id'];
      await _cargarTodo();
      if (mounted && pedidoId != null) {
        context.push('/cuenta-mesa', extra: {'pedidoId': int.parse(pedidoId.toString()), 'nombreMesa': mesa.nombre});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _cargando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Salón'),
        actions: [
          IconButton(
            onPressed: _cargarTodo,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: _cargarTodo, child: const Text('Reintentar')),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 200,
                      mainAxisExtent: 150,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: _mesas.length,
                    itemBuilder: (context, index) {
                      final mesa = _mesas[index];
                      final tienePedido = _pedidoPorMesa.containsKey(mesa.id);
                      final color = _colorEstado(mesa);
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => _tocarMesa(mesa),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border(top: BorderSide(color: color, width: 4)),
                            ),
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      mesa.nombre,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                    ),
                                    Icon(Icons.table_restaurant, color: color),
                                  ],
                                ),
                                const Spacer(),
                                Text('Capacidad: ${mesa.capacidad}'),
                                const SizedBox(height: 4),
                                Text(tienePedido ? 'Ocupada' : _textoEstado(mesa), style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
