import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/session/app_context.dart';
import '../../core/session/app_menu.dart';
import '../products/products_page.dart';
import '../sales/data/sales_documents_repository.dart';
import '../sales/presentation/sales_report_page.dart';
import '../auth/domain/auth_session.dart';
import '../customers/data/customers_repository.dart';
import '../customers/presentation/customers_page.dart';
import '../sales/data/sales_repository.dart';
import '../sales/presentation/sales_page.dart';
import '../restaurant/presentation/restaurant_pages.dart';
import '../restaurant/presentation/restaurant_cash_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    required this.session,
    required this.onLogout,
    this.apiClient,
    super.key,
  });

  final AuthSession session;
  final VoidCallback onLogout;
  final ApiClient? apiClient;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final ApiClient _api =
      widget.apiClient ?? ApiClient(accessToken: widget.session.accessToken);
  late final CustomersRepository _customers = CustomersRepository(_api);
  late final ValueNotifier<int> _restaurantCashRefresh = ValueNotifier(0);
  AppContext? _context;
  String? _error;
  int _tab = 0;

  @override
  void dispose() {
    _restaurantCashRefresh.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final context = await AppContext.load(_api);
      if (mounted) setState(() => _context = context);
    } on ApiException catch (e) {
      if (e.isUnauthorized) return widget.onLogout();
      if (mounted) setState(() => _error = e.message);
    } on FormatException catch (error, stackTrace) {
      _showLoadError(error, stackTrace);
    } on TypeError catch (error, stackTrace) {
      _showLoadError(error, stackTrace);
    } on StateError catch (error, stackTrace) {
      _showLoadError(error, stackTrace);
    }
  }

  void _showLoadError(Object error, StackTrace stackTrace) {
    debugPrint('Failed to load app context: $error');
    debugPrintStack(stackTrace: stackTrace);
    if (mounted) {
      setState(
        () => _error =
            'No se pudo interpretar la información recibida. Reintenta o cierra sesión.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appContext = _context;
    if (appContext == null) {
      return Scaffold(
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _load,
                        child: const Text('Reintentar'),
                      ),
                      TextButton(
                        onPressed: widget.onLogout,
                        child: const Text('Cerrar sesión'),
                      ),
                    ],
                  ),
                ),
        ),
      );
    }

    final name = '${widget.session.firstName} ${widget.session.lastName}'
        .trim();
    final vertical = appContext.verticalCode.toUpperCase();
    final isRestaurant = vertical == 'RESTAURANT';
    if (isRestaurant) {
      final restaurantModules = restaurantMenu(appContext);
      final selectedIndex = restaurantModules.isEmpty
          ? 0
          : _tab.clamp(0, restaurantModules.length - 1);

      Widget restaurantPage(MenuEntry entry) {
        switch (entry.id) {
          case 'restaurant-orders':
            return RestaurantOrdersPage(
              api: _api,
              appContext: appContext,
              customers: _customers,
              onUnauthorized: widget.onLogout,
              onPaymentClosed: () => _restaurantCashRefresh.value++,
              showAppBar: false,
            );
          case 'cash':
            return RestaurantCashPage(
              api: _api,
              appContext: appContext,
              onUnauthorized: widget.onLogout,
              refreshNotifier: _restaurantCashRefresh,
              showAppBar: false,
            );
          case 'tables':
            return RestaurantTablesPage(
              api: _api,
              appContext: appContext,
              onUnauthorized: widget.onLogout,
              showAppBar: false,
            );
          case 'restaurant-menu':
            return RestaurantMenuPage(
              api: _api,
              appContext: appContext,
              onUnauthorized: widget.onLogout,
              showAppBar: false,
            );
          default:
            return const SizedBox.shrink();
        }
      }

      return Scaffold(
        appBar: AppBar(
          title: Text(
            restaurantModules.isEmpty
                ? 'Restaurante'
                : restaurantModules[selectedIndex].labelFor(vertical),
          ),
          actions: [
            IconButton(
              tooltip: 'Cerrar sesión',
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        body: restaurantModules.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Tu usuario aún no tiene permisos para los módulos de restaurante.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : IndexedStack(
                index: selectedIndex,
                children: [
                  for (final item in restaurantModules) restaurantPage(item),
                ],
              ),
        bottomNavigationBar: restaurantModules.isEmpty
            ? null
            : NavigationBar(
                selectedIndex: selectedIndex,
                onDestinationSelected: (index) => setState(() => _tab = index),
                destinations: [
                  for (final item in restaurantModules)
                    NavigationDestination(
                      icon: Icon(item.icon),
                      label:
                          item.id == 'restaurant-orders' &&
                              appContext.restaurantQuickSaleEnabled
                          ? 'Venta rápida'
                          : item.labelFor(vertical),
                    ),
                ],
              ),
      );
    }
    final menu = visibleMenu(appContext);
    final live = menu.where((e) => e.implemented).toList();
    final soon = menu.where((e) => !e.implemented).toList();
    final index = _tab.clamp(0, live.length);

    Widget pageFor(MenuEntry e) {
      switch (e.action) {
        case MenuAction.sales:
          return SalesPage(
            repository: SalesRepository(_api, appContext),
            customers: _customers,
            appContext: appContext,
            onUnauthorized: widget.onLogout,
          );
        case MenuAction.salesReport:
          return SalesReportPage(
            repository: SalesDocumentsRepository(_api, appContext),
            appContext: appContext,
            onUnauthorized: widget.onLogout,
          );
        case MenuAction.customers:
          return CustomersPage(
            repository: _customers,
            appContext: appContext,
            onUnauthorized: widget.onLogout,
          );
        case MenuAction.products:
          return ProductsPage(
            api: _api,
            appContext: appContext,
            onUnauthorized: widget.onLogout,
          );
        case MenuAction.restaurantOrders:
        case MenuAction.restaurantTables:
        case MenuAction.restaurantMenu:
        case MenuAction.none:
          return const SizedBox.shrink();
      }
    }

    return Scaffold(
      body: IndexedStack(
        index: index,
        children: [
          for (final e in live) pageFor(e),
          _AccountTab(
            userName: name.isEmpty ? widget.session.username : name,
            appContext: appContext,
            soon: [for (final e in soon) e.labelFor(vertical)],
            onLogout: widget.onLogout,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          for (final e in live)
            NavigationDestination(
              icon: Icon(e.icon),
              label: e.labelFor(vertical),
            ),
          const NavigationDestination(icon: Icon(Icons.menu), label: 'Más'),
        ],
      ),
    );
  }
}

class _AccountTab extends StatelessWidget {
  const _AccountTab({
    required this.userName,
    required this.appContext,
    required this.soon,
    required this.onLogout,
  });

  final String userName;
  final AppContext appContext;
  final List<String> soon;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Más')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(userName),
            subtitle: Text(appContext.companyName),
          ),
          if (appContext.verticalName.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.store_outlined),
              title: const Text('Tipo de empresa'),
              subtitle: Text(
                '${appContext.verticalName} (${appContext.verticalCode})'
                '${appContext.workshopEnabled ? ' · datos de taller activos' : ' · datos de taller desactivados (flag SALES_WORKSHOP_MULTI_VEHICLE)'}',
              ),
            ),
          if (soon.isNotEmpty) ...[
            const Divider(),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('Próximamente en la app'),
            ),
            for (final label in soon)
              ListTile(
                enabled: false,
                leading: const Icon(Icons.hourglass_empty),
                title: Text(label),
              ),
            const Divider(),
          ],
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Cerrar sesión'),
            onTap: onLogout,
          ),
        ],
      ),
    );
  }
}
