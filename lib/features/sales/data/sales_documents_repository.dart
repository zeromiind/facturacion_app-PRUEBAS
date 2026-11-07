import '../../../core/api/api_client.dart';
import '../../../core/session/app_context.dart';
import '../../../core/time/lima_time.dart';

class SaleDocument {
  const SaleDocument({
    required this.id,
    required this.documentKind,
    required this.series,
    required this.number,
    required this.issueAt,
    required this.status,
    required this.sunatStatus,
    required this.total,
    required this.balanceDue,
    required this.customerName,
    required this.customerDocNumber,
    required this.plate,
    required this.vehicleLabel,
    required this.paymentMethod,
    required this.createdBy,
  });

  factory SaleDocument.fromJson(Map<String, dynamic> json) {
    final brand = (json['vehicle_brand_snapshot'] ?? '').toString();
    final model = (json['vehicle_model_snapshot'] ?? '').toString();
    return SaleDocument(
      id: toIntOrNull(json['id']) ?? 0,
      documentKind: (json['document_kind'] ?? '').toString(),
      series: (json['series'] ?? '').toString(),
      number: (json['number'] ?? '').toString(),
      issueAt: parseApiDateToLima((json['issue_at'] ?? '').toString()),
      status: (json['status'] ?? '').toString(),
      sunatStatus: json['sunat_status']?.toString(),
      total: toNum(json['total']).toDouble(),
      balanceDue: toNum(json['balance_due']).toDouble(),
      customerName: (json['customer_name'] ?? 'Cliente varios').toString(),
      customerDocNumber: json['customer_doc_number']?.toString(),
      plate: json['vehicle_plate_snapshot']?.toString(),
      vehicleLabel: '$brand $model'.trim(),
      paymentMethod: json['payment_method_name']?.toString(),
      createdBy: json['created_by_user_name']?.toString(),
    );
  }

  final int id;
  final String documentKind;
  final String series;
  final String number;
  final DateTime? issueAt;
  final String status;
  final String? sunatStatus;
  final double total;
  final double balanceDue;
  final String customerName;
  final String? customerDocNumber;
  final String? plate;
  final String vehicleLabel;
  final String? paymentMethod;
  final String? createdBy;

  String get fullNumber => '$series-$number';
}

class SaleDocumentItem {
  const SaleDocumentItem({
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.total,
    this.unitLabel,
  });

  factory SaleDocumentItem.fromJson(Map<String, dynamic> json) =>
      SaleDocumentItem(
        description: (json['description'] ?? 'Artículo').toString(),
        quantity: toNum(json['qty']).toDouble(),
        unitPrice: toNum(json['unitPrice'] ?? json['unit_price']).toDouble(),
        total: toNum(json['lineTotal'] ?? json['total']).toDouble(),
        unitLabel: json['unitLabel']?.toString(),
      );

  final String description;
  final double quantity;
  final double unitPrice;
  final double total;
  final String? unitLabel;
}

class DocumentPage {
  const DocumentPage(this.items, this.page, this.lastPage, this.total);

  final List<SaleDocument> items;
  final int page;
  final int lastPage;
  final int total;
}

enum DocumentTab { all, tributary, orders, pending, converted }

class DocumentFilters {
  const DocumentFilters({
    this.tab = DocumentTab.all,
    this.customer = '',
    this.vehicle = '',
    this.from,
    this.to,
  });

  final DocumentTab tab;
  final String customer;
  final String vehicle;
  final DateTime? from;
  final DateTime? to;

  DocumentFilters copyWith({
    DocumentTab? tab,
    String? customer,
    String? vehicle,
    DateTime? from,
    DateTime? to,
    bool clearDates = false,
  }) => DocumentFilters(
    tab: tab ?? this.tab,
    customer: customer ?? this.customer,
    vehicle: vehicle ?? this.vehicle,
    from: clearDates ? null : from ?? this.from,
    to: clearDates ? null : to ?? this.to,
  );
}

class SalesDocumentsRepository {
  SalesDocumentsRepository(this._api, this._context);

  static const pageSize = 20;

  final ApiClient _api;
  final AppContext _context;

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Misma lógica de pestañas que la web (buildDocumentFilterParams).
  Map<String, String?> buildParams(DocumentFilters f, {int page = 1}) {
    final kinds = _context.documentKinds;
    String ids(Iterable<DocumentKind> list) => list.map((k) => k.id).join(',');
    final preIds = kinds.where(
      (k) =>
          k.kindGroup == 'PRE_DOCUMENT' ||
          k.code == 'QUOTATION' ||
          k.code == 'SALES_ORDER',
    );
    final params = <String, String?>{
      'page': '$page',
      'per_page': '$pageSize',
      'branch_id': _context.branchId?.toString(),
      'customer': f.customer.trim(),
      'vehicle': _context.workshopEnabled ? f.vehicle.trim() : null,
      'issue_date_from': f.from == null ? null : _date(f.from!),
      'issue_date_to': f.to == null ? null : _date(f.to!),
    };
    switch (f.tab) {
      case DocumentTab.all:
        break;
      case DocumentTab.tributary:
        params['document_kind_id'] = ids(kinds.where((k) => k.isTributary));
      case DocumentTab.orders:
        params['document_kind'] = 'QUOTATION,SALES_ORDER';
      case DocumentTab.pending:
        params['document_kind_id'] = ids(preIds);
        params['conversion_state'] = 'PENDING';
      case DocumentTab.converted:
        params['document_kind_id'] = ids(preIds);
        params['conversion_state'] = 'CONVERTED';
    }
    return params;
  }

  Future<DocumentPage> fetch(DocumentFilters filters, {int page = 1}) async {
    final body = await _api.get(
      '/api/sales/commercial-documents',
      buildParams(filters, page: page),
    );
    final data = body['data'];
    final meta = (body['meta'] as Map?) ?? const {};
    final items = data is List
        ? data
              .whereType<Map>()
              .map((r) => SaleDocument.fromJson(r.cast<String, dynamic>()))
              .toList()
        : <SaleDocument>[];
    return DocumentPage(
      items,
      toIntOrNull(meta['page']) ?? page,
      toIntOrNull(meta['last_page']) ?? page,
      toIntOrNull(meta['total']) ?? items.length,
    );
  }

  Future<List<SaleDocumentItem>> fetchItems(int documentId) async {
    final body = await _api.get('/api/sales/commercial-documents/$documentId');
    final data = body['data'];
    if (data is! Map || data['items'] is! List) {
      throw const ApiException(
        'El detalle del comprobante no contiene productos para imprimir.',
      );
    }
    final items = (data['items'] as List)
        .whereType<Map>()
        .map((item) => SaleDocumentItem.fromJson(item.cast<String, dynamic>()))
        .toList();
    if (items.isEmpty) {
      throw const ApiException(
        'El comprobante no devolvió productos para incluir en el ticket.',
      );
    }
    return items;
  }
}
