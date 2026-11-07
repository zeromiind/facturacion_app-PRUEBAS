import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/api/api_client.dart';
import '../../../core/session/app_context.dart';
import '../../../core/time/lima_time.dart';
import '../../customers/data/customers_repository.dart';
import '../../customers/domain/customer.dart';

class RestaurantOrdersPage extends StatefulWidget {
  const RestaurantOrdersPage({
    required this.api,
    required this.appContext,
    required this.customers,
    required this.onUnauthorized,
    this.onPaymentClosed,
    this.showAppBar = true,
    super.key,
  });

  final ApiClient api;
  final AppContext appContext;
  final CustomersRepository customers;
  final VoidCallback onUnauthorized;
  final VoidCallback? onPaymentClosed;
  final bool showAppBar;

  @override
  State<RestaurantOrdersPage> createState() => _RestaurantOrdersPageState();
}

class _RestaurantOrdersPageState extends State<RestaurantOrdersPage> {
  static const _guestName = 'CLIENTES VARIOS';

  final _customerSearch = TextEditingController();
  final _menuSearch = TextEditingController();
  final _notes = TextEditingController();
  final _cart = <int, _MenuItem>{};
  final _quickSaleKinds = <int, String>{};
  final _quickSaleGuestCounts = <int, int>{};
  Timer? _menuSearchTimer;

  List<Map<String, dynamic>> _tables = const [];
  List<Map<String, dynamic>> _orders = const [];
  List<Map<String, dynamic>> _menu = const [];
  List<Map<String, dynamic>> _menuSearchResults = const [];
  String? _selectedMenuCategory;
  List<Map<String, dynamic>> _series = const [];
  List<Map<String, dynamic>> _paymentMethods = const [];
  List<Customer> _customerSuggestions = const [];
  Map<String, dynamic>? _selectedTable;
  Customer? _customer;
  bool? _quickSaleEnabledFromBootstrap;
  bool _selectingGuestCount = false;
  bool _viewingTableOrders = false;
  int _guestCount = 1;
  int? _currencyId;
  int? _defaultCashPaymentMethodId;
  int? _paymentMethodId;
  double _taxRate = 0;
  bool _pricesIncludeTax = false;
  bool _loading = true;
  bool _loadingFeaturedMenu = true;
  bool _searchingMenu = false;
  bool _loadingGuestCustomer = false;
  bool _submitting = false;
  bool _quickSaleCartSheetOpen = false;
  String? _error;
  String? _menuSearchError;
  String? _guestCustomerError;
  int _checkoutOrderId = 0;
  int? _editingOrderId;
  int? _loadingOrderId;
  int _menuSearchSequence = 0;

  AppContext get _ctx => widget.appContext;
  bool get _quickSale =>
      _quickSaleEnabledFromBootstrap ?? _ctx.restaurantQuickSaleEnabled;
  String get _currencySymbol => _ctx.defaultCurrency?.symbol ?? 'S/';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _menuSearchTimer?.cancel();
    _customerSearch.dispose();
    _menuSearch.dispose();
    _notes.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _rows(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map((row) => row.cast<String, dynamic>())
            .toList()
      : const [];

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final branchId = _ctx.branchId;
      if (branchId == null) {
        throw const ApiException(
          'Selecciona una sucursal para ver los pedidos.',
        );
      }
      final results = await Future.wait([
        widget.api.get('/api/restaurant/bootstrap', {
          'branch_id': '$branchId',
          'warehouse_id': _ctx.warehouseId?.toString(),
          'mode': 'orders_minimal',
        }),
        widget.api.get('/api/restaurant/tables', {'branch_id': '$branchId'}),
        widget.api.get('/api/restaurant/orders', {
          'branch_id': '$branchId',
          'per_page': '50',
          'include_items': '1',
          'include_meta': '1',
        }),
      ]);
      final bootstrap = results[0];
      final rawDocumentKindIds = bootstrap['document_kind_ids'];
      final documentKindIds = rawDocumentKindIds is Map
          ? rawDocumentKindIds.cast<String, dynamic>()
          : const <String, dynamic>{};
      final salesOrderKindId = toIntOrNull(documentKindIds['SALES_ORDER']);
      final series = _rows(bootstrap['series_numbers'])
          .where(
            (row) =>
                toBool(row['is_enabled']) &&
                ((salesOrderKindId != null &&
                        toIntOrNull(row['document_kind_id']) ==
                            salesOrderKindId) ||
                    row['document_kind']?.toString().toUpperCase() ==
                        'SALES_ORDER'),
          )
          .toList();
      final methods = _rows(bootstrap['payment_methods']);
      final currencies = _rows(bootstrap['currencies']);
      final cashMethod = methods.where((row) {
        final key = '${row['code'] ?? ''} ${row['name'] ?? ''}'.toUpperCase();
        return key.contains('EFECT') ||
            key.contains('CASH') ||
            key.contains('CONTADO');
      });
      final defaultCurrency = currencies.where(
        (row) => toBool(row['is_default']),
      );
      final quickSaleEnabled = toBool(
        bootstrap['restaurant_quick_sale_enabled'],
      );
      final orders = _rows(results[2]['data']);
      if (!mounted) return;
      setState(() {
        _series = series;
        _paymentMethods = methods;
        _defaultCashPaymentMethodId = toIntOrNull(
          cashMethod.firstOrNull?['id'],
        );
        _paymentMethodId =
            _defaultCashPaymentMethodId ??
            toIntOrNull(methods.firstOrNull?['id']);
        _currencyId = toIntOrNull(
          defaultCurrency.firstOrNull?['id'] ?? currencies.firstOrNull?['id'],
        );
        _taxRate = toNum(bootstrap['active_igv_rate_percent']).toDouble();
        _pricesIncludeTax = toBool(bootstrap['restaurant_price_includes_igv']);
        _quickSaleEnabledFromBootstrap = quickSaleEnabled;
        _tables = _rows(results[1]['data']);
        _orders = quickSaleEnabled
            ? orders
                  .where(
                    (order) =>
                        _isOpenOrder(order) ||
                        _isTodayInLima(
                          order['issue_at'] ?? order['created_at'],
                        ),
                  )
                  .toList()
            : orders;
        _menu = const [];
        _selectedMenuCategory = null;
      });
      if (_quickSale) unawaited(_loadGuestCustomer());
      unawaited(_loadFeaturedMenu());
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        widget.onUnauthorized();
      } else if (mounted) {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadFeaturedMenu() async {
    try {
      final response = await widget.api.get('/api/inventory/products', {
        'warehouse_id': _ctx.warehouseId?.toString(),
        'status': '1',
        'limit': '200',
      });
      if (!mounted) return;
      setState(() {
        _menu = _sellableMenuProducts(response['data']);
        _selectedMenuCategory = null;
        _menuSearchError = null;
      });
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        widget.onUnauthorized();
      } else if (mounted) {
        setState(() => _menuSearchError = error.message);
      }
    } finally {
      if (mounted) setState(() => _loadingFeaturedMenu = false);
    }
  }

