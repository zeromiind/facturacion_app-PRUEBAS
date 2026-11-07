import '../api/api_client.dart';

class NamedOption {
  const NamedOption({required this.id, required this.code, required this.name});

  final int id;
  final String code;
  final String name;

  factory NamedOption.fromJson(Map<String, dynamic> json) => NamedOption(
    id: toIntOrNull(json['id']) ?? 0,
    code: (json['code'] ?? '').toString(),
    name: (json['name'] ?? json['label'] ?? '').toString(),
  );
}

class DocumentKind {
  const DocumentKind({
    required this.id,
    required this.code,
    required this.label,
    required this.kindGroup,
  });

  final int id;
  final String code;
  final String label;
  final String kindGroup;

  bool get isTributary => kindGroup != 'PRE_DOCUMENT';
  bool get isNote => kindGroup.startsWith('NOTE_');

  factory DocumentKind.fromJson(Map<String, dynamic> json) => DocumentKind(
    id: toIntOrNull(json['id']) ?? 0,
    code: (json['code'] ?? '').toString(),
    label: (json['label'] ?? json['code'] ?? '').toString(),
    kindGroup: (json['kind_group'] ?? '').toString(),
  );
}

class TaxCategory {
  const TaxCategory({required this.id, required this.ratePercent});

  final int id;
  final double ratePercent;

  factory TaxCategory.fromJson(Map<String, dynamic> json) => TaxCategory(
    id: toIntOrNull(json['id']) ?? 0,
    ratePercent: toNum(json['rate_percent']).toDouble(),
  );
}

class SeriesOption {
  const SeriesOption({required this.series, required this.nextNumber});

  final String series;
  final int nextNumber;

  String get label => '$series (N° $nextNumber)';
}

class CurrencyOption {
  const CurrencyOption({
    required this.id,
    required this.symbol,
    required this.isDefault,
  });

  final int id;
  final String symbol;
  final bool isDefault;

  factory CurrencyOption.fromJson(Map<String, dynamic> json) => CurrencyOption(
    id: toIntOrNull(json['id']) ?? 0,
    symbol: (json['symbol'] ?? 'S/').toString(),
    isDefault: toBool(json['is_default']),
  );
}

/// Contexto operativo + catálogos que la web carga al iniciar sesión.
class AppContext {
  const AppContext({
    required this.branchId,
    required this.warehouseId,
    required this.cashRegisterId,
    required this.verticalName,
    required this.companyName,
    required this.features,
    required this.documentKinds,
    required this.paymentMethods,
    required this.taxCategories,
    required this.currencies,
    required this.unitId,
    this.verticalCode = '',
    this.roleCode = '',
    this.roleProfile = '',
    this.permissions = const {},
    this.restaurantQuickSaleEnabled = false,
  });

  final String verticalCode;
  final String roleCode;
  final String roleProfile;

  /// moduleCode (SALES, INVENTORY, APPCFG...) -> can_view.
  final Map<String, bool> permissions;
  final bool restaurantQuickSaleEnabled;

  bool get isAdmin => roleCode.toUpperCase().contains('ADMIN');
  bool get isCashier {
    final code = roleCode.toUpperCase();
    return roleProfile.toUpperCase() == 'CASHIER' ||
        code.contains('CAJA') ||
        code.contains('CAJER') ||
        code.contains('CASHIER');
  }

  bool get isSeller {
    final code = roleCode.toUpperCase();
    final profile = roleProfile.toUpperCase();
    return profile == 'SELLER' ||
        profile.contains('VENDED') ||
        code.contains('VENDED') ||
        code.contains('SELLER');
  }

  /// El vendedor solo emite pedidos y el cajero los convierte en comprobantes.
  bool get sellerToCashier => features.contains('SALES_SELLER_TO_CASHIER');

  final int? branchId;
  final int? warehouseId;
  final int? cashRegisterId;
  final String verticalName;
  final String companyName;
  final Set<String> features;
  final List<DocumentKind> documentKinds;
  final List<NamedOption> paymentMethods;
  final List<TaxCategory> taxCategories;
  final List<CurrencyOption> currencies;
  final int? unitId;

  bool isTributaryDocument(String code) {
    for (final kind in documentKinds) {
      if (kind.code == code) return kind.isTributary;
    }
    return false;
  }

  /// Mismo flag que usa la web para activar los datos de taller.
  bool get workshopEnabled =>
      features.contains('SALES_WORKSHOP_MULTI_VEHICLE') ||
      verticalCode.toUpperCase() == 'WORKSHOP';

