import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../dato/servicio_mesas.dart';

class PantallaCuentaMesa extends StatefulWidget {
  final int pedidoId;
  final String nombreMesa;

  const PantallaCuentaMesa({
    super.key,
    required this.pedidoId,
    required this.nombreMesa,
  });

  @override
  State<PantallaCuentaMesa> createState() => _PantallaCuentaMesaState();
}

class _PantallaCuentaMesaState extends State<PantallaCuentaMesa> {
  final _servicio = ServicioMesas.instancia;
  bool _cargando = true;
  String? _error;
  Map<String, dynamic>? _pedido;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final pedido = await _servicio.obtenerPedido(widget.pedidoId);
      setState(() {
        _pedido = pedido;
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

  double get _total {
    if (_pedido == null) return 0.0;
    final total = _pedido!['total'];
    if (total == null) return 0.0;
    return double.tryParse(total.toString()) ?? 0.0;
  }

  List<dynamic> get _items {
    if (_pedido == null) return [];
    return _pedido!['items'] ?? _pedido!['details'] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Cuenta - ${widget.nombreMesa}'),
        actions: [
          IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh), tooltip: 'Actualizar'),
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
                      FilledButton(onPressed: _cargar, child: const Text('Reintentar')),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: _items.isEmpty
                          ? const Center(
                              child: Text('Sin productos. Agrega desde Carta o Mostrador.'),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _items.length,
                              separatorBuilder: (_, _) => const Divider(),
                              itemBuilder: (context, index) {
                                final item = _items[index] as Map<String, dynamic>;
                                final nombre = item['product_name'] ?? item['name'] ?? item['description'] ?? '';
                                final cantidad = item['quantity'] ?? item['qty'] ?? 1;
                                final precio = item['unit_price'] ?? item['price'] ?? '0.00';
                                final importe = item['total'] ?? item['amount'] ?? precio;
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(nombre.toString()),
                                  subtitle: Text('Cant: $cantidad   P. Unit: S/ $precio'),
                                  trailing: Text('S/ $importe', style: const TextStyle(fontWeight: FontWeight.bold)),
                                );
                              },
                            ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(top: BorderSide(color: Colors.grey.shade300)),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              Text('S/ ${_total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => context.go('/carta'),
                                  icon: const Icon(Icons.menu_book),
                                  label: const Text('Agregar desde Carta'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Se solicitará la cuenta (próximamente en Caja)')),
                                    );
                                  },
                                  icon: const Icon(Icons.receipt_long),
                                  label: const Text('Pedir cuenta'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}