  Future<void> _loadGuestCustomer() async {
    setState(() {
      _loadingGuestCustomer = true;
      _guestCustomerError = null;
    });
    try {
      final nameMatches = await widget.customers.autocomplete(_guestName);
      final defaultCustomer = nameMatches
          .where(
            (customer) =>
                customer.isActive &&
                customer.name.trim().toUpperCase() == _guestName,
          )
          .firstOrNull;

      if (defaultCustomer == null) {
        if (mounted) {
          setState(
            () => _guestCustomerError = 'No se encontró el cliente CLIENTES VARIOS en la base de datos de la empresa.',
          );
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _customer = defaultCustomer;
        _customerSearch.text = defaultCustomer.name;
      });
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        widget.onUnauthorized();
      } else if (mounted) {
        setState(() => _guestCustomerError = error.message);
      }
    } finally {
      if (mounted) setState(() => _loadingGuestCustomer = false);
    }
  }

  Future<void> _searchCustomers(String value) async {
    if (_quickSale || value.trim().length < 2) {
      setState(() => _customerSuggestions = const []);
      return;
    }
    try {
      final rows = await widget.customers.autocomplete(value);
      if (mounted && _customerSearch.text == value) {
        setState(() => _customerSuggestions = rows);
      }
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        widget.onUnauthorized();
      } else if (mounted) {
        setState(() => _error = error.message);
      }
    }
  }

  void _addMenuItem(Map<String, dynamic> row) {
    final id = toIntOrNull(row['id']);
    if (id == null) return;
    setState(() {
      final existing = _cart[id];
      if (existing == null) {
        _cart[id] = _MenuItem.fromJson(row);
      } else {
        existing.quantity++;
      }
      _menuSearch.clear();
      _menuSearchResults = const [];
      _menuSearchError = null;
      _menuSearchTimer?.cancel();
      _menuSearchSequence++;
    });
  }

  void _searchMenuProducts(String value) {
    _menuSearchTimer?.cancel();
    final query = value.trim();
    final requestSequence = ++_menuSearchSequence;
    if (query.length < 2) {
      setState(() {
        _menuSearchResults = const [];
        _searchingMenu = false;
        _menuSearchError = null;
      });
      return;
    }

    setState(() {
      _searchingMenu = true;
      _menuSearchError = null;
    });
    _menuSearchTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final response = await widget.api.get('/api/inventory/products', {
          'search': query,
          'warehouse_id': _ctx.warehouseId?.toString(),
          'status': '1',
          'limit': '24',
          'autocomplete': 'true',
        });
        if (!mounted ||
            requestSequence != _menuSearchSequence ||
            _menuSearch.text.trim() != query) {
          return;
        }
        setState(() {
          _menuSearchResults = _sellableMenuProducts(response['data']);
          _menuSearchError = null;
        });
      } on ApiException catch (error) {
        if (requestSequence != _menuSearchSequence || !mounted) return;
        if (error.isUnauthorized) {
          widget.onUnauthorized();
        } else {
          setState(() => _menuSearchError = error.message);
        }
      } finally {
        if (requestSequence == _menuSearchSequence && mounted) {
          setState(() => _searchingMenu = false);
        }
      }
    });
  }

  List<Map<String, dynamic>> _sellableMenuProducts(Object? value) {
    final rows = _rows(value);
    return rows.where((row) {
      final nature = (row['product_nature'] ?? '').toString().toUpperCase();
      final metadata = [
        row['category_name'],
        row['line_name'],
        row['name'],
      ].join(' ').toLowerCase();
      return nature != 'SUPPLY' &&
          !metadata.contains('insumo') &&
          !metadata.contains('ingrediente') &&
          !metadata.contains('materia prima');
    }).toList();
  }

  double _round2(double value) => double.parse(value.toStringAsFixed(2));

  bool _isTodayInLima(Object? value) {
    final orderDate = parseApiDateToLima(value?.toString());
    if (orderDate == null) return false;
    final today = limaNow();
    return orderDate.year == today.year &&
        orderDate.month == today.month &&
        orderDate.day == today.day;
  }

  bool _isOpenOrder(Map<String, dynamic> order) {
    final status = (order['status'] ?? '').toString().toUpperCase();
    return !const {'ISSUED', 'VOID', 'CANCELED', 'CANCELLED'}.contains(status);
  }

  Widget _buildMenu() {
    final query = _menuSearch.text.trim().toLowerCase();
    final sourceMenu = query.length >= 2 ? _menuSearchResults : _menu;
    final filteredMenu = sourceMenu.where((product) {
      final name = (product['name'] ?? '').toString().toLowerCase();
      final code = (product['sku'] ?? product['barcode'] ?? '')
          .toString()
          .toLowerCase();
      return query.isEmpty || name.contains(query) || code.contains(query);
    }).toList();
    if (query.length < 2 && _loadingFeaturedMenu) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_searchingMenu) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_menuSearchError != null) {
      return _ErrorBanner(message: _menuSearchError!);
    }
    if (filteredMenu.isEmpty) {
      return const _EmptyCard(
        icon: Icons.restaurant_menu,
        message:
            'No hay productos disponibles. Revisa el catálogo o la búsqueda.',
      );
    }

    final visibleMenu = filteredMenu.take(query.length >= 2 ? 24 : 12).toList();
    return Column(
      children: [
        for (final product in visibleMenu)
          Card(
            margin: const EdgeInsets.only(bottom: 4),
            child: ListTile(
              leading: const CircleAvatar(
                radius: 18,
                child: Icon(Icons.restaurant_menu, size: 18),
              ),
              title: Text(
                (product['name'] ?? '').toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${product['sku'] ?? product['barcode'] ?? 'Producto'} · $_currencySymbol ${toNum(product['sale_price']).toStringAsFixed(2)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.add_circle_outline),
              onTap: () => _addMenuItem(product),
            ),
          ),
        if (visibleMenu.length < filteredMenu.length)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              query.isEmpty
                  ? 'Mostrando 12 de ${filteredMenu.length}. Usa la búsqueda para encontrar otro producto.'
                  : 'Mostrando ${visibleMenu.length} de ${filteredMenu.length} resultados.',
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  Widget _buildQuickSaleMenu() {
    final query = _menuSearch.text.trim().toLowerCase();
    final sourceMenu = query.length >= 2 ? _menuSearchResults : _menu;
    final categories =
        _menu
            .map(
              (product) => (product['category_name'] ?? '').toString().trim(),
            )
            .where((category) => category.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final products = sourceMenu.where((product) {
      final category = (product['category_name'] ?? '').toString().trim();
      if (_selectedMenuCategory != null && category != _selectedMenuCategory) {
        return false;
      }
      if (query.isEmpty || query.length >= 2) return true;
      final name = (product['name'] ?? '').toString().toLowerCase();
      final code = (product['sku'] ?? product['barcode'] ?? '')
          .toString()
          .toLowerCase();
      return name.contains(query) || code.contains(query);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _menuSearch,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Buscar plato o bebida',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _menuSearch.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpiar búsqueda',
                    onPressed: () {
                      _menuSearch.clear();
                      _searchMenuProducts('');
                    },
                    icon: const Icon(Icons.close),
                  ),
          ),
          onChanged: _searchMenuProducts,
        ),
        if (categories.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final category in ['Todos', ...categories])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(category),
                      selected: category == 'Todos'
                          ? _selectedMenuCategory == null
                          : _selectedMenuCategory == category,
                      onSelected: (_) => setState(
                        () => _selectedMenuCategory = category == 'Todos'
                            ? null
                            : category,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (_searchingMenu)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
        if (_menuSearchError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _ErrorBanner(message: _menuSearchError!),
          ),
        if (_loadingFeaturedMenu && _menu.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (products.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _EmptyCard(
              icon: Icons.restaurant_menu,
              message: query.length >= 2 && !_searchingMenu
                  ? 'No se encontraron platos o bebidas.'
                  : 'No hay productos disponibles en esta categoría.',
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 600
                  ? 4
                  : constraints.maxWidth >= 340
                  ? 3
                  : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                itemCount: products.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.82,
                ),
                itemBuilder: (context, index) {
                  final product = products[index];
                  final id = toIntOrNull(product['id']);
                  final inCart = id == null ? null : _cart[id];
                  final imageUrl = (product['image_url'] ?? '').toString();
                  final colors = [
                    Theme.of(context).colorScheme.primaryContainer,
                    Theme.of(context).colorScheme.secondaryContainer,
                    Theme.of(context).colorScheme.tertiaryContainer,
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                  ];
                  final color = colors[index % colors.length];
                  return Material(
                    color: color,
                    borderRadius: BorderRadius.circular(14),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _addMenuItem(product),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Column(
                              children: [
                                Expanded(
                                  child: Center(
                                    child: imageUrl.startsWith('http')
                                        ? Image.network(
                                            imageUrl,
                                            width: double.infinity,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, _, _) => Icon(
                                              Icons.restaurant_menu,
                                              size: 38,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                          )
                                        : Icon(
                                            Icons.restaurant_menu,
                                            size: 38,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                  ),
                                ),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    8,
                                    10,
                                    10,
                                  ),
                                  color: Theme.of(context).colorScheme.surface
                                      .withValues(alpha: 0.92),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        (product['name'] ?? 'Producto')
                                            .toString(),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '$_currencySymbol ${toNum(product['sale_price']).toStringAsFixed(2)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Positioned(
                            top: 6,
                            right: 6,
                            child: CircleAvatar(
                              radius: 16,
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .surface,
                              child: inCart == null
                                  ? Icon(
                                      Icons.add,
                                      size: 20,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                    )
                                  : Text(
                                      '${inCart.quantity}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
      ],
    );
  }

  double _lineTotal(_MenuItem item) {
    final base = item.quantity * item.price;
    return _round2(_pricesIncludeTax ? base : base * (1 + _taxRate / 100));
  }

  Future<void> _editQuickSaleItemPrice(
    _MenuItem item, {
    StateSetter? refreshSheet,
  }) async {
    if (!_quickSale) return;

    final formKey = GlobalKey<FormState>();
    final priceFieldKey = GlobalKey<FormFieldState<String>>();
    double? parsePrice(String? value) {
      final price = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
      return price != null && price.isFinite && price >= 0 ? price : null;
    }

    final price = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Editar precio de ${item.name}'),
        content: Form(
          key: formKey,
          child: TextFormField(
            key: priceFieldKey,
            initialValue: item.price.toStringAsFixed(2),
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Precio unitario',
              prefixText: '$_currencySymbol ',
            ),
            validator: (value) => parsePrice(value) == null
                ? 'Ingresa un precio válido mayor o igual a cero.'
                : null,
            onFieldSubmitted: (_) {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(dialogContext)
                    .pop(parsePrice(priceFieldKey.currentState?.value));
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(dialogContext)
                    .pop(parsePrice(priceFieldKey.currentState?.value));
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (price == null || !mounted) return;
    setState(() => item.price = price);
    refreshSheet?.call(() {});
  }

  Future<void> _createOrder() async {
    final table = _selectedTable;
    final branchId = _ctx.branchId;
    final editingOrderId = _editingOrderId;
    if (branchId == null ||
        (table == null && editingOrderId == null) ||
        (_quickSale && _selectingGuestCount && editingOrderId == null)) {
      setState(() => _error = 'Selecciona una mesa para continuar.');
      return;
    }
    if (_cart.isEmpty) {
      setState(() => _error = 'Agrega al menos un producto al pedido.');
      return;
    }
    if (editingOrderId == null &&
        (_series.isEmpty ||
            _currencyId == null ||
            _defaultCashPaymentMethodId == null)) {
      setState(
        () => _error = 'Configura serie, moneda y medio de pago efectivo.',
      );
      return;
    }
    if (_customer == null) {
      setState(() {
        _error = _quickSale
            ? 'No se pudo cargar $_guestName. Revisa el cliente configurado.'
            : 'Busca y selecciona un cliente.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final items = _cart.values.map((item) {
        final gross = _lineTotal(item);
        final netUnit = _pricesIncludeTax && _taxRate > 0
            ? _round2(item.price / (1 + _taxRate / 100))
            : item.price;
        final subtotal = _pricesIncludeTax
            ? _round2(item.quantity * netUnit)
            : _round2(item.quantity * item.price);
        return <String, dynamic>{
          'product_id': item.id,
          'description': item.name,
          'quantity': item.quantity,
          'unit_price': netUnit,
          'unit_id': item.unitId,
          'tax_rate': _taxRate,
          'subtotal': subtotal,
          'tax_total': _round2(gross - subtotal),
          'total': gross,
        };
      }).toList();
      if (editingOrderId != null) {
        await widget.api.put(
          '/api/sales/commercial-documents/$editingOrderId',
          {
            'customer_id': _customer!.id,
            'notes': _notes.text.trim(),
            'items': [
              for (var index = 0; index < items.length; index++)
                {
                  'line_no': index + 1,
                  'product_id': items[index]['product_id'],
                  'description': items[index]['description'],
                  'qty': items[index]['quantity'],
                  'unit_price': items[index]['unit_price'],
                  'unit_id': items[index]['unit_id'],
                  'subtotal': items[index]['subtotal'],
                  'tax_total': items[index]['tax_total'],
                  'total': items[index]['total'],
                },
            ],
          },
        );
      } else {
        final result = await widget.api.post('/api/restaurant/orders', {
          'branch_id': branchId,
          'warehouse_id': _ctx.warehouseId,
          'table_id': toIntOrNull(table?['id']),
          'table_label': '${table?['code'] ?? ''} ${table?['name'] ?? ''}'
              .trim(),
          'series': _series.first['series'],
          'currency_id': _currencyId,
          'payment_method_id': _defaultCashPaymentMethodId,
          'customer_id': _customer!.id,
          'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          'items': items,
        });
        if (!mounted) return;
        final orderId = toIntOrNull(result['id']);
        if (orderId != null && _quickSale) {
          _quickSaleKinds[orderId] = _selectedNewOrderKind;
          _quickSaleGuestCounts[orderId] = _guestCount;
        }
      }
      if (!mounted) return;
      if (_quickSaleCartSheetOpen) {
        _quickSaleCartSheetOpen = false;
        Navigator.of(context).pop();
      }
      final wasEditing = editingOrderId != null;
      setState(() {
        _cart.clear();
        _notes.clear();
        if (_quickSale && editingOrderId == null) {
          _viewingTableOrders = true;
          _selectingGuestCount = false;
        } else {
          _selectedTable = null;
        }
        _editingOrderId = null;
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              wasEditing ? 'Pedido actualizado.' : 'Pedido registrado.',
            ),
          ),
        );
      }
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        widget.onUnauthorized();
      } else if (mounted) {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _editQuickSaleOrder(Map<String, dynamic> order) async {
    final id = toIntOrNull(order['id']);
    if (!_quickSale ||
        id == null ||
        (order['status'] ?? '').toString().toUpperCase() != 'DRAFT' ||
        _loadingOrderId != null ||
        _checkoutOrderId != 0) {
      return;
    }

    if (_cart.isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Descartar cambios en curso'),
          content: const Text(
            'Si editas este pedido, se perderán los productos del formulario actual.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }

    setState(() {
      _loadingOrderId = id;
      _error = null;
    });
    try {
      var sourceOrder = order;
      var items = _rows(order['items']);
      if (items.isEmpty) {
        final response = await widget.api.get('/api/restaurant/orders/$id');
        final detail = response['data'];
        if (detail is Map) {
          sourceOrder = detail.cast<String, dynamic>();
          items = _rows(sourceOrder['items']);
        }
      }
      if (items.isEmpty) {
        throw const ApiException('El pedido no tiene productos para editar.');
      }

      final tableId = toIntOrNull(sourceOrder['table_id']);
      final table = _tables.where((row) => toIntOrNull(row['id']) == tableId);
      final tableLabel = (sourceOrder['table_label'] ?? 'Mesa').toString();
      final cart = <int, _MenuItem>{};
      for (final item in items) {
        final productId = toIntOrNull(item['product_id']);
        if (productId == null) continue;
        final quantity = toNum(item['quantity']).round().clamp(1, 999999);
        final unitPrice = toNum(item['unit_price']).toDouble();
        final storedTotal = toNum(item['total']).toDouble();
        final displayPrice = _pricesIncludeTax
            ? storedTotal > 0
                  ? storedTotal / quantity
                  : unitPrice * (1 + _taxRate / 100)
            : unitPrice;
        cart[productId] = _MenuItem(
          id: productId,
          name: (item['description'] ?? 'Producto').toString(),
          price: displayPrice,
          unitId: toIntOrNull(item['unit_id']),
        )..quantity = quantity;
      }
      if (cart.isEmpty) {
        throw const ApiException('El pedido no tiene productos editables.');
      }
      if (!mounted) return;
      setState(() {
        _editingOrderId = id;
        _viewingTableOrders = false;
        _selectingGuestCount = false;
        _selectedTable =
            table.firstOrNull ??
            {'id': tableId, 'code': tableLabel, 'name': tableLabel};
        _notes.text = (sourceOrder['notes'] ?? '').toString();
        _cart
          ..clear()
          ..addAll(cart);
        _menuSearch.clear();
        _menuSearchResults = const [];
      });
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        widget.onUnauthorized();
      } else if (mounted) {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted) setState(() => _loadingOrderId = null);
    }
  }

  void _cancelOrderEdit() {
    setState(() {
      _editingOrderId = null;
      _selectedTable = null;
      _cart.clear();
      _notes.clear();
    });
  }

  Future<void> _checkout(Map<String, dynamic> order) async {
    final id = toIntOrNull(order['id']);
    if (id == null || _checkoutOrderId != 0) return;
    if (_quickSale && _ctx.cashRegisterId == null) {
      setState(() => _error = 'Selecciona una caja para registrar el cobro.');
      return;
    }
    if (_quickSale && _paymentMethodId == null) {
      setState(() => _error = 'Selecciona un medio de pago para continuar.');
      return;
    }
    final kind = _quickSaleKinds[id] ?? 'SALES_ORDER';
    setState(() {
      _checkoutOrderId = id;
      _error = null;
    });
    try {
      await widget.api.post('/api/restaurant/orders/$id/checkout', {
        'target_document_kind': kind,
        'cash_register_id': _ctx.cashRegisterId,
        'payment_method_id': _paymentMethodId,
      });
      if (_quickSale && mounted) {
        setState(() {
          _selectedTable = null;
          _viewingTableOrders = false;
          _selectingGuestCount = false;
        });
      }
      widget.onPaymentClosed?.call();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Pago cerrado para ${order['series']}-${order['number']}.',
            ),
          ),
        );
      }
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        widget.onUnauthorized();
      } else if (mounted) {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted) setState(() => _checkoutOrderId = 0);
    }
  }

  Widget _buildTables() {
    if (_tables.isEmpty) {
      return const _EmptyCard(
        icon: Icons.table_restaurant_outlined,
        message: 'No hay mesas registradas para esta sucursal.',
      );
    }
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final table in _tables)
          SizedBox(
            width: 155,
            child: _TableCard(
              table: table,
              selected:
                  toIntOrNull(table['id']) ==
                  toIntOrNull(_selectedTable?['id']),
              onTap: () => setState(() => _selectedTable = table),
            ),
          ),
      ],
    );
  }

  bool get _choosingQuickSaleTable =>
      _quickSale && _selectedTable == null && _editingOrderId == null;

  List<Map<String, dynamic>> get _selectedTableOrders {
    final tableId = toIntOrNull(_selectedTable?['id']);
    if (tableId == null) return const [];
    return _orders.where((order) {
      return toIntOrNull(order['table_id']) == tableId && _isOpenOrder(order);
    }).toList();
  }

  void _selectQuickSaleTable(Map<String, dynamic> table) {
    final status = (table['status'] ?? '').toString().toUpperCase();
    final tableId = toIntOrNull(table['id']);
    final hasActiveOrder = _orders.any((order) {
      return tableId != null &&
          toIntOrNull(order['table_id']) == tableId &&
          _isOpenOrder(order);
    });

    setState(() {
      _selectedTable = table;
      _selectedMenuCategory = null;
      _error = null;
      _cart.clear();
      _notes.clear();
      if (status == 'OCCUPIED' || hasActiveOrder) {
        _viewingTableOrders = true;
        _selectingGuestCount = false;
      } else {
        _viewingTableOrders = false;
        _selectingGuestCount = true;
        _guestCount = 1;
      }
    });
  }

  void _continueToQuickSaleMenu() {
    setState(() {
      _selectingGuestCount = false;
      _viewingTableOrders = false;
      _error = null;
    });
  }

  Widget _buildQuickSaleTableSelection() {
    final available = _tables
        .where(
          (table) =>
              (table['status'] ?? '').toString().toUpperCase() == 'AVAILABLE',
        )
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Selecciona una mesa',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          '$available disponibles · ${_tables.length} en total',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        if (_tables.isEmpty)
          const _EmptyCard(
            icon: Icons.table_restaurant_outlined,
            message: 'No hay mesas registradas para esta sucursal.',
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900
                  ? 5
                  : constraints.maxWidth >= 600
                  ? 4
                  : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _tables.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: columns == 5 ? 1.5 : 1.2,
                ),
                itemBuilder: (context, index) {
                  final table = _tables[index];
                  return _TableCard(
                    table: table,
                    selected: false,
                    onTap: () => _selectQuickSaleTable(table),
                  );
                },
              );
            },
          ),
      ],
    );
  }

  Widget _buildGuestCountSelection() {
    final tableName = (_selectedTable?['name'] ?? 'Mesa').toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '¿Cuántas personas?',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text('Indica los comensales para $tableName antes de abrir el menú.'),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton.filledTonal(
                  tooltip: 'Quitar una persona',
                  onPressed: _guestCount <= 1
                      ? null
                      : () => setState(() => _guestCount--),
                  icon: const Icon(Icons.remove),
                ),
                Column(
                  children: [
                    Text(
                      '$_guestCount',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const Text('personas'),
                  ],
                ),
                IconButton.filledTonal(
                  tooltip: 'Agregar una persona',
                  onPressed: () => setState(() => _guestCount++),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _continueToQuickSaleMenu,
            icon: const Icon(Icons.restaurant_menu),
            label: const Text('Continuar al menú'),
          ),
        ),
      ],
    );
  }

  Future<void> _backToQuickSaleTables() async {
    if (_editingOrderId != null) {
      _cancelOrderEdit();
      return;
    }
    if (_cart.isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Descartar pedido en curso'),
          content: const Text(
            'Si vuelves a la selección de mesas, se quitarán los productos agregados.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Seguir en el pedido'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Descartar'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    setState(() {
      _selectedTable = null;
      _selectingGuestCount = false;
      _viewingTableOrders = false;
      _cart.clear();
      _notes.clear();
      _selectedMenuCategory = null;
      _menuSearch.clear();
      _menuSearchResults = const [];
      _error = null;
    });
  }

  Future<void> _openQuickSaleCart() async {
    if (_cart.isEmpty) return;
    _quickSaleCartSheetOpen = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, refreshSheet) => FractionallySizedBox(
          heightFactor: 0.9,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
            ),
            child: _buildCart(refreshSheet: refreshSheet),
          ),
        ),
      ),
    );
    _quickSaleCartSheetOpen = false;
  }

  Widget _buildQuickSaleCartBar() {
    final itemCount = _cart.values.fold<int>(
      0,
      (count, item) => count + item.quantity,
    );
    final total = _cart.values.fold<double>(
      0,
      (sum, item) => sum + _lineTotal(item),
    );
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      itemCount == 1 ? '1 producto' : '$itemCount productos',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    Text(
                      '$_currencySymbol ${total.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _cart.isEmpty ? null : _openQuickSaleCart,
                icon: const Icon(Icons.arrow_forward),
                label: Text(
                  _editingOrderId == null ? 'Ver pedido' : 'Guardar pedido',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCart({StateSetter? refreshSheet}) {
    void updateCart(VoidCallback update) {
      setState(update);
      refreshSheet?.call(() {});
    }

    final total = _cart.values.fold<double>(
      0,
      (sum, item) => sum + _lineTotal(item),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _editingOrderId == null ? 'Detalle del pedido' : 'Editar pedido',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_editingOrderId != null) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _submitting ? null : _cancelOrderEdit,
                  child: const Text('Cancelar edición'),
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (_cart.isEmpty)
              const Text('Agrega platos o bebidas del menú.')
            else
              for (final item in _cart.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.name),
                  subtitle: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('${item.quantity} × '),
                      if (_quickSale)
                        InkWell(
                          onTap: _submitting
                              ? null
                              : () => _editQuickSaleItemPrice(
                                  item,
                                  refreshSheet: refreshSheet,
                                ),
                          child: Text(
                            '$_currencySymbol ${item.price.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      else
                        Text(
                          '$_currencySymbol ${item.price.toStringAsFixed(2)}',
                        ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Quitar una unidad',
                        onPressed: () => updateCart(() {
                          if (item.quantity > 1) {
                            item.quantity--;
                          } else {
                            _cart.remove(item.id);
                          }
                        }),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      IconButton(
                        tooltip: 'Agregar una unidad',
                        onPressed: () => updateCart(() => item.quantity++),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                ),
            const Divider(),
            Row(
              children: [
                const Expanded(child: Text('Total estimado')),
                Text(
                  '$_currencySymbol ${total.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_quickSale && _editingOrderId == null)
              DropdownButtonFormField<String>(
                initialValue: _selectedNewOrderKind,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Comprobante al cerrar',
                  prefixIcon: Icon(Icons.receipt_long_outlined),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'SALES_ORDER',
                    child: Text('Pedido de Venta'),
                  ),
                  DropdownMenuItem(value: 'RECEIPT', child: Text('Boleta')),
                  DropdownMenuItem(value: 'INVOICE', child: Text('Factura')),
                ],
                onChanged: (value) => setState(
                  () => _selectedNewOrderKind = value ?? 'SALES_ORDER',
                ),
              ),
            if (_quickSale && _editingOrderId == null)
              const SizedBox(height: 16),
            if (_quickSale) ...[
              const SizedBox(height: 12),
              _buildCustomerField(),
              if (_guestCustomerError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'No se pudo cargar $_guestName: $_guestCustomerError',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text('Comensales: $_guestCount'),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(
                labelText: 'Notas del pedido (opcional)',
                prefixIcon: Icon(Icons.edit_note),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed:
                  _submitting ||
                      (_quickSale &&
                          (_customer == null || _loadingGuestCustomer))
                  ? null
                  : _createOrder,
              icon: _submitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(
                _submitting
                    ? (_editingOrderId != null
                          ? 'Guardando cambios...'
                          : _quickSale
                          ? 'Registrando...'
                          : 'Enviando a cocina...')
                    : _editingOrderId != null
                    ? 'Guardar cambios'
                    : _quickSale
                    ? 'Registrar pedido'
                    : 'Enviar pedido a cocina',
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _selectedNewOrderKind = 'SALES_ORDER';

  Widget _buildCustomerField() {
    if (_quickSale) {
      return InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Cliente',
          prefixIcon: Icon(Icons.person_outline),
        ),
        child: Row(
          children: [
            Expanded(child: Text(_customer?.name ?? _guestName)),
            if (_loadingGuestCustomer)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            if (_guestCustomerError != null)
              IconButton(
                tooltip: 'Reintentar cliente',
                onPressed: _loadingGuestCustomer ? null : _loadGuestCustomer,
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
      );
    }
    return Column(
      children: [
        TextField(
          controller: _customerSearch,
          decoration: const InputDecoration(
            labelText: 'Buscar cliente',
            hintText: 'Nombre o documento',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: _searchCustomers,
        ),
        for (final customer in _customerSuggestions)
          ListTile(
            dense: true,
            title: Text(customer.name),
            subtitle: Text(customer.documentLabel),
            onTap: () => setState(() {
              _customer = customer;
              _customerSearch.text = customer.name;
              _customerSuggestions = const [];
            }),
          ),
        if (_customer != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() {
                _customer = null;
                _customerSearch.clear();
              }),
              icon: const Icon(Icons.close),
              label: Text('Quitar ${_customer!.name}'),
            ),
          ),
      ],
    );
  }

  Widget _buildOrderList() {
    final orders = _viewingTableOrders ? _selectedTableOrders : _orders;
    if (orders.isEmpty) {
      return _EmptyCard(
        icon: Icons.receipt_long_outlined,
        message: _viewingTableOrders
            ? 'No hay pedidos activos asociados a esta mesa.'
            : _quickSale
            ? 'Aún no hay pedidos de hoy.'
            : 'No hay pedidos activos.',
      );
    }
    return Column(
      children: [
        for (final order in orders)
          _OrderCard(
            order: order,
            quickSale: _quickSale,
            currencySymbol: _currencySymbol,
            guestCount: _quickSaleGuestCounts[toIntOrNull(order['id'])],
            paymentMethods: _paymentMethods,
            paymentMethodId: _paymentMethodId,
            onPaymentMethodChanged: (value) =>
                setState(() => _paymentMethodId = value),
            selectedDocumentKind:
                _quickSaleKinds[toIntOrNull(order['id'])] ?? 'SALES_ORDER',
            checkoutBusy: _checkoutOrderId == toIntOrNull(order['id']),
            editBusy: _loadingOrderId == toIntOrNull(order['id']),
            onDocumentKindChanged: (kind) {
              final id = toIntOrNull(order['id']);
              if (id != null) setState(() => _quickSaleKinds[id] = kind);
            },
            onCheckout: () => _checkout(order),
            onEdit: () => _editQuickSaleOrder(order),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedName = _selectedTable == null
        ? 'Selecciona una mesa'
        : '${_selectedTable!['code'] ?? ''} · ${_selectedTable!['name'] ?? ''}';
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: Text(_quickSale ? 'Pedidos rápidos' : 'Pedidos de salón'),
              actions: [
                IconButton(
                  tooltip: 'Actualizar',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            )
          : null,
      bottomNavigationBar:
          _quickSale &&
              !_choosingQuickSaleTable &&
              !_selectingGuestCount &&
              !_viewingTableOrders
          ? _buildQuickSaleCartBar()
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_choosingQuickSaleTable) ...[
                    if (_error != null) ...[
                      _ErrorBanner(message: _error!),
                      const SizedBox(height: 12),
                    ],
                    _buildQuickSaleTableSelection(),
                  ] else if (_quickSale && _selectingGuestCount) ...[
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Volver a mesas',
                          onPressed: _backToQuickSaleTables,
                          icon: const Icon(Icons.arrow_back),
                        ),
                        Expanded(
                          child: Text(
                            selectedName,
                            style: Theme.of(context).textTheme.titleLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (_error != null) ...[
                      _ErrorBanner(message: _error!),
                      const SizedBox(height: 12),
                    ],
                    _buildGuestCountSelection(),
                  ] else if (_quickSale && _viewingTableOrders) ...[
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Volver a mesas',
                          onPressed: _backToQuickSaleTables,
                          icon: const Icon(Icons.arrow_back),
                        ),
                        Expanded(
                          child: Text(
                            selectedName,
                            style: Theme.of(context).textTheme.titleLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (_error != null) ...[
                      _ErrorBanner(message: _error!),
                      const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'Pedido de ${_selectedTable?['name'] ?? 'la mesa'}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    _buildOrderList(),
                  ] else ...[
                    if (_quickSale)
                      Row(
                        children: [
                          IconButton(
                            tooltip: _editingOrderId == null
                                ? 'Cambiar mesa'
                                : 'Cancelar edición',
                            onPressed: _backToQuickSaleTables,
                            icon: const Icon(Icons.arrow_back),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              selectedName,
                              style: Theme.of(context).textTheme.titleLarge,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton(
                            onPressed: _backToQuickSaleTables,
                            child: const Text('Cambiar'),
                          ),
                        ],
                      )
                    else
                      const _ModeBanner(
                        title: 'Pedidos por mesa',
                        subtitle: 'Los pedidos se envían a cocina y se cobran al finalizar.',
                        icon: Icons.restaurant,
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      _ErrorBanner(message: _error!),
                    ],
                    if (_quickSale) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Chip(
                          avatar: const Icon(Icons.people_outline, size: 18),
                          label: Text('Comensales: $_guestCount'),
                        ),
                      ),
                    ],
                    if (!_quickSale) ...[
                      const SizedBox(height: 16),
                      Text(
                        '1. Mesa',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      _buildTables(),
                      const SizedBox(height: 8),
                      Text(
                        selectedName,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
                    if (!_quickSale) ...[
                      const SizedBox(height: 12),
                      Text(
                        '2. Cliente',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      _buildCustomerField(),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      _quickSale ? 'Menú' : '3. Menú',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (_quickSale)
                      _buildQuickSaleMenu()
                    else ...[
                      TextField(
                        controller: _menuSearch,
                        decoration: const InputDecoration(
                          hintText: 'Buscar plato o bebida',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: _searchMenuProducts,
                      ),
                      const SizedBox(height: 8),
                      _buildMenu(),
                    ],
                    if (!_quickSale) ...[
                      const SizedBox(height: 12),
                      _buildCart(),
                    ],
                    if (!_quickSale) ...[
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Pedidos activos',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          Text('${_orders.length}'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildOrderList(),
                    ],
                  ],
                ],
              ),
            ),
    );
  }
}

class _MenuItem {
  _MenuItem({
    required this.id,
    required this.name,
    required this.price,
    this.unitId,
  });

  factory _MenuItem.fromJson(Map<String, dynamic> row) => _MenuItem(
    id: toIntOrNull(row['id']) ?? 0,
    name: (row['name'] ?? '').toString(),
    price: toNum(row['sale_price']).toDouble(),
    unitId: toIntOrNull(row['unit_id']),
  );

  final int id;
  final String name;
  double price;
  final int? unitId;
  int quantity = 1;
}

class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.table,
    required this.selected,
    required this.onTap,
  });

  final Map<String, dynamic> table;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = (table['status'] ?? 'AVAILABLE').toString().toUpperCase();
    final disabled = status == 'DISABLED';
    final color = switch (status) {
      'OCCUPIED' => const Color(0xFFFFF1E5),
      'RESERVED' => const Color(0xFFFFF8D8),
      'DISABLED' => const Color(0xFFF0F2F1),
      _ => const Color(0xFFE9F5EE),
    };
    return Card(
      color: selected ? Theme.of(context).colorScheme.primaryContainer : color,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: disabled ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.table_restaurant_outlined,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 4),
              Text(
                (table['name'] ?? table['code'] ?? 'Mesa').toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                '${table['capacity'] ?? 0} personas · ${_statusLabel(status)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(String value) => switch (value) {
    'OCCUPIED' => 'Ocupada',
    'RESERVED' => 'Reservada',
    'DISABLED' => 'Inactiva',
    _ => 'Disponible',
  };
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.quickSale,
    required this.currencySymbol,
    required this.guestCount,
    required this.paymentMethods,
    required this.paymentMethodId,
    required this.onPaymentMethodChanged,
    required this.selectedDocumentKind,
    required this.checkoutBusy,
    required this.editBusy,
    required this.onDocumentKindChanged,
    required this.onCheckout,
    required this.onEdit,
  });

  final Map<String, dynamic> order;
  final bool quickSale;
  final String currencySymbol;
  final int? guestCount;
  final List<Map<String, dynamic>> paymentMethods;
  final int? paymentMethodId;
  final ValueChanged<int?> onPaymentMethodChanged;
  final String selectedDocumentKind;
  final bool checkoutBusy;
  final bool editBusy;
  final ValueChanged<String> onDocumentKindChanged;
  final VoidCallback onCheckout;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final status = (order['status'] ?? '').toString().toUpperCase();
    final isClosed =
        status == 'ISSUED' ||
        status == 'VOID' ||
        status == 'CANCELED' ||
        status == 'CANCELLED';
    final canEdit = status == 'DRAFT';
    final label = quickSale
        ? status == 'ISSUED'
              ? 'Pago cerrado'
              : isClosed
              ? 'Cancelado'
              : 'Pago pendiente'
        : _kitchenLabel((order['kitchen_status'] ?? '').toString());
    final rawItems = order['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map((row) => row.cast<String, dynamic>())
              .toList()
        : const <Map<String, dynamic>>[];
    final itemsTotal = items.fold<double>(
      0,
      (sum, item) => sum + toNum(item['total']).toDouble(),
    );
    final total = (items.isNotEmpty ? itemsTotal : toNum(order['total']))
        .toStringAsFixed(2);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${order['series'] ?? ''}-${order['number'] ?? ''}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(label: Text(label)),
              ],
            ),
            if ((order['table_label'] ?? '').toString().isNotEmpty)
              Text('Mesa ${order['table_label']}'),
            Text('Cliente: ${order['customer_name'] ?? '—'}'),
            if (guestCount != null) Text('Comensales: $guestCount'),
            Text(
              '${order['line_count'] ?? 0} líneas · ${order['total_qty'] ?? 0} unidades',
            ),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Platos y productos',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${toNum(item['quantity']).toStringAsFixed(0)} × ${item['description'] ?? 'Producto'}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$currencySymbol ${toNum(item['total']).toStringAsFixed(2)}',
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(child: Text('Total')),
                Text(
                  '$currencySymbol $total',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            if (quickSale && !isClosed)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  if (paymentMethods.isNotEmpty)
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      initialValue: paymentMethodId,
                      decoration: const InputDecoration(
                        labelText: 'Medio de pago',
                        prefixIcon: Icon(Icons.payments_outlined),
                      ),
                      items: [
                        for (final method in paymentMethods)
                          DropdownMenuItem(
                            value: toIntOrNull(method['id']),
                            child: Text((method['name'] ?? '').toString()),
                          ),
                      ],
                      onChanged: checkoutBusy ? null : onPaymentMethodChanged,
                    ),
                  if (paymentMethods.isNotEmpty) const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: selectedDocumentKind,
                    decoration: const InputDecoration(
                      labelText: 'Comprobante',
                      prefixIcon: Icon(Icons.receipt_long_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'SALES_ORDER',
                        child: Text('Pedido de Venta'),
                      ),
                      DropdownMenuItem(value: 'RECEIPT', child: Text('Boleta')),
                      DropdownMenuItem(
                        value: 'INVOICE',
                        child: Text('Factura'),
                      ),
                    ],
                    onChanged: checkoutBusy
                        ? null
                        : (value) {
                            if (value != null) onDocumentKindChanged(value);
                          },
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: checkoutBusy ? null : onCheckout,
                    icon: checkoutBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.point_of_sale),
                    label: Text(
                      checkoutBusy ? 'Procesando cobro...' : 'Cobrar pedido',
                    ),
                  ),
                  if (canEdit) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: editBusy || checkoutBusy ? null : onEdit,
                      icon: editBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.edit_outlined),
                      label: Text(
                        editBusy ? 'Cargando pedido...' : 'Editar pedido',
                      ),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _kitchenLabel(String value) => switch (value.toUpperCase()) {
    'IN_PREP' || 'IN_PREPARATION' => 'En preparación',
    'READY' => 'Listo',
    'SERVED' => 'Entregado',
    'CANCELLED' => 'Cancelado',
    _ => 'Pendiente',
  };
}

class RestaurantTablesPage extends StatefulWidget {
  const RestaurantTablesPage({
    required this.api,
    required this.appContext,
    required this.onUnauthorized,
    this.showAppBar = true,
    super.key,
  });

  final ApiClient api;
  final AppContext appContext;
  final VoidCallback onUnauthorized;
  final bool showAppBar;

  @override
  State<RestaurantTablesPage> createState() => _RestaurantTablesPageState();
}

class _RestaurantTablesPageState extends State<RestaurantTablesPage> {
  List<Map<String, dynamic>> _tables = const [];
  String _statusFilter = '';
  String _search = '';
  bool _loading = true;
  int? _busyId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final branchId = widget.appContext.branchId;
      if (branchId == null) {
        throw const ApiException('Selecciona una sucursal para ver las mesas.');
      }
      final body = await widget.api.get('/api/restaurant/tables', {
        'branch_id': '$branchId',
        'status': _statusFilter.isEmpty ? null : _statusFilter,
        'search': _search.trim().isEmpty ? null : _search.trim(),
      });
      final rows = body['data'];
      if (mounted) {
        setState(
          () => _tables = rows is List
              ? rows
                    .whereType<Map>()
                    .map((row) => row.cast<String, dynamic>())
                    .toList()
              : const [],
        );
      }
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        widget.onUnauthorized();
      } else if (mounted) {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editTable([Map<String, dynamic>? table]) async {
    final branchId = widget.appContext.branchId;
    if (branchId == null) {
      setState(
        () => _error = 'Selecciona una sucursal para administrar mesas.',
      );
      return;
    }
    final formKey = GlobalKey<FormState>();
    var codeValue = (table?['code'] ?? '').toString();
    var nameValue = (table?['name'] ?? '').toString();
    var capacityValue = (table?['capacity'] ?? 4).toString();
    final value = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(table == null ? 'Agregar mesa' : 'Editar mesa'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: codeValue,
                  textCapitalization: TextCapitalization.characters,
                  readOnly: table != null,
                  maxLength: 40,
                  decoration: InputDecoration(
                    labelText: 'Código',
                    helperText: table == null ? null : 'El código no se puede cambiar después de crear la mesa.',
                  ),
                  validator: (value) {
                    final normalized = (value ?? '').trim();
                    if (normalized.isEmpty) {
                      return 'Ingresa un código para la mesa.';
                    }
                    if (normalized.length > 40) {
                      return 'El código admite hasta 40 caracteres.';
                    }
                    return null;
                  },
                  onSaved: (value) => codeValue = value ?? '',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: nameValue,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Nombre / zona'),
                  validator: (value) {
                    final normalized = (value ?? '').trim();
                    if (normalized.isEmpty) {
                      return 'Ingresa un nombre para la mesa.';
                    }
                    if (normalized.length > 120) {
                      return 'El nombre admite hasta 120 caracteres.';
                    }
                    return null;
                  },
                  onSaved: (value) => nameValue = value ?? '',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: capacityValue,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Capacidad'),
                  validator: (value) {
                    final number = int.tryParse(value ?? '');
                    return number == null || number < 1 || number > 30
                        ? 'La capacidad debe estar entre 1 y 30.'
                        : null;
                  },
                  onSaved: (value) => capacityValue = value ?? '',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final form = formKey.currentState;
              if (form == null || !form.validate()) return;
              form.save();
              Navigator.pop(context, {
                if (table == null) 'code': codeValue.trim().toUpperCase(),
                'name': nameValue.trim(),
                'capacity': int.parse(capacityValue),
              });
            },
            child: Text(table == null ? 'Crear mesa' : 'Guardar cambios'),
          ),
        ],
      ),
    );
    if (value == null || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final id = toIntOrNull(table?['id']);
      if (id == null) {
        await widget.api.post('/api/restaurant/tables', {
          'branch_id': branchId,
          ...value,
        });
      } else {
        await widget.api.put('/api/restaurant/tables/$id', value);
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(id == null ? 'Mesa creada.' : 'Mesa actualizada.'),
          ),
        );
      }
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        widget.onUnauthorized();
      } else if (mounted) {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeTableStatus(
    Map<String, dynamic> table,
    String status,
  ) async {
    final id = toIntOrNull(table['id']);
    if (id == null) return;
    setState(() {
      _busyId = id;
      _error = null;
    });
    try {
      await widget.api.put('/api/restaurant/tables/$id', {'status': status});
      await _load();
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        widget.onUnauthorized();
      } else if (mounted) {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final countAvailable = _tables
        .where((row) => row['status'] == 'AVAILABLE')
        .length;
    final countOccupied = _tables
        .where((row) => row['status'] == 'OCCUPIED')
        .length;
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Mesas'),
              actions: [
                IconButton(
                  onPressed: _loading ? null : _load,
                  tooltip: 'Actualizar',
                  icon: const Icon(Icons.refresh),
                ),
              ],
            )
          : null,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : () => _editTable(),
        icon: const Icon(Icons.add),
        label: const Text('Agregar mesa'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(child: Text('${_tables.length} mesas')),
                Chip(label: Text('$countAvailable libres')),
                const SizedBox(width: 6),
                Chip(label: Text('$countOccupied ocupadas')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Buscar código o nombre',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => _search = value,
                    onSubmitted: (_) => _load(),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _statusFilter,
                  items: const [
                    DropdownMenuItem(value: '', child: Text('Todos')),
                    DropdownMenuItem(value: 'AVAILABLE', child: Text('Libres')),
                    DropdownMenuItem(
                      value: 'OCCUPIED',
                      child: Text('Ocupadas'),
                    ),
                    DropdownMenuItem(
                      value: 'RESERVED',
                      child: Text('Reservadas'),
                    ),
                    DropdownMenuItem(
                      value: 'DISABLED',
                      child: Text('Inactivas'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _statusFilter = value ?? '');
                    _load();
                  },
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) _ErrorBanner(message: _error!),
          Expanded(
            child: _tables.isEmpty && !_loading
                ? const _EmptyCard(
                    icon: Icons.table_restaurant_outlined,
                    message: 'No hay mesas para estos filtros. Puedes agregar una mesa.',
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 330,
                            mainAxisExtent: 238,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                      itemCount: _tables.length,
                      itemBuilder: (context, index) {
                        final table = _tables[index];
                        final status = (table['status'] ?? 'AVAILABLE')
                            .toString();
                        final id = toIntOrNull(table['id']);
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.table_restaurant_outlined),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${table['code'] ?? ''} · ${table['name'] ?? ''}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Capacidad: ${table['capacity'] ?? 0} personas',
                                ),
                                const SizedBox(height: 4),
                                Chip(label: Text(_statusLabel(status))),
                                const Spacer(),
                                Wrap(
                                  spacing: 4,
                                  children: [
                                    IconButton(
                                      tooltip: 'Editar mesa',
                                      onPressed: _loading
                                          ? null
                                          : () => _editTable(table),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                    for (final option in const [
                                      ('AVAILABLE', 'Libre'),
                                      ('OCCUPIED', 'Ocupada'),
                                      ('RESERVED', 'Reservar'),
                                      ('DISABLED', 'Inactivar'),
                                    ])
                                      if (status != option.$1)
                                        TextButton(
                                          onPressed: _busyId == id
                                              ? null
                                              : () => _changeTableStatus(
                                                  table,
                                                  option.$1,
                                                ),
                                          child: Text(option.$2),
                                        ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String status) => switch (status.toUpperCase()) {
    'OCCUPIED' => 'Ocupada',
    'RESERVED' => 'Reservada',
    'DISABLED' => 'Fuera de servicio',
    _ => 'Disponible',
  };
}

class RestaurantMenuPage extends StatefulWidget {
  const RestaurantMenuPage({
    required this.api,
    required this.appContext,
    required this.onUnauthorized,
    this.showAppBar = true,
    super.key,
  });

  final ApiClient api;
  final AppContext appContext;
  final VoidCallback onUnauthorized;
  final bool showAppBar;

  @override
  State<RestaurantMenuPage> createState() => _RestaurantMenuPageState();
}

class _RestaurantMenuPageState extends State<RestaurantMenuPage> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _products = const [];
  List<Map<String, dynamic>> _units = const [];
  bool _loading = true;
  bool _saving = false;
  bool _showInactive = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.api.get('/api/inventory/products', {
          'search': _search.text.trim(),
          'warehouse_id': widget.appContext.warehouseId?.toString(),
          'limit': '100',
          'autocomplete': 'true',
        }),
        widget.api.get('/api/inventory/product-lookups'),
      ]);
      final rows = results[0]['data'];
      final products = rows is List
          ? rows
                .whereType<Map>()
                .map((row) => row.cast<String, dynamic>())
                .where(
                  (row) =>
                      row['product_nature']?.toString().toUpperCase() !=
                      'SUPPLY',
                )
                .toList()
          : <Map<String, dynamic>>[];
      final rawUnits = results[1]['units'];
      final units = rawUnits is List
          ? rawUnits
                .whereType<Map>()
                .map((row) => row.cast<String, dynamic>())
                .toList()
          : <Map<String, dynamic>>[];
      if (mounted) {
        setState(() {
          _products = products;
          _units = units;
        });
      }
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        widget.onUnauthorized();
      } else if (mounted) {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editMenuItem([Map<String, dynamic>? product]) async {
    final seenUnitIds = <int>{};
    final unitOptions = _units.where((unit) {
      final id = toIntOrNull(unit['id']);
      return id != null && seenUnitIds.add(id);
    }).toList();
    if (unitOptions.isEmpty) {
      setState(() => _error = 'No hay unidades configuradas para productos.');
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RestaurantMenuProductDialog(
        product: product,
        units: unitOptions,
        onSave: (draft, {existingProductId}) =>
            _saveMenuItem(product, draft, existingProductId: existingProductId),
      ),
    );
  }

  Future<_RestaurantMenuSaveResult> _saveMenuItem(
    Map<String, dynamic>? product,
    _RestaurantMenuProductDraft draft, {
    int? existingProductId,
  }) async {
    if (!mounted) return const _RestaurantMenuSaveResult();
    setState(() {
      _saving = true;
      _error = null;
    });
    var productSaved = false;
    int? productId = toIntOrNull(product?['id']) ?? existingProductId;
    String? uploadedImageUrl;
    String? imageError;
    try {
      if (productId == null) {
        final response = await widget.api.post(
          '/api/inventory/products',
          draft.payload,
        );
        productId = toIntOrNull(response['id']);
        productSaved = true;
      } else {
        await widget.api.put(
          '/api/inventory/products/$productId',
          draft.payload,
        );
        productSaved = true;
      }
      if (draft.imageBytes != null && productId == null) {
        return const _RestaurantMenuSaveResult(
          imageError:
              'No se recibió el identificador del producto para subir la imagen',
        );
      }
      if (draft.imageBytes != null && productId != null) {
        try {
          final response = await widget.api.uploadFile(
            '/api/inventory/products/$productId/image',
            fieldName: 'image',
            bytes: draft.imageBytes!,
            filename: draft.imageName ?? 'product-image.jpg',
          );
          uploadedImageUrl = response['image_url']?.toString();
        } on ApiException catch (error) {
          imageError = error.message;
        } on Exception catch (error) {
          imageError = error.toString();
        }
      }
      if (imageError == null) await _load();
      if (productId != null && mounted) {
        setState(() {
          final currentProduct =
              product ??
              _products.firstWhere(
                (row) => toIntOrNull(row['id']) == productId,
                orElse: () => const <String, dynamic>{},
              );
          final updatedProduct = {
            ...currentProduct,
            ...draft.payload,
            'id': productId,
            'image_url': uploadedImageUrl ?? currentProduct['image_url'],
          };
          final existingIndex = _products.indexWhere(
            (row) => toIntOrNull(row['id']) == productId,
          );
          if (existingIndex < 0) {
            _products = [..._products, updatedProduct];
          } else {
            _products = [
              for (var index = 0; index < _products.length; index++)
                if (index == existingIndex)
                  updatedProduct
                else
                  _products[index],
            ];
          }
        });
      }
      return _RestaurantMenuSaveResult(
        productId: productId,
        imageError: imageError,
      );
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        widget.onUnauthorized();
      }
      if (productSaved && mounted) await _load();
      rethrow;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleMenuStatus(Map<String, dynamic> product) async {
    final id = toIntOrNull(product['id']);
    if (id == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.put('/api/inventory/products/$id', {
        'status': toIntOrNull(product['status']) == 1 ? 0 : 1,
      });
      await _load();
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        widget.onUnauthorized();
      } else if (mounted) {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final symbol = widget.appContext.defaultCurrency?.symbol ?? 'S/';
    final products = _products
        .where((row) => _showInactive || toIntOrNull(row['status']) != 0)
        .toList();
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Menú'),
              actions: [
                IconButton(
                  onPressed: _loading ? null : _load,
                  tooltip: 'Actualizar',
                  icon: const Icon(Icons.refresh),
                ),
              ],
            )
          : null,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving || _loading ? null : () => _editMenuItem(),
        icon: const Icon(Icons.add),
        label: const Text('Agregar al menú'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                hintText: 'Buscar plato o bebida',
                prefixIcon: Icon(Icons.search),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
            ),
          ),
          SwitchListTile(
            value: _showInactive,
            title: const Text('Mostrar productos inactivos'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            onChanged: (value) => setState(() => _showInactive = value),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) _ErrorBanner(message: _error!),
          Expanded(
            child: products.isEmpty && !_loading
                ? const _EmptyCard(
                    icon: Icons.restaurant_menu,
                    message: 'No hay productos de carta para mostrar.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                    itemCount: products.length,
                    itemBuilder: (context, index) {
                      final product = products[index];
                      final active = toIntOrNull(product['status']) != 0;
                      return Card(
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.restaurant_menu),
                          ),
                          title: Text(
                            (product['name'] ?? '').toString(),
                            style: TextStyle(
                              color: active
                                  ? null
                                  : Theme.of(context).disabledColor,
                            ),
                          ),
                          subtitle: Text(
                            [
                              if ((product['category_name'] ?? '')
                                  .toString()
                                  .isNotEmpty)
                                product['category_name'].toString(),
                              if ((product['sku'] ?? '').toString().isNotEmpty)
                                product['sku'].toString(),
                            ].join(' · '),
                          ),
                          trailing: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                '$symbol ${toNum(product['sale_price']).toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Editar producto',
                                onPressed: _saving
                                    ? null
                                    : () => _editMenuItem(product),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: active
                                    ? 'Desactivar producto'
                                    : 'Activar producto',
                                onPressed: _saving
                                    ? null
                                    : () => _toggleMenuStatus(product),
                                icon: Icon(
                                  active
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                              ),
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

class _RestaurantMenuProductDialog extends StatefulWidget {
  const _RestaurantMenuProductDialog({
    required this.product,
    required this.units,
    required this.onSave,
  });

  final Map<String, dynamic>? product;
  final List<Map<String, dynamic>> units;
  final Future<_RestaurantMenuSaveResult> Function(
    _RestaurantMenuProductDraft draft, {
    int? existingProductId,
  })
  onSave;

  @override
  State<_RestaurantMenuProductDialog> createState() =>
      _RestaurantMenuProductDialogState();
}

class _RestaurantMenuProductDraft {
  const _RestaurantMenuProductDraft({
    required this.payload,
    this.imageBytes,
    this.imageName,
  });

  final Map<String, dynamic> payload;
  final Uint8List? imageBytes;
  final String? imageName;
}

class _RestaurantMenuSaveResult {
  const _RestaurantMenuSaveResult({this.productId, this.imageError});

  final int? productId;
  final String? imageError;
}

class _RestaurantMenuProductDialogState
    extends State<_RestaurantMenuProductDialog> {
  final _formKey = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();
  late final TextEditingController _name;
  late final TextEditingController _sku;
  late final TextEditingController _price;
  late final TextEditingController _cost;
  late int? _unitId;
  Uint8List? _imageBytes;
  String? _imageName;
  bool _pickingImage = false;
  bool _saving = false;
  String? _imageError;
  String? _saveError;
  int? _existingProductId;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _name = TextEditingController(text: (product?['name'] ?? '').toString());
    _sku = TextEditingController(text: (product?['sku'] ?? '').toString());
    _price = TextEditingController(
      text: toNum(product?['sale_price']).toStringAsFixed(2),
    );
    _cost = TextEditingController(
      text: toNum(product?['cost_price']).toStringAsFixed(2),
    );
    final availableUnitIds = widget.units
        .map((unit) => toIntOrNull(unit['id']))
        .whereType<int>()
        .toSet();
    final productUnitId = toIntOrNull(product?['unit_id']);
    _unitId = availableUnitIds.contains(productUnitId)
        ? productUnitId
        : toIntOrNull(widget.units.first['id']);
  }

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _price.dispose();
    _cost.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    setState(() {
      _pickingImage = true;
      _imageError = null;
    });
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _imageName = image.name;
      });
    } on Exception catch (error) {
      if (mounted) {
        setState(
          () => _imageError = 'No se pudo seleccionar la imagen: $error',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _pickingImage = false);
      }
    }
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    if (_unitId == null) {
      setState(() => _saveError = 'Selecciona una unidad de venta.');
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final result = await widget.onSave(
        _RestaurantMenuProductDraft(
          payload: {
            'name': _name.text.trim(),
            'sku': _sku.text.trim().isEmpty ? null : _sku.text.trim(),
            'unit_id': _unitId,
            'product_nature': 'PRODUCT',
            'sale_price': double.parse(_price.text.replaceAll(',', '.')),
            'cost_price': double.parse(_cost.text.replaceAll(',', '.')),
            'is_stockable': toBool(widget.product?['is_stockable'] ?? true),
            'lot_tracking': toBool(widget.product?['lot_tracking']),
            'has_expiration': toBool(widget.product?['has_expiration']),
            'status': toIntOrNull(widget.product?['status']) ?? 1,
          },
          imageBytes: _imageBytes,
          imageName: _imageName,
        ),
        existingProductId: _existingProductId,
      );
      if (!mounted) return;
      if (result.imageError != null) {
        setState(() {
          _existingProductId = result.productId;
          _saveError =
              'El producto se guardó, pero no se pudo guardar la imagen: ${result.imageError}. Puedes volver a intentarlo sin duplicar el producto.';
        });
      } else {
        Navigator.pop(context);
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _saveError = error.message);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final existingImageUrl = (widget.product?['image_url'] ?? '').toString();
    final editingExisting =
        widget.product != null || _existingProductId != null;
    return AlertDialog(
      title: Text(editingExisting ? 'Editar producto' : 'Agregar al menú'),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: size.height * 0.72,
        ),
        child: SizedBox(
          width: double.maxFinite,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: 'Plato o bebida',
                    ),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'El nombre es obligatorio.'
                        : null,
                  ),
                  TextFormField(
                    controller: _sku,
                    decoration: const InputDecoration(
                      labelText: 'Código (opcional)',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 160,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _imageBytes != null
                        ? Image.memory(
                            _imageBytes!,
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.contain,
                          )
                        : existingImageUrl.isNotEmpty
                        ? Image.network(
                            existingImageUrl,
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) =>
                                const Icon(Icons.restaurant_menu, size: 42),
                          )
                        : const Icon(
                            Icons.add_photo_alternate_outlined,
                            size: 42,
                          ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: OutlinedButton.icon(
                      onPressed: _pickingImage || _saving ? null : _pickImage,
                      icon: _pickingImage
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(
                        _imageBytes == null && existingImageUrl.isEmpty
                            ? 'Elegir imagen'
                            : 'Cambiar imagen',
                      ),
                    ),
                  ),
                  if (_imageError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _imageError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (_saveError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [_ErrorBanner(message: _saveError!)],
                      ),
                    ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: _unitId,
                    decoration: const InputDecoration(
                      labelText: 'Unidad de venta',
                    ),
                    items: [
                      for (final unit in widget.units)
                        DropdownMenuItem(
                          value: toIntOrNull(unit['id'])!,
                          child: Text(
                            '${unit['name'] ?? unit['label'] ?? ''} (${unit['code'] ?? ''})',
                          ),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) {
                            if (value != null) setState(() => _unitId = value);
                          },
                  ),
                  TextFormField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Precio de venta',
                    ),
                    validator: (value) {
                      final number = double.tryParse(
                        (value ?? '').replaceAll(',', '.'),
                      );
                      return number == null || number < 0
                          ? 'Ingresa un precio válido.'
                          : null;
                    },
                  ),
                  TextFormField(
                    controller: _cost,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Costo'),
                    validator: (value) {
                      final number = double.tryParse(
                        (value ?? '').replaceAll(',', '.'),
                      );
                      return number == null || number < 0
                          ? 'Ingresa un costo válido.'
                          : null;
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _pickingImage || _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(editingExisting ? 'Guardar' : 'Agregar'),
        ),
      ],
    );
  }
}

class _ModeBanner extends StatelessWidget {
  const _ModeBanner({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.primaryContainer,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(subtitle),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          Icon(icon, size: 32, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
