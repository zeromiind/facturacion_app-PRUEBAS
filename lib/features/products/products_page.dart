import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/inventory/stock.dart';
import '../../core/session/app_context.dart';

class ProductRow {
  const ProductRow({
    required this.id,
    required this.name,
    required this.price,
    this.sku,
    this.category,
    this.unit,
    this.stock,
    this.active = true,
  });

  factory ProductRow.fromJson(Map<String, dynamic> j) => ProductRow(
    id: toIntOrNull(j['id']) ?? 0,
    name: (j['name'] ?? '').toString(),
    price: toNum(j['sale_price']).toDouble(),
    sku: j['sku']?.toString(),
    category: j['category_name']?.toString(),
    unit: (j['unit_code'] ?? j['unit_name'])?.toString(),
    stock: j['stock'] == null && j['current_stock'] == null
        ? null
        : toNum(j['stock'] ?? j['current_stock']).toDouble(),
    active: j['status'] == null ? true : toBool(j['status']),
  );

  final int id;
  final String name;
  final double price;
  final String? sku;
  final String? category;
  final String? unit;
  final double? stock;
  final bool active;
}

class ProductsPage extends StatefulWidget {
  const ProductsPage({
    required this.api,
    required this.appContext,
    required this.onUnauthorized,
    super.key,
  });

  final ApiClient api;
  final AppContext appContext;
  final VoidCallback onUnauthorized;

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final _search = TextEditingController();
  List<ProductRow> _rows = const [];
  Map<int, double> _stock = const {};
  bool _loading = false;
  String? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    StockRepository(widget.api)
        .byProduct(widget.appContext.warehouseId)
        .then((map) {
          if (mounted) setState(() => _stock = map);
        })
        .catchError((_) {});
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final body = await widget.api.get('/api/inventory/products', {
        'search': _search.text.trim(),
        'limit': '100',
        'autocomplete': 'true',
      });
      final data = body['data'];
      if (!mounted || seq != _seq) return;
      setState(
        () => _rows = data is List
            ? data
                  .whereType<Map>()
                  .map((r) => ProductRow.fromJson(r.cast<String, dynamic>()))
                  .toList()
            : const [],
      );
    } on ApiException catch (e) {
      if (e.isUnauthorized) return widget.onUnauthorized();
      if (mounted && seq == _seq) setState(() => _error = e.message);
    } finally {
      if (mounted && seq == _seq) setState(() => _loading = false);
    }
  }

  String _subtitle(ProductRow p) {
    return [
      if ((p.sku ?? '').isNotEmpty) p.sku!,
      if ((p.category ?? '').isNotEmpty) p.category!,
      if ((p.unit ?? '').isNotEmpty) p.unit!,
      if (!p.active) 'Inactivo',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final symbol = widget.appContext.defaultCurrency?.symbol ?? 'S/';
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Productos')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                hintText: 'Nombre, SKU o código de barras',
                prefixIcon: Icon(Icons.search),
              ),
              textInputAction: TextInputAction.search,
              onChanged: (_) => _load(),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: _rows.isEmpty && !_loading
                ? Center(child: Text(_error ?? 'Sin productos.'))
                : ListView.builder(
                    itemCount: _rows.length,
                    itemBuilder: (context, i) {
                      final p = _rows[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: ListTile(
                          title: Text(p.name),
                          subtitle: Text(_subtitle(p)),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '$symbol ${p.price.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              StockChip(stock: _stock[p.id]),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
