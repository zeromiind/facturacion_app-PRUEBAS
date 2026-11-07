import 'dart:math';

import '../../../core/api/api_client.dart';
import '../../../core/inventory/stock.dart';
import '../../../core/session/app_context.dart';
import '../../../core/time/lima_time.dart';
import '../domain/product.dart';

class CartLine {
  CartLine({required this.product, this.qty = 1, double? unitPrice})
    : unitPrice = unitPrice ?? product.salePrice;

  final Product product;
  double qty;
  double unitPrice;

  double get gross => qty * unitPrice;
}

class SaleTotals {
  const SaleTotals(this.subtotal, this.tax, this.total);

  final double subtotal;
  final double tax;
  final double total;
}

enum SunatSendMode { direct, dailySummary, disabled }

class SaleDraft {
  SaleDraft({
    required this.documentKind,
    required this.series,
    required this.customerId,
    required this.paymentMethodId,
    required this.lines,
    this.sunatSendMode = SunatSendMode.direct,
    this.customerAddress,
    this.customerPhone,
    this.vehicleId,
    this.odometerKm,
    this.nextOdometerKm,
    this.notes,
  });

  final DocumentKind documentKind;
  final String series;
  final int customerId;
  final int paymentMethodId;
  final List<CartLine> lines;
  final SunatSendMode sunatSendMode;
  final String? customerAddress;
  final String? customerPhone;
  final int? vehicleId;
  final int? odometerKm;
  final int? nextOdometerKm;
  final String? notes;
}

class SalesRepository {
  SalesRepository(this._api, this._context);

  final ApiClient _api;
  final AppContext _context;
  String _clientRequestId = _newRequestId();

  static String _newRequestId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32).toRadixString(16)}';

  Future<List<Product>> searchProducts(String query) async {
    final body = await _api.get('/api/inventory/products', {
      'search': query.trim(),
      'status': '1',
      'limit': '50',
      'autocomplete': 'true',
    });
    return _mapProducts(body['data']);
  }

  Future<Map<int, double>> stockByProduct() =>
      StockRepository(_api).byProduct(_context.warehouseId);

  Future<List<Product>> quickProducts({int limit = 4}) async {
    final body = await _api.get('/api/inventory/products', {
      'warehouse_id': _context.warehouseId?.toString(),
      'status': '1',
      'limit': '$limit',
    });
    return _mapProducts(body['data']);
  }

  List<Product> _mapProducts(Object? data) {
    if (data is! List) return const [];
    return data.whereType<Map>().map((raw) {
      final row = raw.cast<String, dynamic>();
      return Product(
        id: toIntOrNull(row['id']) ?? 0,
        name: (row['name'] ?? '').toString(),
        salePrice: toNum(row['sale_price']).toDouble(),
        sku: row['sku']?.toString(),
        unitId: toIntOrNull(row['unit_id']),
        unitCode: row['unit_code']?.toString(),
        categoryName: row['category_name']?.toString(),
        lotTracking: toBool(row['lot_tracking']),
      );
    }).toList();
  }

  Future<List<SeriesOption>> seriesFor(String documentKind) async {
    final body = await _api.get('/api/sales/series-numbers', {
      'document_kind': documentKind,
      'branch_id': _context.branchId?.toString(),
      'warehouse_id': _context.warehouseId?.toString(),
    });
    final data = body['data'];
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .where((r) => r['document_kind'] == documentKind)
        .map(
          (r) => SeriesOption(
            series: r['series'].toString(),
            nextNumber: (toIntOrNull(r['current_number']) ?? 0) + 1,
          ),
        )
        .toList();
  }

  /// Los precios se manejan con IGV incluido en documentos tributarios.
  SaleTotals totals(List<CartLine> lines, DocumentKind kind) {
    final rate = kind.isTributary ? (_context.defaultTax?.ratePercent ?? 0) : 0;
    var subtotal = 0.0, tax = 0.0;
    for (final line in lines) {
      final gross = line.gross;
      final base = rate > 0 ? gross / (1 + rate / 100) : gross;
      subtotal += base;
      tax += gross - base;
    }
    return SaleTotals(subtotal, tax, subtotal + tax);
  }

  Future<Map<String, dynamic>> createDocument(SaleDraft draft) async {
    final kind = draft.documentKind;
    final isPre = !kind.isTributary;
    final taxCategory = kind.isTributary ? _context.defaultTax : null;
    final rate = taxCategory?.ratePercent ?? 0;

    double round2(double v) => double.parse(v.toStringAsFixed(2));

    final items = draft.lines.map((line) {
      final gross = line.gross;
      final subtotal = rate > 0
          ? round2(gross / (1 + rate / 100))
          : round2(gross);
      final tax = round2(gross - subtotal);
      return {
        'description': line.product.name,
        'product_id': line.product.id,
        'unit_id': line.product.unitId ?? _context.unitId,
        'tax_category_id': taxCategory?.id,
        'qty': line.qty,
        'unit_price': line.unitPrice,
        'subtotal': subtotal,
        'tax_total': tax,
        'total': round2(gross),
        'metadata': {
          'price_includes_tax': rate > 0,
          'descuento': 0,
          'gratuitas': 0,
          'is_free_operation': false,
        },
      };
    }).toList();
    final total = items.fold<double>(
      0,
      (sum, i) => sum + (i['total'] as double),
    );

    final issueAt = limaIsoOffset(limaNow());

    final hasVehicle = _context.workshopEnabled && draft.vehicleId != null;
    final body = {
      'document_kind': kind.code,
      'document_kind_id': kind.id,
      'branch_id': _context.branchId,
      'warehouse_id': _context.warehouseId,
      'cash_register_id': _context.cashRegisterId,
      'series': draft.series,
      'issue_at': issueAt,
      'due_at': null,
      'customer_id': draft.customerId,
      'customer_vehicle_id': hasVehicle ? draft.vehicleId : null,
      'currency_id': _context.defaultCurrency?.id ?? 1,
      'payment_method_id': draft.paymentMethodId,
      'notes': (draft.notes ?? '').trim().isEmpty ? null : draft.notes!.trim(),
      'status': isPre ? 'DRAFT' : 'ISSUED',
      'items': items,
      'payments': isPre
          ? <Map<String, dynamic>>[]
          : [
              {
                'payment_method_id': draft.paymentMethodId,
                'amount': round2(total),
                'status': 'PAID',
                'paid_at': issueAt,
              },
            ],
      'metadata': {
        'defer_sunat_send':
            !isPre && draft.sunatSendMode == SunatSendMode.disabled,
        'force_async_on_issue': !isPre,
        'receipt_send_mode': kind.code == 'RECEIPT'
            ? (draft.sunatSendMode == SunatSendMode.dailySummary
                  ? 'SUMMARY'
                  : 'DIRECT')
            : null,
        'customer_address': draft.customerAddress,
        'customer_phone': draft.customerPhone,
        'vehicle_odometer_km': hasVehicle ? draft.odometerKm : null,
        'vehicle_next_odometer_km': hasVehicle ? draft.nextOdometerKm : null,
        'payment_condition': 'CONTADO',
        'credit_installments': <Map<String, dynamic>>[],
        'credit_total': 0,
        'has_advance': false,
        'advance_amount': 0,
        'discount_total': 0,
        'client_request_id': _clientRequestId,
      },
    };

    final result = await _api.post('/api/sales/commercial-documents', body);
    _clientRequestId = _newRequestId();
    return result;
  }
}
