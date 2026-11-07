import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';
import '../data/customers_repository.dart';
import '../domain/customer.dart';

class CustomerFormPage extends StatefulWidget {
  const CustomerFormPage({
    required this.repository,
    required this.workshopEnabled,
    this.customer,
    super.key,
  });

  final CustomersRepository repository;
  final bool workshopEnabled;
  final Customer? customer;

  @override
  State<CustomerFormPage> createState() => _CustomerFormPageState();
}

class _CustomerFormPageState extends State<CustomerFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _docController = TextEditingController();
  final _nameController = TextEditingController();
  final _tradeController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();

  List<CustomerType> _types = const [];
  List<CustomerVehicle> _vehicles = const [];
  int? _customerId;
  int? _typeId;
  bool _active = true;
  bool _saving = false;
  bool _resolving = false;
  bool _changed = false;

  bool get _isEditing => _customerId != null;
  CustomerType? get _type => _types.where((t) => t.id == _typeId).firstOrNull;

  @override
  void initState() {
    super.initState();
    final c = widget.customer;
    if (c != null) {
      _customerId = c.id;
      _typeId = c.customerTypeId;
      _active = c.isActive;
      _docController.text = c.docNumber ?? '';
      _nameController.text = c.name;
      _tradeController.text = c.tradeName ?? '';
      _addressController.text = c.address ?? '';
      _phoneController.text = c.phone ?? '';
    }
    _bootstrap();
  }

  @override
  void dispose() {
    _docController.dispose();
    _nameController.dispose();
    _tradeController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final types = await widget.repository.types();
      if (!mounted) return;
      setState(() {
        _types = types;
        _typeId ??= types.isEmpty ? null : types.first.id;
      });
      if (_isEditing && widget.workshopEnabled) await _loadVehicles();
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _loadVehicles() async {
    try {
      final rows = await widget.repository.vehicles(_customerId!);
      if (mounted) setState(() => _vehicles = rows);
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  bool get _canResolve {
    final doc = _docController.text.trim();
    return doc.length == 8 || doc.length == 11;
  }

  Future<void> _resolveDocument() async {
    setState(() => _resolving = true);
    try {
      final found = await widget.repository.resolveDocument(
        _docController.text,
      );
      if (!mounted) return;
      setState(() {
        _nameController.text = found.name;
        if ((found.address ?? '').isNotEmpty) {
          _addressController.text = found.address!;
        }
        if (found.customerTypeId != null) _typeId = found.customerTypeId;
      });
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final payload = {
      'doc_type': _type == null ? null : '${_type!.sunatCode}',
      'customer_type_id': _typeId,
      'doc_number': _docController.text.trim(),
      'legal_name': _nameController.text.trim(),
      'trade_name': _tradeController.text.trim(),
      'address': _addressController.text.trim(),
      'phone': _phoneController.text.trim(),
      'status': _active ? 1 : 0,
    };

    setState(() => _saving = true);
    try {
      if (_isEditing) {
        await widget.repository.update(_customerId!, payload);
        _changed = true;
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      final id = await widget.repository.create(payload);
      _changed = true;
      if (!mounted) return;
      if (widget.workshopEnabled && id != null) {
        // En taller se permanece en el cliente para registrar sus vehículos.
        setState(() => _customerId = id);
        _toast('Cliente creado. Ahora puede agregar sus vehículos.');
      } else {
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editVehicle([CustomerVehicle? vehicle]) async {
    final saved = await showVehicleSheet(
      context,
      repository: widget.repository,
      customerId: _customerId!,
      vehicle: vehicle,
    );
    if (saved == true) _loadVehicles();
  }

  Future<void> _deleteVehicle(CustomerVehicle vehicle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar vehículo'),
        content: Text('¿Eliminar ${vehicle.plate}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.deleteVehicle(_customerId!, vehicle.id);
      _loadVehicles();
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEditing ? 'Editar cliente' : 'Nuevo cliente'),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: const Text('Guardar'),
            ),
          ),
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: _types.any((t) => t.id == _typeId)
                    ? _typeId
                    : null,
                decoration: const InputDecoration(labelText: 'Tipo de cliente'),
                items: [
                  for (final t in _types)
                    DropdownMenuItem(value: t.id, child: Text(t.name)),
                ],
                onChanged: (value) => setState(() => _typeId = value),
                validator: (v) => v == null ? 'Seleccione un tipo' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _docController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Nº de documento',
                  suffixIcon: _resolving
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          tooltip: 'Buscar en RENIEC / SUNAT',
                          icon: const Icon(Icons.manage_search),
                          onPressed: _canResolve ? _resolveDocument : null,
                        ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nombre / Razón social',
                ),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Ingrese el nombre' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tradeController,
                decoration: const InputDecoration(
                  labelText: 'Nombre comercial',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(labelText: 'Dirección'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Teléfono'),
              ),
              if (_isEditing)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Cliente activo'),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
              if (widget.workshopEnabled) ...[
                const Divider(height: 32),
                Row(
                  children: [
                    const Icon(Icons.directions_car_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Vehículos',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (_isEditing)
                      TextButton.icon(
                        onPressed: () => _editVehicle(),
                        icon: const Icon(Icons.add),
                        label: const Text('Agregar'),
                      ),
                  ],
                ),
                if (!_isEditing)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Guarde el cliente para registrar sus vehículos.',
                    ),
                  )
                else if (_vehicles.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Sin vehículos registrados.'),
                  )
                else
                  for (final v in _vehicles)
                    Card(
                      margin: const EdgeInsets.only(top: 8),
                      child: ListTile(
                        onTap: () => _editVehicle(v),
                        leading: Icon(
                          v.isDefault ? Icons.star : Icons.directions_car,
                        ),
                        title: Text(v.label),
                        subtitle: Text(
                          [
                            if (v.year != null) '${v.year}',
                            if ((v.color ?? '').isNotEmpty) v.color!,
                            if ((v.vin ?? '').isNotEmpty) 'VIN ${v.vin}',
                          ].join(' · '),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _deleteVehicle(v),
                        ),
                      ),
                    ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool?> showVehicleSheet(
  BuildContext context, {
  required CustomersRepository repository,
  required int customerId,
  CustomerVehicle? vehicle,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _VehicleSheet(
    repository: repository,
    customerId: customerId,
    vehicle: vehicle,
  ),
);

class _VehicleSheet extends StatefulWidget {
  const _VehicleSheet({
    required this.repository,
    required this.customerId,
    this.vehicle,
  });

  final CustomersRepository repository;
  final int customerId;
  final CustomerVehicle? vehicle;

  @override
  State<_VehicleSheet> createState() => _VehicleSheetState();
}

class _VehicleSheetState extends State<_VehicleSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _plate = TextEditingController(text: widget.vehicle?.plate);
  late final _brand = TextEditingController(text: widget.vehicle?.brand);
  late final _model = TextEditingController(text: widget.vehicle?.model);
  late final _year = TextEditingController(
    text: widget.vehicle?.year?.toString(),
  );
  late final _color = TextEditingController(text: widget.vehicle?.color);
  late final _vin = TextEditingController(text: widget.vehicle?.vin);
  late bool _isDefault = widget.vehicle?.isDefault ?? false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_plate, _brand, _model, _year, _color, _vin]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    String? text(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    final payload = {
      'plate': _plate.text.trim().toUpperCase(),
      'brand': text(_brand),
      'model': text(_model),
      'year': int.tryParse(_year.text.trim()),
      'color': text(_color),
      'vin': text(_vin),
      'is_default': _isDefault,
    };
    setState(() => _saving = true);
    try {
      if (widget.vehicle == null) {
        await widget.repository.createVehicle(widget.customerId, payload);
      } else {
        await widget.repository.updateVehicle(
          widget.customerId,
          widget.vehicle!.id,
          payload,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.vehicle == null ? 'Nuevo vehículo' : 'Editar vehículo',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _plate,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Placa'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Ingrese la placa' : null,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _brand,
                      decoration: const InputDecoration(labelText: 'Marca'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _model,
                      decoration: const InputDecoration(labelText: 'Modelo'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _year,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Año'),
                      validator: (v) {
                        final value = int.tryParse((v ?? '').trim());
                        if ((v ?? '').trim().isEmpty) return null;
                        return value == null || value < 1900 || value > 2100
                            ? 'Año inválido'
                            : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _color,
                      decoration: const InputDecoration(labelText: 'Color'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _vin,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'VIN / Chasis'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Vehículo principal'),
                value: _isDefault,
                onChanged: (v) => setState(() => _isDefault = v),
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: const Text('Guardar vehículo'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
