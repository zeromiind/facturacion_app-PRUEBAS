import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';
import '../../../core/inventory/stock.dart';
import '../../../core/session/app_context.dart';
import '../../customers/data/customers_repository.dart';
import '../../customers/domain/customer.dart';
import '../../customers/presentation/customer_form_page.dart';
import '../data/sales_repository.dart';
import '../domain/product.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({
    required this.repository,
    required this.customers,
    required this.appContext,
    required this.onUnauthorized,
    super.key,
  });

  final SalesRepository repository;
  final CustomersRepository customers;
  final AppContext appContext;
  final VoidCallback onUnauthorized;

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  final _lines = <CartLine>[];
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _odometerController = TextEditingController();
  final _nextOdometerController = TextEditingController();
  final _notesController = TextEditingController();

  // Como en la web: en flujo vendedor->cajero, el cajero no emite pedidos.
  late final List<DocumentKind> _kinds = widget.appContext.documentKinds
      .where((k) => !k.isNote)
      .where(
        (k) =>
            !(widget.appContext.sellerToCashier &&
                widget.appContext.isCashier &&
                !widget.appContext.isAdmin &&
                (k.code == 'QUOTATION' || k.code == 'SALES_ORDER')),
      )
      .toList();
  DocumentKind? _kind;
  List<SeriesOption> _seriesOptions = const [];
  List<Product> _top = const [];
  Map<int, double> _stock = const {};
  String? _series;
  int? _paymentMethodId;
  SunatSendMode _sunatSendMode = SunatSendMode.direct;
  Customer? _customer;
  List<CustomerVehicle> _vehicles = const [];
  int? _vehicleId;
  bool _submitting = false;

  AppContext get _ctx => widget.appContext;
  String get _symbol => _ctx.defaultCurrency?.symbol ?? 'S/';
  String _money(num v) => '$_symbol ${v.toStringAsFixed(2)}';

  @override
  void initState() {
    super.initState();
    _guard(() => widget.repository.stockByProduct()).then((map) {
      if (mounted && map != null) setState(() => _stock = map);
    });
    _guard(() => widget.repository.quickProducts()).then((rows) {
      if (mounted && rows != null) setState(() => _top = rows);
    });
    _kind =
        _kinds.where((k) => k.code == 'QUOTATION').firstOrNull ??
        _kinds.where((k) => k.code == 'SALES_ORDER').firstOrNull ??
        _kinds.where((k) => k.code == 'RECEIPT').firstOrNull ??
        _kinds.firstOrNull;
    final methods = _ctx.paymentMethods;
    final cash = methods.where((m) {
      final text = '${m.code} ${m.name}'.toUpperCase();
      return text.contains('EFECT') ||
          text.contains('CASH') ||
          text.contains('CONTADO');
    });
    _paymentMethodId = (cash.firstOrNull ?? methods.firstOrNull)?.id;
    _loadSeries();
  }

  @override
  void dispose() {
    _addressController.dispose();
    _phoneController.dispose();
    _odometerController.dispose();
    _nextOdometerController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<T?> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        widget.onUnauthorized();
      } else {
        _toast(e.message);
      }
      return null;
    }
  }

  Future<void> _loadSeries() async {
    final kind = _kind;
    if (kind == null) return;
    final rows = await _guard(() => widget.repository.seriesFor(kind.code));
    if (!mounted || kind != _kind) return;
    setState(() {
      _seriesOptions = rows ?? const [];
      _series = _seriesOptions.any((s) => s.series == _series)
          ? _series
          : _seriesOptions.firstOrNull?.series;
    });
    if (rows != null && rows.isEmpty) {
      _toast('No hay series activas para ${kind.label}.');
    }
  }

  Future<void> _pickCustomer() async {
    final picked = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CustomerPicker(
        repository: widget.customers,
        workshopEnabled: _ctx.workshopEnabled,
      ),
    );
    if (picked == null) return;
    setState(() {
      _customer = picked;
      _vehicles = const [];
      _vehicleId = null;
      _addressController.text = picked.address ?? '';
      _phoneController.text = picked.phone ?? '';
      _odometerController.clear();
      _nextOdometerController.clear();
    });
    if (_ctx.workshopEnabled) await _loadVehicles();
  }

  Future<void> _loadVehicles({bool selectNewest = false}) async {
    final customer = _customer;
    if (customer == null) return;
    final rows = await _guard(() => widget.customers.vehicles(customer.id));
    if (!mounted || rows == null || customer != _customer) return;
    setState(() {
      _vehicles = rows;
      if (selectNewest && rows.isNotEmpty) {
        _vehicleId = rows.map((v) => v.id).reduce((a, b) => a > b ? a : b);
      } else if (!rows.any((v) => v.id == _vehicleId)) {
        _vehicleId =
            (rows.where((v) => v.isDefault).firstOrNull ?? rows.firstOrNull)
                ?.id;
      }
    });
  }

  Future<void> _addVehicle() async {
    final customer = _customer;
    if (customer == null) return;
    final saved = await showVehicleSheet(
      context,
      repository: widget.customers,
      customerId: customer.id,
    );
    if (saved == true) _loadVehicles(selectNewest: true);
  }

  Future<void> _addProduct() async {
    final product = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ProductPicker(
        repository: widget.repository,
        symbol: _symbol,
        stock: _stock,
      ),
    );
    if (product == null) return;
    _addToCart(product);
  }

  void _addToCart(Product product) {
    if (product.lotTracking) {
      _toast('Los productos con lote aún no se pueden vender desde el móvil.');
      return;
    }
    setState(() {
      final existing = _lines.where((l) => l.product.id == product.id);
      if (existing.isEmpty) {
        _lines.add(CartLine(product: product));
      } else {
        existing.first.qty += 1;
      }
    });
  }

  Future<void> _editPrice(CartLine line) async {
    final controller = TextEditingController(
      text: line.unitPrice.toStringAsFixed(2),
    );
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Precio unitario'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(prefixText: '$_symbol '),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              double.tryParse(controller.text.replaceAll(',', '.')),
            ),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && value >= 0) setState(() => line.unitPrice = value);
  }

  Future<void> _submit() async {
    final kind = _kind;
    final customer = _customer;
    String? error;
    if (kind == null || _series == null) {
      error = 'Seleccione tipo de documento y serie.';
    } else if (customer == null) {
      error = 'Seleccione un cliente.';
    } else if (_lines.isEmpty) {
      error = 'Agregue al menos un producto.';
    } else if (_paymentMethodId == null) {
      error = 'Seleccione un medio de pago.';
    }
    if (error != null) return _toast(error);

    int? km(TextEditingController c) =>
        int.tryParse(c.text.replaceAll(RegExp(r'\D'), ''));

    setState(() => _submitting = true);
    final result = await _guard(
      () => widget.repository.createDocument(
        SaleDraft(
          documentKind: kind!,
          series: _series!,
          customerId: customer!.id,
          paymentMethodId: _paymentMethodId!,
          lines: _lines,
          sunatSendMode: _sunatSendMode,
          customerAddress: _addressController.text.trim().isEmpty
              ? null
              : _addressController.text.trim(),
          customerPhone: _phoneController.text.trim().isEmpty
              ? null
              : _phoneController.text.trim(),
          vehicleId: _vehicleId,
          odometerKm: km(_odometerController),
          nextOdometerKm: km(_nextOdometerController),
          notes: _notesController.text,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result == null) return;

    final data = result['data'];
    final number = data is Map
        ? '${data['series'] ?? _series}-${data['number'] ?? ''}'
        : _series;
    _toast('${kind!.label} registrado: $number');
    setState(() {
      _lines.clear();
      _customer = null;
      _vehicles = const [];
      _vehicleId = null;
      for (final c in [
        _addressController,
        _phoneController,
        _odometerController,
        _nextOdometerController,
        _notesController,
      ]) {
        c.clear();
      }
    });
    _loadSeries();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = _kind;
    final totals = kind == null
        ? const SaleTotals(0, 0, 0)
        : widget.repository.totals(_lines, kind);
    final workshop = _ctx.workshopEnabled;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nueva venta'),
        bottom: workshop
            ? PreferredSize(
                preferredSize: const Size.fromHeight(24),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Modo taller · datos de vehículo',
                    style: theme.textTheme.labelMedium,
                  ),
                ),
              )
            : null,
      ),
      bottomNavigationBar: SafeArea(
        child: Material(
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (totals.tax > 0)
                        Text(
                          'IGV ${_money(totals.tax)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      Text(
                        _money(totals.total),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(
                    kind != null && !kind.isTributary ? 'Guardar' : 'Emitir',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _section(
            title: 'Documento',
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 0,
                children: [
                  for (final k in _kinds)
                    ChoiceChip(
                      label: Text(k.label),
                      selected: k == kind,
                      onSelected: (_) {
                        setState(() {
                          _kind = k;
                          if (k.code != 'RECEIPT' &&
                              _sunatSendMode == SunatSendMode.dailySummary) {
                            _sunatSendMode = SunatSendMode.direct;
                          }
                        });
                        _loadSeries();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                isExpanded: true,
                key: ValueKey(
                  'series-${_seriesOptions.map((s) => s.label).join()}',
                ),
                initialValue: _series,
                decoration: const InputDecoration(
                  labelText: 'Serie (siguiente número)',
                ),
                items: [
                  for (final s in _seriesOptions)
                    DropdownMenuItem(value: s.series, child: Text(s.label)),
                ],
                onChanged: (value) => setState(() => _series = value),
              ),
              if (kind?.isTributary ?? false) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<SunatSendMode>(
                  isExpanded: true,
                  initialValue: _sunatSendMode,
                  decoration: InputDecoration(
                    labelText: 'Envío a SUNAT',
                    helperText: switch (_sunatSendMode) {
                      SunatSendMode.direct =>
                        'Se enviará al emitir el comprobante.',
                      SunatSendMode.dailySummary =>
                        'La boleta se incluirá en el resumen diario.',
                      SunatSendMode.disabled =>
                        'El comprobante quedará pendiente de envío.',
                    },
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: SunatSendMode.direct,
                      child: Text('Envío directo'),
                    ),
                    if (kind?.code == 'RECEIPT')
                      const DropdownMenuItem(
                        value: SunatSendMode.dailySummary,
                        child: Text('Por resumen diario (RC)'),
                      ),
                    const DropdownMenuItem(
                      value: SunatSendMode.disabled,
                      child: Text('No enviar ahora'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _sunatSendMode = value);
                    }
                  },
                ),
              ],
            ],
          ),
          _section(
            title: 'Cliente',
            children: [
              InkWell(
                onTap: _pickCustomer,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Cliente',
                    suffixIcon: Icon(Icons.search),
                  ),
                  child: Text(
                    _customer == null
                        ? 'Toque para buscar o crear'
                        : '${_customer!.name}\n${_customer!.documentLabel}',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _addressController,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Dirección'),
              ),
              if (workshop) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Teléfono'),
                ),
              ],
            ],
          ),
          if (workshop)
            _section(
              title: 'Vehículo',
              trailing: TextButton.icon(
                onPressed: _customer == null ? null : _addVehicle,
                icon: const Icon(Icons.add),
                label: const Text('Nuevo'),
              ),
              children: [
                DropdownButtonFormField<int?>(
                  isExpanded: true,
                  key: ValueKey('veh-${_vehicles.length}-$_vehicleId'),
                  initialValue: _vehicleId,
                  decoration: InputDecoration(
                    labelText: 'Vehículo',
                    helperText: _customer == null
                        ? 'Seleccione un cliente'
                        : (_vehicles.isEmpty
                              ? 'El cliente no tiene vehículos'
                              : null),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Sin vehículo'),
                    ),
                    for (final v in _vehicles)
                      DropdownMenuItem<int?>(value: v.id, child: Text(v.label)),
                  ],
                  onChanged: _vehicles.isEmpty
                      ? null
                      : (value) => setState(() => _vehicleId = value),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _odometerController,
                        enabled: _vehicleId != null,
                        keyboardType: TextInputType.number,
                        maxLength: 7,
                        decoration: const InputDecoration(
                          labelText: 'Km actual',
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _nextOdometerController,
                        enabled: _vehicleId != null,
                        keyboardType: TextInputType.number,
                        maxLength: 7,
                        decoration: const InputDecoration(
                          labelText: 'Próximo km',
                          counterText: '',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          _section(
            title: 'Productos',
            trailing: TextButton.icon(
              onPressed: _addProduct,
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('Agregar'),
            ),
            children: [
              if (_top.isNotEmpty) ...[
                Row(
                  children: [
                    Icon(
                      Icons.local_fire_department,
                      size: 16,
                      color: Colors.orange.shade700,
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Más vendidos',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cardsPerView = (constraints.maxWidth / 210)
                        .floor()
                        .clamp(2, 6);
                    final cardWidth =
                        (constraints.maxWidth - (8 * (cardsPerView - 1))) /
                        cardsPerView;
                    return SizedBox(
                      height: 120,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _top.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final p = _top[i];
                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _addToCart(p),
                            child: Container(
                              width: cardWidth,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer
                                    .withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      p.name,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 2,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        _money(p.salePrice),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                      StockChip(stock: _stock[p.id]),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
                const Divider(height: 20),
              ],
              if (_lines.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Aún no hay productos.'),
                ),
              for (final line in _lines) _lineTile(line),
            ],
          ),
          _section(
            title: 'Pago',
            children: [
              DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: _paymentMethodId,
                decoration: const InputDecoration(labelText: 'Medio de pago'),
                items: [
                  for (final m in _ctx.paymentMethods)
                    DropdownMenuItem(value: m.id, child: Text(m.name)),
                ],
                onChanged: (value) => setState(() => _paymentMethodId = value),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _notesController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Observaciones'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _lineTile(CartLine line) {
    return Dismissible(
      key: ObjectKey(line),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red.shade100,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete_outline),
      ),
      onDismissed: (_) => setState(() => _lines.remove(line)),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          line.product.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: GestureDetector(
          onTap: () => _editPrice(line),
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${_money(line.unitPrice)} c/u  ✎  =  ${_money(line.gross)}',
              ),
              StockChip(stock: _stock[line.product.id]),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () => setState(() {
                line.qty -= 1;
                if (line.qty <= 0) _lines.remove(line);
              }),
            ),
            Text(
              line.qty == line.qty.roundToDouble()
                  ? '${line.qty.toInt()}'
                  : line.qty.toString(),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => setState(() => line.qty += 1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section({
    required String title,
    required List<Widget> children,
    Widget? trailing,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _CustomerPicker extends StatefulWidget {
  const _CustomerPicker({
    required this.repository,
    required this.workshopEnabled,
  });

  final CustomersRepository repository;
  final bool workshopEnabled;

  @override
  State<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends State<_CustomerPicker> {
  final _controller = TextEditingController();
  List<Customer> _results = const [];
  bool _loading = false;
  String? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.repository.autocomplete(query);
      if (mounted && seq == _seq) setState(() => _results = rows);
    } on ApiException catch (e) {
      if (mounted && seq == _seq) setState(() => _error = e.message);
    } finally {
      if (mounted && seq == _seq) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CustomerFormPage(
          repository: widget.repository,
          workshopEnabled: widget.workshopEnabled,
        ),
      ),
    );
    if (created == true) _search(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: SearchBar(
                      controller: _controller,
                      autoFocus: true,
                      hintText: 'Nombre, DNI o RUC',
                      leading: const Icon(Icons.search),
                      onChanged: _search,
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Nuevo cliente',
                    onPressed: _create,
                    icon: const Icon(Icons.person_add_alt_1),
                  ),
                ],
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (context, index) {
                  final c = _results[index];
                  return ListTile(
                    title: Text(c.name),
                    subtitle: Text(c.documentLabel),
                    onTap: () => Navigator.of(context).pop(c),
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

class _ProductPicker extends StatefulWidget {
  const _ProductPicker({
    required this.repository,
    required this.symbol,
    required this.stock,
  });

  final SalesRepository repository;
  final String symbol;
  final Map<int, double> stock;

  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  final _controller = TextEditingController();
  List<Product> _results = const [];
  List<Product> _top = const [];
  bool _loading = false;
  String? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _search('');
    _loadTop();
  }

  Future<void> _loadTop() async {
    try {
      final rows = await widget.repository.quickProducts();
      if (mounted) setState(() => _top = rows);
    } on ApiException {
      // Los más vendidos son opcionales; la búsqueda sigue disponible.
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.repository.searchProducts(query);
      if (mounted && seq == _seq) setState(() => _results = rows);
    } on ApiException catch (e) {
      if (mounted && seq == _seq) setState(() => _error = e.message);
    } finally {
      if (mounted && seq == _seq) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showTop = _controller.text.trim().isEmpty && _top.isNotEmpty;
    Widget tile(Product p) => ListTile(
      dense: true,
      title: Text(p.name),
      subtitle: Text(
        [
          if ((p.sku ?? '').isNotEmpty) p.sku!,
          if ((p.categoryName ?? '').isNotEmpty) p.categoryName!,
        ].join(' · '),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${widget.symbol} ${p.salePrice.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          StockChip(stock: widget.stock[p.id]),
        ],
      ),
      onTap: () => Navigator.of(context).pop(p),
    );
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SearchBar(
                controller: _controller,
                autoFocus: true,
                hintText: 'Producto, SKU o código de barras',
                leading: const Icon(Icons.search),
                onChanged: _search,
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
            Expanded(
              child: ListView.builder(
                itemCount: _results.length + (showTop ? _top.length + 2 : 0),
                itemBuilder: (context, index) {
                  if (showTop) {
                    if (index == 0) {
                      return const Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Text(
                          'Más vendidos',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      );
                    }
                    if (index <= _top.length) return tile(_top[index - 1]);
                    if (index == _top.length + 1) {
                      return const Padding(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Text(
                          'Todos los productos',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      );
                    }
                    return tile(_results[index - _top.length - 2]);
                  }
                  return tile(_results[index]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
