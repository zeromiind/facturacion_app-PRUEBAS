import 'package:flutter/material.dart';

import '../dato/servicio_catalogo.dart';
import '../dominio/producto_catalogo.dart';

class PantallaCarta extends StatefulWidget {
  const PantallaCarta({super.key});

  @override
  State<PantallaCarta> createState() => _PantallaCartaState();
}

class _PantallaCartaState extends State<PantallaCarta> {
  final _servicio = ServicioCatalogo.instancia;
  final _controladorBusqueda = TextEditingController();
  List<ProductoCatalogo> _productos = [];
  String _busqueda = '';
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _controladorBusqueda.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final productos = await _servicio.obtenerProductos();
      setState(() {
        _productos = productos;
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

  List<ProductoCatalogo> get _filtrados {
    final q = _busqueda.trim().toLowerCase();
    if (q.isEmpty) return _productos;
    return _productos.where((p) {
      return p.nombre.toLowerCase().contains(q) || p.codigoSku.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Carta')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controladorBusqueda,
              onChanged: (v) => setState(() => _busqueda = v),
              decoration: const InputDecoration(
                hintText: 'Buscar producto por nombre o código',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _cargando
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
                      : _filtrados.isEmpty
                          ? const Center(child: Text('No se encontraron productos'))
                          : GridView.builder(
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 260,
                                mainAxisExtent: 150,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                              itemCount: _filtrados.length,
                              itemBuilder: (context, index) {
                                final p = _filtrados[index];
                                return Card(
                                  clipBehavior: Clip.antiAlias,
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            CircleAvatar(
                                              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                              child: Icon(Icons.fastfood_outlined, color: Theme.of(context).colorScheme.onPrimaryContainer),
                                            ),
                                            const Spacer(),
                                            Text(p.precioFormateado, style: const TextStyle(fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                        const Spacer(),
                                        Text(p.nombre, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 4),
                                        Text(p.codigoSku, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
