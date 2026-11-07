import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../core/api/api_client.dart';
import '../../../core/session/app_context.dart';
import '../../../core/time/lima_time.dart';
import '../data/sales_documents_repository.dart';
import 'sales_ticket_pdf.dart';

class SalesReportPage extends StatefulWidget {
  const SalesReportPage({
    required this.repository,
    required this.appContext,
    required this.onUnauthorized,
    super.key,
  });

  final SalesDocumentsRepository repository;
  final AppContext appContext;
  final VoidCallback onUnauthorized;

  @override
  State<SalesReportPage> createState() => _SalesReportPageState();
}

class _SalesReportPageState extends State<SalesReportPage> {
  final _customerController = TextEditingController();
  final _vehicleController = TextEditingController();
  final _items = <SaleDocument>[];
  DocumentFilters _filters = const DocumentFilters();
  int _page = 1;
  int _lastPage = 1;
  int _total = 0;
  bool _loading = false;
  int _requestId = 0;
  int? _printingDocumentId;
  String? _error;

  static const _tabLabels = {
    DocumentTab.all: 'Todos',
    DocumentTab.tributary: 'Comprobantes',
    DocumentTab.orders: 'Pedidos',
    DocumentTab.pending: 'Por convertir',
    DocumentTab.converted: 'Convertidos',
  };

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _customerController.dispose();
    _vehicleController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    _requestId++;
    setState(() {
      _items.clear();
      _page = 1;
      _lastPage = 1;
      _total = 0;
      _error = null;
      _loading = false;
    });
    await _loadPage(1, force: true);
  }

  Future<void> _loadPage(int page, {bool force = false}) async {
    if ((!force && _loading) || page < 1 || page > _lastPage) return;
    final requestId = ++_requestId;
    final filters = _filters;
    setState(() => _loading = true);
    try {
      final result = await widget.repository.fetch(filters, page: page);
      if (!mounted || requestId != _requestId || filters != _filters) return;
      setState(() {
        _items
          ..clear()
          ..addAll(result.items);
        _page = result.page;
        _lastPage = result.lastPage;
        _total = result.total;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted || requestId != _requestId) return;
      if (e.isUnauthorized) return widget.onUnauthorized();
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted && requestId == _requestId) {
        setState(() => _loading = false);
      }
    }
  }

  void _apply(DocumentFilters filters) {
    _filters = filters;
    _loading = false;
    _reload();
  }

  Future<void> _pickRange() async {
    final now = limaNow();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: _filters.from == null
          ? null
          : DateTimeRange(start: _filters.from!, end: _filters.to ?? now),
    );
    if (range != null) {
      _apply(_filters.copyWith(from: range.start, to: range.end));
    }
  }

  String _dateLabel(DateTime? d) => d == null
      ? '-'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _kindLabel(String code) {
    final match = widget.appContext.documentKinds.where((k) => k.code == code);
    return match.isEmpty ? code : match.first.label;
  }

  bool _isTributaryDocument(String code) =>
      widget.appContext.isTributaryDocument(code);

  String _statusLabel(String status) =>
      const {
        'ISSUED': 'Emitido',
        'DRAFT': 'Borrador',
        'PAID': 'Pagado',
        'VOID': 'Anulado',
        'VOIDED': 'Anulado',
        'CANCELLED': 'Anulado',
        'CANCELED': 'Anulado',
        'PENDING': 'Pendiente',
      }[status.toUpperCase()] ??
      status;

  String _sunatLabel(String status) =>
      const {
        'ACCEPTED': 'Aceptado',
        'PENDING': 'Pendiente',
        'REJECTED': 'Rechazado',
        'NOT_SENT': 'No enviado',
        'SENT': 'Enviado',
        'SENDING': 'Enviando',
        'PROCESSING': 'Procesando',
        'PENDING_CONFIRMATION': 'Pendiente de confirmación',
        'EXPIRED_WINDOW': 'Fuera de plazo',
        'HTTP_ERROR': 'Error HTTP',
        'NETWORK_ERROR': 'Error de red',
        'ERROR': 'Error',
      }[status.toUpperCase()] ??
      status;

  Color _sunatColor(String? status) {
    switch (status?.toUpperCase()) {
      case 'ACCEPTED':
        return Colors.green;
      case 'REJECTED':
      case 'ERROR':
      case 'HTTP_ERROR':
      case 'NETWORK_ERROR':
        return Colors.red;
      case 'PENDING':
      case 'PENDING_CONFIRMATION':
      case 'SENDING':
      case 'PROCESSING':
        return Colors.orange;
      default:
        return Colors.blueGrey;
    }
  }

  Color _statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'ISSUED':
      case 'PAID':
        return Colors.green;
      case 'DRAFT':
        return Colors.orange;
      case 'VOID':
      case 'VOIDED':
      case 'CANCELLED':
        return Colors.red;
      default:
        return Colors.blueGrey;
    }
  }

  void _showDetail(SaleDocument d) {
    final symbol = widget.appContext.defaultCurrency?.symbol ?? 'S/';
    final rows = <MapEntry<String, String?>>[
      MapEntry('Cliente', d.customerName),
      MapEntry('Documento', d.customerDocNumber),
      MapEntry('Fecha', _dateLabel(d.issueAt)),
      MapEntry('Estado', _statusLabel(d.status)),
      if (_isTributaryDocument(d.documentKind))
        MapEntry(
          'SUNAT',
          d.sunatStatus == null ? null : _sunatLabel(d.sunatStatus!),
        ),
      MapEntry('Medio de pago', d.paymentMethod),
      MapEntry('Vendedor', d.createdBy),
      if (widget.appContext.workshopEnabled) ...[
        MapEntry('Placa', d.plate),
        MapEntry('Vehículo', d.vehicleLabel),
      ],
      MapEntry('Total', '$symbol ${d.total.toStringAsFixed(2)}'),
      MapEntry('Saldo', '$symbol ${d.balanceDue.toStringAsFixed(2)}'),
    ];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              '${_kindLabel(d.documentKind)} ${d.fullNumber}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            for (final r in rows)
              if ((r.value ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 96,
                        child: Text(
                          r.key,
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ),
                      Expanded(child: Text(r.value!)),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _printTicket(SaleDocument document) async {
    if (_printingDocumentId != null) return;
    setState(() => _printingDocumentId = document.id);
    try {
      final companyName = widget.appContext.companyName;
      final items = await widget.repository.fetchItems(document.id);
      final showSunatStatus = _isTributaryDocument(document.documentKind);
      final bytes = await buildSalesTicketPdf(
        document,
        documentKindLabel: _kindLabel(document.documentKind),
        companyName: companyName,
        currencySymbol: widget.appContext.defaultCurrency?.symbol ?? 'S/',
        statusLabel: _statusLabel(document.status),
        sunatStatusLabel:
            document.sunatStatus == null || document.sunatStatus!.isEmpty
            ? 'Sin envío'
            : _sunatLabel(document.sunatStatus!),
        items: items,
        showSunatStatus: showSunatStatus,
      );
      if (!mounted) return;
      await Printing.layoutPdf(
        name: 'Ticket_${document.fullNumber}',
        format: salesTicketPageFormat(
          document,
          companyName: companyName,
          items: items,
          showSunatStatus: showSunatStatus,
        ),
        dynamicLayout: false,
        onLayout: (_) async => bytes,
      );
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        widget.onUnauthorized();
      } else {
        _toast('No se pudo cargar el detalle del ticket: ${e.message}');
      }
    } catch (e) {
      _toast('No se pudo abrir la impresión del ticket: $e');
    } finally {
      if (mounted) setState(() => _printingDocumentId = null);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final workshop = widget.appContext.workshopEnabled;
    final symbol = widget.appContext.defaultCurrency?.symbol ?? 'S/';
    final sum = _items.fold<double>(0, (a, d) => a + d.total);
    final firstItem = _total == 0
        ? 0
        : ((_page - 1) * SalesDocumentsRepository.pageSize) + 1;
    final lastItem = math.min(
      _page * SalesDocumentsRepository.pageSize,
      _total,
    );

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Reporte de ventas'),
        actions: [
          IconButton(
            tooltip: 'Rango de fechas',
            icon: Icon(
              _filters.from == null
                  ? Icons.date_range_outlined
                  : Icons.date_range,
            ),
            onPressed: _pickRange,
          ),
          if (_filters.from != null)
            IconButton(
              tooltip: 'Quitar fechas',
              icon: const Icon(Icons.close),
              onPressed: () => _apply(_filters.copyWith(clearDates: true)),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customerController,
                    decoration: const InputDecoration(
                      hintText: 'Buscar cliente',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (v) => _apply(_filters.copyWith(customer: v)),
                  ),
                ),
                if (workshop) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _vehicleController,
                      decoration: const InputDecoration(
                        hintText: 'Placa',
                        prefixIcon: Icon(Icons.directions_car_outlined),
                        isDense: true,
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: (v) => _apply(_filters.copyWith(vehicle: v)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Wrap(
              spacing: 6,
              children: [
                for (final entry in _tabLabels.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: _filters.tab == entry.key,
                    onSelected: (_) =>
                        _apply(_filters.copyWith(tab: entry.key)),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Row(
              children: [
                Text('$_total documentos'),
                const Spacer(),
                Text(
                  'Esta página: $symbol ${sum.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _reload,
              child: _items.isEmpty && !_loading
                  ? ListView(
                      children: [
                        const SizedBox(height: 80),
                        Center(
                          child: Text(
                            _error ?? 'No hay documentos para mostrar.',
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: _items.length,
                      itemBuilder: (context, i) {
                        final d = _items[i];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _showDetail(d),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${_kindLabel(d.documentKind)} · ${d.fullNumber}',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '$symbol ${d.total.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    d.customerName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    [
                                      _dateLabel(d.issueAt),
                                      if (workshop &&
                                          (d.plate ?? '').isNotEmpty)
                                        d.plate!,
                                    ].join(' · '),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      _statusChip(
                                        _statusLabel(d.status),
                                        _statusColor(d.status),
                                      ),
                                      if (_isTributaryDocument(d.documentKind))
                                        _statusChip(
                                          'SUNAT: ${d.sunatStatus == null || d.sunatStatus!.isEmpty ? 'Sin envío' : _sunatLabel(d.sunatStatus!)}',
                                          _sunatColor(d.sunatStatus),
                                        ),
                                      if ((d.paymentMethod ?? '').isNotEmpty)
                                        Chip(
                                          avatar: const Icon(
                                            Icons.payment_outlined,
                                            size: 16,
                                          ),
                                          label: Text(
                                            'Medio de pago: ${d.paymentMethod}',
                                          ),
                                          visualDensity: VisualDensity.compact,
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                    ],
                                  ),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: _printingDocumentId == null
                                          ? () => _printTicket(d)
                                          : null,
                                      icon: _printingDocumentId == d.id
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons.print_outlined),
                                      label: Text(
                                        _printingDocumentId == d.id
                                            ? 'Preparando…'
                                            : 'Imprimir ticket',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Página anterior',
                  onPressed: _loading || _page <= 1
                      ? null
                      : () => _loadPage(_page - 1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    _total == 0
                        ? 'Página $_page de $_lastPage'
                        : 'Mostrando $firstItem-$lastItem de $_total\nPágina $_page de $_lastPage',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Página siguiente',
                  onPressed: _loading || _page >= _lastPage
                      ? null
                      : () => _loadPage(_page + 1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String label, Color color) => Chip(
    label: Text(label),
    labelStyle: TextStyle(color: color, fontSize: 12),
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    side: BorderSide(color: color.withValues(alpha: 0.35)),
    backgroundColor: color.withValues(alpha: 0.08),
  );
}
