import 'package:flutter/material.dart';

import '../api/api_client.dart';

/// Stock por producto del almacén activo (mismo endpoint que usa la web).
class StockRepository {
  StockRepository(this._api);

  final ApiClient _api;

  Future<Map<int, double>> byProduct(int? warehouseId) async {
    final body = await _api.get('/api/inventory/current-stock', {
      'warehouse_id': warehouseId?.toString(),
    });
    final data = body['data'];
    final map = <int, double>{};
    if (data is List) {
      for (final row in data.whereType<Map>()) {
        final id = toIntOrNull(row['product_id']);
        if (id == null) continue;
        map[id] = (map[id] ?? 0) + toNum(row['stock']).toDouble();
      }
    }
    return map;
  }
}

String formatQty(double v) =>
    v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

class StockChip extends StatelessWidget {
  const StockChip({required this.stock, this.lowThreshold = 5, super.key});

  final double? stock;
  final double lowThreshold;

  @override
  Widget build(BuildContext context) {
    final value = stock ?? 0;
    final MaterialColor color = value <= 0
        ? Colors.red
        : (value <= lowThreshold ? Colors.orange : Colors.green);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'Stock ${formatQty(value)}',
        style: TextStyle(
          color: color.shade800,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
