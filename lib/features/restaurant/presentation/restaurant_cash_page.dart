import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/session/app_context.dart';

bool _isCashPaymentMethodName(Object? value) {
  final normalized = (value ?? '').toString().trim().toLowerCase();
  return normalized.contains('efect') ||
      normalized.contains('cash') ||
      normalized.contains('contado');
}

bool _cashMethodIsCash(Map<String, dynamic> method) {
  final classification = method['is_cash_payment'];
  return classification is bool
      ? classification
      : _isCashPaymentMethodName(method['payment_method_name']);
}

class RestaurantCashPage extends StatefulWidget {
  const RestaurantCashPage({
    required this.api,
    required this.appContext,
    required this.onUnauthorized,
    this.refreshNotifier,
    this.showAppBar = true,
    super.key,
  });

  final ApiClient api;
  final AppContext appContext;
  final VoidCallback onUnauthorized;
  final ValueListenable<int>? refreshNotifier;
  final bool showAppBar;

  @override
  State<RestaurantCashPage> createState() => _RestaurantCashPageState();
}

class _RestaurantCashPageState extends State<RestaurantCashPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  Map<String, dynamic>? _session;
  List<Map<String, dynamic>> _movements = const [];
  List<Map<String, dynamic>> _paymentMethodTotals = const [];
  List<Map<String, dynamic>> _history = const [];
  Map<String, dynamic>? _closedSummary;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String _openingAmount = '0.00';
  String _closingAmount = '';
  final _openingNotes = TextEditingController();
  final _closingNotes = TextEditingController();

  int? get _registerId => widget.appContext.cashRegisterId;
  String get _symbol => widget.appContext.defaultCurrency?.symbol ?? 'S/';

  @override
  void initState() {
    super.initState();
    widget.refreshNotifier?.addListener(_handleExternalRefresh);
    _tabs.addListener(() {
      if (_tabs.index == 1) _loadHistory();
    });
    _loadCurrent();
  }

  @override
  void didUpdateWidget(covariant RestaurantCashPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshNotifier != widget.refreshNotifier) {
      oldWidget.refreshNotifier?.removeListener(_handleExternalRefresh);
      widget.refreshNotifier?.addListener(_handleExternalRefresh);
    }
  }

  @override
  void dispose() {
    widget.refreshNotifier?.removeListener(_handleExternalRefresh);
    _tabs.dispose();
    _openingNotes.dispose();
    _closingNotes.dispose();
    super.dispose();
  }

  void _handleExternalRefresh() {
    if (_tabs.index == 0) {
      _loadCurrent();
    } else {
      _loadHistory();
    }
  }

  List<Map<String, dynamic>> _asRows(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map((row) => row.cast<String, dynamic>())
            .toList()
      : const [];

  double _number(Object? value) => toNum(value).toDouble();

  String _money(Object? value) =>
      '$_symbol ${_number(value).toStringAsFixed(2)}';

  Future<List<Map<String, dynamic>>> _loadPaymentMethodTotals(
    int sessionId,
  ) async {
    try {
      final response = await widget.api.get(
        '/api/cash/sessions/$sessionId/payment-method-breakdown',
      );
      return _asRows(response['payment_method_breakdown']);
    } on ApiException catch (error) {
      if (error.statusCode != 404) rethrow;
      final detail = await widget.api.get(
        '/api/cash/sessions/$sessionId/detail',
      );
      return _asRows(detail['payment_method_breakdown']);
    }
  }

  Future<void> _loadCurrent() async {
    if (_registerId == null) {
      setState(() {
        _session = null;
        _movements = const [];
        _paymentMethodTotals = const [];
        _error = 'Selecciona una caja para consultar la sesión.';
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.api.get('/api/cash/sessions/current', {
        'cash_register_id': '$_registerId',
      });
      final session = response['session'];
      if (session is Map) {
        final row = session.cast<String, dynamic>();
        final id = toIntOrNull(row['id']);
        if (!mounted) return;
        setState(() {
          _session = row;
          _closingAmount = _number(row['expected_balance']).toStringAsFixed(2);
          _error = null;
        });
        final paymentMethodTotals = id == null
            ? const <Map<String, dynamic>>[]
            : await _loadPaymentMethodTotals(id);
        final movementResponse = id == null
            ? <String, dynamic>{}
            : await widget.api.get('/api/cash/movements', {
                'session_id': '$id',
                'cash_register_id': '$_registerId',
                'limit': '200',
              });
        if (!mounted) return;
        setState(() {
          _movements = _asRows(movementResponse['data']);
          _paymentMethodTotals = paymentMethodTotals;
        });
      } else if (mounted) {
        setState(() {
          _session = null;
          _movements = const [];
          _paymentMethodTotals = const [];
        });
      }
    } on ApiException catch (error) {
      _handleError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadHistory() async {
    if (_registerId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.api.get('/api/cash/sessions', {
        'cash_register_id': '$_registerId',
        'page': '1',
        'per_page': '30',
      });
      if (mounted) setState(() => _history = _asRows(response['data']));
    } on ApiException catch (error) {
      _handleError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _handleError(ApiException error) {
    if (error.isUnauthorized) {
      widget.onUnauthorized();
    } else if (mounted) {
      setState(() => _error = error.message);
    }
  }

  Future<void> _loadSessionById(int sessionId) async {
    try {
      final response = await widget.api.get(
        '/api/cash/sessions/$sessionId/detail',
      );
      final session = response['session'];
      if (session is! Map) {
        if (mounted) {
          setState(
            () => _error =
                'El servidor encontró una sesión abierta, pero no se pudo cargar su detalle.',
          );
        }
        return;
      }

      final row = session.cast<String, dynamic>()
        ..putIfAbsent('cash_register_id', () => _registerId);
      if (!mounted) return;
      setState(() {
        _session = row;
        _movements = _asRows(response['movements']);
        _paymentMethodTotals = _asRows(response['payment_method_breakdown']);
        _closingAmount = _number(row['expected_balance']).toStringAsFixed(2);
        _error = null;
      });
    } on ApiException catch (error) {
      _handleError(error);
    }
  }

  Future<void> _recoverOpenSession(ApiException conflict) async {
    final existingSessionId = toIntOrNull(conflict.responseBody['session_id']);
    if (existingSessionId != null) {
      await _loadSessionById(existingSessionId);
      return;
    }

    await _loadCurrent();
    if (!mounted || _session != null) return;

    try {
      final response = await widget.api.get('/api/cash/sessions', {
        'cash_register_id': '$_registerId',
        'status': 'OPEN',
        'page': '1',
        'per_page': '30',
      });
      final existing = _asRows(response['data']).where((row) {
        return toIntOrNull(row['cash_register_id']) == _registerId &&
            (row['status'] ?? '').toString().toUpperCase() == 'OPEN';
      }).firstOrNull;
      final sessionId = toIntOrNull(existing?['id']);
      if (sessionId != null) {
        await _loadSessionById(sessionId);
        return;
      }
      if (mounted && _session == null && _error == null) {
        _handleError(conflict);
      }
    } on ApiException catch (error) {
      _handleError(error);
    }
  }

  Future<void> _openSession() async {
    final amount = double.tryParse(_openingAmount.replaceAll(',', '.'));
    if (_registerId == null || amount == null || amount < 0) {
      setState(
        () => _error = 'Ingresa un saldo inicial válido y selecciona una caja.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.post('/api/cash/sessions', {
        'cash_register_id': _registerId,
        'opening_balance': amount,
        'notes': _openingNotes.text.trim().isEmpty
            ? null
            : _openingNotes.text.trim(),
      });
      if (mounted) setState(() => _closedSummary = null);
      _openingNotes.clear();
      await _loadCurrent();
    } on ApiException catch (error) {
      if (error.statusCode == 409) {
        await _recoverOpenSession(error);
      } else {
        _handleError(error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _closeSession() async {
    final session = _session;
    final id = toIntOrNull(session?['id']);
    final amount = double.tryParse(_closingAmount.replaceAll(',', '.'));
    if (id == null || amount == null || amount < 0) {
      setState(() => _error = 'Ingresa un saldo contado válido.');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar caja'),
        content: Text(
          'Saldo contado: ${_money(amount)}. ¿Confirmas el cierre de esta sesión?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Seguir revisando'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar caja'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await widget.api.put('/api/cash/sessions/$id/close', {
        'closing_balance': amount,
        'notes': _closingNotes.text.trim().isEmpty
            ? null
            : _closingNotes.text.trim(),
      });
      if (!mounted) return;
      setState(() {
        final summary = response['summary'] is Map
            ? (response['summary'] as Map).cast<String, dynamic>()
            : null;
        _closedSummary = summary == null
            ? null
            : {
                ...summary,
                'sales_by_payment_method': response['sales_by_payment_method'],
              };
        _session = null;
        _movements = const [];
        _paymentMethodTotals = const [];
      });
      await _loadHistory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Caja cerrada correctamente.')),
        );
      }
    } on ApiException catch (error) {
      _handleError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editMovement([Map<String, dynamic>? movement]) async {
    final session = _session;
    final id = toIntOrNull(movement?['id']);
    final manual =
        movement == null ||
        (movement['ref_type'] ?? '').toString().toUpperCase() == 'MANUAL';
    if (session == null || (movement != null && !manual)) return;

    final formKey = GlobalKey<FormState>();
    var type = (movement?['movement_type'] ?? 'IN').toString().toUpperCase();
    final amount = TextEditingController(
      text: movement == null
          ? ''
          : _number(movement['amount']).toStringAsFixed(2),
    );
    final description = TextEditingController(
      text: (movement?['description'] ?? '').toString(),
    );
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            movement == null ? 'Nuevo movimiento' : 'Editar movimiento',
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: const [
                    DropdownMenuItem(value: 'IN', child: Text('Ingreso')),
                    DropdownMenuItem(value: 'OUT', child: Text('Egreso')),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => type = value);
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(labelText: 'Monto ($_symbol)'),
                  validator: (value) {
                    final parsed = double.tryParse(
                      (value ?? '').replaceAll(',', '.'),
                    );
                    return parsed == null || parsed <= 0
                        ? 'Ingresa un monto mayor a cero.'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: description,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                  maxLength: 180,
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'La descripción es obligatoria.'
                      : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(context, {
                  'movement_type': type,
                  'amount': double.parse(amount.text.replaceAll(',', '.')),
                  'description': description.text.trim(),
                });
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    amount.dispose();
    description.dispose();
    if (payload == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (id == null) {
        await widget.api.post('/api/cash/movements', {
          ...payload,
          'cash_register_id': _registerId,
          'cash_session_id': toIntOrNull(session['id']),
        });
      } else {
        await widget.api.put('/api/cash/movements/$id', payload);
      }
      await _loadCurrent();
    } on ApiException catch (error) {
      _handleError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadSessionDetail(int sessionId) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.api.get(
        '/api/cash/sessions/$sessionId/detail',
      );
      if (mounted) {
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (context) =>
              _SessionDetailSheet(detail: response, money: _money),
        );
      }
    } on ApiException catch (error) {
      _handleError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isSalesMovement(Map<String, dynamic> movement) => const {
    'COMMERCIAL_DOCUMENT',
    'COMMERCIAL_DOCUMENT_EDIT',
    'COMMERCIAL_DOCUMENT_VOID',
    'INVOICE',
    'RECEIPT',
    'SALES_ORDER',
    'QUOTATION',
    'CREDIT_NOTE',
    'DEBIT_NOTE',
    'CUSTOMER_CREDIT_PAYMENT',
  }.contains((movement['ref_type'] ?? '').toString().trim().toUpperCase());

  bool _isCashPayment(Object? value) {
    return _isCashPaymentMethodName(value);
  }

  bool _isCashPaymentMethod(Map<String, dynamic> method) {
    return _cashMethodIsCash(method);
  }

  double get _manualInTotal => _movements
      .where(
        (row) =>
            !_isSalesMovement(row) &&
            (row['movement_type'] ?? '').toString().toUpperCase() == 'IN',
      )
      .fold(0, (sum, row) => sum + _number(row['amount']));

  double get _manualOutTotal => _movements
      .where(
        (row) =>
            !_isSalesMovement(row) &&
            (row['movement_type'] ?? '').toString().toUpperCase() == 'OUT',
      )
      .fold(0, (sum, row) => sum + _number(row['amount']));

  double get _salesCashInTotal => _movements
      .where(
        (row) =>
            _isSalesMovement(row) &&
            (row['movement_type'] ?? '').toString().toUpperCase() == 'IN' &&
            (row['is_cash_payment'] is bool
                ? row['is_cash_payment'] == true
                : _isCashPayment(row['payment_method_name'])),
      )
      .fold(0, (sum, row) => sum + _number(row['amount']));

  double get _digitalSalesTotal => _paymentMethodTotals
      .where((method) => !_isCashPaymentMethod(method))
      .fold(0, (sum, method) => sum + _number(method['total_amount']));

  double get _effectiveCashTotal =>
      _number(_session?['opening_balance']) +
      _manualInTotal -
      _manualOutTotal +
      _salesCashInTotal;

  String _date(Object? value) {
    if (value == null) return '—';
    final date = DateTime.tryParse(value.toString())?.toLocal();
    if (date == null) return value.toString();
    String two(int part) => part.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}';
  }

  Widget _metric(String label, Object? value, IconData icon, {Color? color}) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: color ?? Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.bodySmall),
                    Text(
                      _money(value),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildCurrentSession() {
    final session = _session;
    if (session == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.lock_open),
                title: Text('Caja cerrada'),
                subtitle: Text(
                  'Abre un turno para registrar cobros y movimientos.',
                ),
              ),
              TextFormField(
                initialValue: _openingAmount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Saldo inicial ($_symbol)',
                  prefixIcon: const Icon(Icons.savings_outlined),
                ),
                onChanged: (value) => _openingAmount = value,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _openingNotes,
                decoration: const InputDecoration(
                  labelText: 'Notas de apertura (opcional)',
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _openSession,
                  icon: const Icon(Icons.lock_open),
                  label: Text(_busy ? 'Abriendo caja...' : 'Abrir caja'),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final opening = _number(session['opening_balance']);
    final expected = _number(session['expected_balance']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: const Color(0xFFE9F5EE),
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.lock_open)),
            title: Text(
              (session['cash_register_name'] ??
                      session['cash_register_code'] ??
                      'Caja')
                  .toString(),
            ),
            subtitle: Text('Sesión abierta · ${_date(session['opened_at'])}'),
            trailing: const Chip(label: Text('ABIERTA')),
          ),
        ),
        _metric('Saldo inicial', opening, Icons.savings_outlined),
        _metric(
          'Mov. manuales (+)',
          _manualInTotal,
          Icons.south_west,
          color: Colors.green,
        ),
        _metric(
          'Mov. manuales (-)',
          _manualOutTotal,
          Icons.north_east,
          color: Colors.red,
        ),
        _metric(
          'Ventas efectivo',
          _salesCashInTotal,
          Icons.payments_outlined,
          color: Colors.green,
        ),
        _metric(
          'Pagos digitales (no efectivo)',
          _digitalSalesTotal,
          Icons.phone_android_outlined,
          color: Colors.blue,
        ),
        _metric(
          'Total efectivo',
          _effectiveCashTotal,
          Icons.account_balance_wallet_outlined,
        ),
        if (_paymentMethodTotals.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ventas por forma de pago',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  for (final method in _paymentMethodTotals)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        (method['payment_method_name'] ?? '-').toString(),
                      ),
                      subtitle: Text(
                        '${method['document_count']} comprobantes${_isCashPaymentMethod(method) ? ' · Efectivo' : ' · Digital, no incluido en el efectivo contado'}',
                      ),
                      trailing: Text(_money(method['total_amount'])),
                    ),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'TOTAL',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${_paymentMethodTotals.fold<int>(0, (total, method) => total + (toIntOrNull(method['document_count']) ?? 0))} comprobantes',
                    ),
                    trailing: Text(
                      _money(
                        _paymentMethodTotals.fold<double>(
                          0,
                          (total, method) =>
                              total + _number(method['total_amount']),
                        ),
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : () => _editMovement(),
              icon: const Icon(Icons.add),
              label: const Text('Movimiento'),
            ),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => setState(
                      () => _closingAmount = expected.toStringAsFixed(2),
                    ),
              icon: const Icon(Icons.calculate_outlined),
              label: const Text('Usar saldo esperado'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Movimientos de caja',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_movements.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Text('Aún no hay movimientos registrados.'),
                  )
                else
                  for (final movement in _movements)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        child: Icon(
                          (movement['movement_type'] ?? '')
                                      .toString()
                                      .toUpperCase() ==
                                  'IN'
                              ? Icons.south_west
                              : Icons.north_east,
                        ),
                      ),
                      title: Text(
                        (movement['description'] ?? 'Movimiento').toString(),
                      ),
                      subtitle: Text(
                        '${_date(movement['movement_at'])} · ${(movement['ref_type'] ?? 'MANUAL')}'
                        '\nForma de pago: ${(movement['payment_method_name'] ?? '-').toString().trim().isEmpty ? '-' : movement['payment_method_name']}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${(movement['movement_type'] ?? '').toString().toUpperCase() == 'IN' ? '+' : '-'}${_money(movement['amount'])}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color:
                                  (movement['movement_type'] ?? '')
                                          .toString()
                                          .toUpperCase() ==
                                      'IN'
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
                            ),
                          ),
                          if ((movement['ref_type'] ?? '')
                                  .toString()
                                  .toUpperCase() ==
                              'MANUAL')
                            IconButton(
                              tooltip: 'Editar movimiento',
                              onPressed: _busy
                                  ? null
                                  : () => _editMovement(movement),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cerrar turno',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: ValueKey('closing-$expected'),
                  initialValue: _closingAmount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Efectivo contado ($_symbol)',
                  ),
                  onChanged: (value) => _closingAmount = value,
                ),
                const SizedBox(height: 4),
                Text('Saldo esperado: ${_money(expected)}'),
                const SizedBox(height: 12),
                TextField(
                  controller: _closingNotes,
                  decoration: const InputDecoration(
                    labelText: 'Notas de cierre (opcional)',
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: _busy ? null : _closeSession,
                    icon: const Icon(Icons.lock),
                    label: Text(
                      _busy ? 'Cerrando...' : 'Revisar y cerrar caja',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHistory() {
    if (_history.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text('No hay sesiones de caja en el historial.'),
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final session in _history)
          Card(
            child: ListTile(
              leading: Icon(
                (session['status'] ?? '').toString().toUpperCase() == 'OPEN'
                    ? Icons.lock_open
                    : Icons.lock_outline,
              ),
              title: Text(
                'Sesión #${session['id']} · ${(session['status'] ?? '').toString().toUpperCase() == 'OPEN' ? 'Abierta' : 'Cerrada'}',
              ),
              subtitle: Text(
                '${_date(session['opened_at'])} · Apertura ${_money(session['opening_balance'])}'
                '${session['closed_at'] == null ? '' : ' · Cierre ${_date(session['closed_at'])}'}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                final id = toIntOrNull(session['id']);
                if (id != null) _loadSessionDetail(id);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildClosedSummary() {
    final summary = _closedSummary;
    if (summary == null) return const SizedBox.shrink();
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resumen del último cierre',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text('Saldo inicial: ${_money(summary['opening_balance'])}'),
            Text('Ingresos: ${_money(summary['total_in'])}'),
            Text(
              'Pagos digitales (no efectivo): ${_money(summary['digital_total_in'])}',
            ),
            Text('Egresos: ${_money(summary['total_out'])}'),
            Text('Esperado: ${_money(summary['expected_balance'])}'),
            Text('Contado: ${_money(summary['closing_balance'])}'),
            Text('Diferencia: ${_money(summary['difference'])}'),
            for (final method in _asRows(summary['sales_by_payment_method']))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text((method['payment_method_name'] ?? '—').toString()),
                subtitle: Text(
                  '${method['document_count'] ?? 0} comprobantes${_isCashPaymentMethod(method) ? ' · Efectivo' : ' · Digital, no incluido en efectivo'}',
                ),
                trailing: Text(_money(method['total_amount'])),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: widget.showAppBar
        ? AppBar(
            title: const Text('Caja'),
            actions: [
              IconButton(
                tooltip: 'Actualizar',
                onPressed: _loading ? null : _loadCurrent,
                icon: const Icon(Icons.refresh),
              ),
            ],
            bottom: TabBar(
              controller: _tabs,
              tabs: const [
                Tab(text: 'Sesión', icon: Icon(Icons.point_of_sale)),
                Tab(text: 'Historial', icon: Icon(Icons.history)),
              ],
            ),
          )
        : AppBar(
            toolbarHeight: 0,
            bottom: TabBar(
              controller: _tabs,
              tabs: const [
                Tab(text: 'Sesión', icon: Icon(Icons.point_of_sale)),
                Tab(text: 'Historial', icon: Icon(Icons.history)),
              ],
            ),
          ),
    body: _loading && _session == null && _history.isEmpty
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              if (_error != null)
                MaterialBanner(
                  content: Text(_error!),
                  leading: const Icon(Icons.error_outline),
                  actions: [
                    TextButton(
                      onPressed: () => setState(() => _error = null),
                      child: const Text('Cerrar'),
                    ),
                  ],
                ),
              if (_loading) const LinearProgressIndicator(),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    RefreshIndicator(
                      onRefresh: _loadCurrent,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _buildClosedSummary(),
                          _buildCurrentSession(),
                        ],
                      ),
                    ),
                    RefreshIndicator(
                      onRefresh: _loadHistory,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [_buildHistory()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
  );
}

class _SessionDetailSheet extends StatelessWidget {
  const _SessionDetailSheet({required this.detail, required this.money});

  final Map<String, dynamic> detail;
  final String Function(Object?) money;

  List<Map<String, dynamic>> _rows(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map((row) => row.cast<String, dynamic>())
            .toList()
      : const [];

  @override
  Widget build(BuildContext context) {
    final session = detail['session'] is Map
        ? (detail['session'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final summary = detail['summary'] is Map
        ? (detail['summary'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final movements = _rows(detail['movements']);
    final documents = _rows(detail['documents']);
    final methods = _rows(detail['payment_method_breakdown']);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Detalle de sesión #${session['id'] ?? ''}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text('Estado: ${session['status'] ?? '—'}'),
            Text('Saldo de apertura: ${money(session['opening_balance'])}'),
            Text('Saldo esperado: ${money(session['expected_balance'])}'),
            Text('Ingresos: ${money(summary['total_in'])}'),
            Text(
              'Pagos digitales (no efectivo): ${money(summary['digital_total_in'])}',
            ),
            Text('Egresos: ${money(summary['total_out'])}'),
            if (session['closing_balance'] != null)
              Text('Saldo de cierre: ${money(session['closing_balance'])}'),
            const Divider(height: 28),
            Text(
              'Movimientos (${movements.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final movement in movements)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  (movement['description'] ?? 'Movimiento').toString(),
                ),
                subtitle: Text((movement['movement_at'] ?? '').toString()),
                trailing: Text(money(movement['amount'])),
              ),
            const Divider(height: 28),
            Text(
              'Ventas por medio de pago',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final method in methods)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text((method['payment_method_name'] ?? '—').toString()),
                subtitle: Text(
                  '${method['document_count'] ?? 0} comprobantes${_cashMethodIsCash(method) ? ' · Efectivo' : ' · Digital'}',
                ),
                trailing: Text(money(method['total_amount'])),
              ),
            const Divider(height: 28),
            Text(
              'Comprobantes (${documents.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final document in documents)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  (document['document_number'] ??
                          document['document_kind_label'] ??
                          'Comprobante')
                      .toString(),
                ),
                subtitle: Text((document['customer_name'] ?? '').toString()),
                trailing: Text(money(document['total'])),
              ),
          ],
        ),
      ),
    );
  }
}