  CurrencyOption? get defaultCurrency => currencies.isEmpty
      ? null
      : currencies.firstWhere((c) => c.isDefault, orElse: () => currencies[0]);

  TaxCategory? get defaultTax => taxCategories.isEmpty
      ? null
      : taxCategories.firstWhere(
          (t) => t.ratePercent > 0,
          orElse: () => taxCategories[0],
        );

  static Future<AppContext> load(ApiClient api) async {
    final operational = await api.get('/api/appcfg/operational-context');
    final selected = (operational['selected'] as Map?) ?? const {};
    final vertical = (operational['active_vertical'] as Map?) ?? const {};
    final rawVerticalCode = (vertical['code'] ??
            operational['active_vertical_code'] ??
            selected['vertical_code'] ??
            '')
        .toString()
        .trim()
        .toUpperCase();
    final verticalName = (vertical['name'] ?? '').toString().trim();
    final verticalCode = rawVerticalCode.isNotEmpty
        ? rawVerticalCode
        : switch (verticalName.toUpperCase()) {
            'RESTAURANTE' || 'RESTAURANT' => 'RESTAURANT',
            _ => '',
          };
    final branches = _list(operational['branches']);
    final warehouses = _list(operational['warehouses']);
    final cashRegisters = _list(operational['cash_registers']);

    final branchId =
        toIntOrNull(selected['branch_id']) ??
        (branches.isEmpty ? null : toIntOrNull(branches.first['id']));
    final warehouseId =
        toIntOrNull(selected['warehouse_id']) ??
        _firstId(
          warehouses.where(
            (w) =>
                w['branch_id'] == null ||
                toIntOrNull(w['branch_id']) == branchId,
          ),
        ) ??
        _firstId(warehouses);
    final cashRegisterId =
        toIntOrNull(selected['cash_register_id']) ?? _firstId(cashRegisters);

    final results = await Future.wait([
      api.get('/api/sales/lookups', {'branch_id': branchId?.toString()}),
      api.get('/api/auth/me'),
      if (verticalCode == 'RESTAURANT' &&
          branchId != null)
        api.get('/api/restaurant/bootstrap', {
          'branch_id': branchId.toString(),
          if (warehouseId != null) 'warehouse_id': warehouseId.toString(),
          'mode': 'orders_minimal',
        })
      else
        Future.value(<String, dynamic>{}),
    ]);
    final lookups = results[0];
    final me = (results[1]['user'] as Map?) ?? const {};
    final restaurantBootstrap = results[2];
    final rawPermissions = (me['permissions'] as Map?) ?? const {};
    final permissions = <String, bool>{
      for (final entry in rawPermissions.entries)
        entry.key.toString(): entry.value is Map
            ? toBool((entry.value as Map)['can_view'])
            : false,
    };

    final features = <String>{
      for (final row in _list(lookups['commerce_features']))
        if (toBool(row['is_enabled'])) (row['feature_code'] ?? '').toString(),
    };
    final units = _list(lookups['units']);
    final company = (operational['company'] as Map?) ?? const {};
    final profile = (lookups['company_profile'] as Map?) ?? const {};

    return AppContext(
      branchId: branchId,
      warehouseId: warehouseId,
      cashRegisterId: cashRegisterId,
      verticalName: verticalName,
      verticalCode: verticalCode,
      roleCode: (me['role_code'] ?? '').toString(),
      roleProfile: (me['role_profile'] ?? '').toString(),
      permissions: permissions,
      restaurantQuickSaleEnabled: toBool(
        restaurantBootstrap['restaurant_quick_sale_enabled'],
      ),
      companyName:
          (profile['trade_name'] ??
                  profile['legal_name'] ??
                  company['trade_name'] ??
                  company['legal_name'] ??
                  '')
              .toString(),
      features: features,
      documentKinds: _list(
        lookups['document_kinds'],
      ).map(DocumentKind.fromJson).toList(),
      paymentMethods: _list(
        lookups['payment_methods'],
      ).map(NamedOption.fromJson).toList(),
      taxCategories: _list(
        lookups['tax_categories'],
      ).map(TaxCategory.fromJson).toList(),
      currencies: _list(
        lookups['currencies'],
      ).map(CurrencyOption.fromJson).toList(),
      unitId: units.isEmpty ? null : toIntOrNull(units.first['id']),
    );
  }

  static List<Map<String, dynamic>> _list(Object? value) => value is List
      ? value.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
      : const [];

  static int? _firstId(Iterable<Map<String, dynamic>> rows) =>
      rows.isEmpty ? null : toIntOrNull(rows.first['id']);
}
