import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';
import '../../../core/session/app_context.dart';
import '../data/customers_repository.dart';
import '../domain/customer.dart';
import 'customer_form_page.dart';

class CustomersPage extends StatefulWidget {
  const CustomersPage({
    required this.repository,
    required this.appContext,
    required this.onUnauthorized,
    super.key,
  });

  final CustomersRepository repository;
  final AppContext appContext;
  final VoidCallback onUnauthorized;

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  final _searchController = TextEditingController();
  List<Customer> _customers = const [];
  bool _loading = true;
  String? _error;
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_requestSeq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.repository.list(query: _searchController.text);
      if (!mounted || seq != _requestSeq) return;
      setState(() => _customers = rows);
    } on ApiException catch (e) {
      if (e.isUnauthorized) return widget.onUnauthorized();
      if (mounted && seq == _requestSeq) setState(() => _error = e.message);
    } finally {
      if (mounted && seq == _requestSeq) setState(() => _loading = false);
    }
  }

  Future<void> _open([Customer? customer]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CustomerFormPage(
          repository: widget.repository,
          workshopEnabled: widget.appContext.workshopEnabled,
          customer: customer,
        ),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _toggleStatus(Customer customer) async {
    try {
      await widget.repository.update(customer.id, {
        'status': customer.isActive ? 0 : 1,
      });
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clientes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Nuevo'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SearchBar(
              controller: _searchController,
              hintText: 'Buscar por nombre o documento',
              leading: const Icon(Icons.search),
              trailing: [
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _searchController.clear();
                      _load();
                    },
                  ),
              ],
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _load(),
              textInputAction: TextInputAction.search,
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            TextButton(onPressed: _load, child: const Text('Reintentar')),
          ],
        ),
      );
    }
    if (_customers.isEmpty) {
      return const Center(child: Text('No hay clientes para mostrar.'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
        itemCount: _customers.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final customer = _customers[index];
          return Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              onTap: () => _open(customer),
              title: Text(
                customer.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: customer.isActive ? null : Colors.grey,
                ),
              ),
              subtitle: Text(
                [
                  customer.documentLabel,
                  if ((customer.phone ?? '').isNotEmpty) customer.phone!,
                ].join(' · '),
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (value) =>
                    value == 'edit' ? _open(customer) : _toggleStatus(customer),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Editar')),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(customer.isActive ? 'Desactivar' : 'Activar'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
