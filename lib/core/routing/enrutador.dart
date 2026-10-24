import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/pantalla_inicio_sesion.dart';
import '../../features/mesas/presentation/pantalla_salon.dart';
import '../../features/mesas/presentacion/pantalla_cuenta_mesa.dart';
import '../../features/caja/presentation/pantalla_caja.dart';
import '../../features/cocina/presentation/pantalla_cocina.dart';
import '../../features/catalogo/presentacion/pantalla_carta.dart';
import '../../features/sales/presentation/sales_page.dart';
import '../auth/servicio_sesion.dart';

class Enrutador {
  static final Enrutador instancia = Enrutador._();
  Enrutador._();

  final ServicioSesion _sesion = ServicioSesion.instancia;

  late final GoRouter router = GoRouter(
    initialLocation: '/inicio-sesion',
    routes: [
      GoRoute(
        path: '/inicio-sesion',
        builder: (context, state) => const PantallaInicioSesion(),
      ),
      ShellRoute(
        builder: (context, state, child) => _CascaronNavegacion(child: child),
        routes: [
          GoRoute(
            path: '/mesas',
            builder: (context, state) => const PantallaSalon(),
          ),
          GoRoute(
            path: '/carta',
            builder: (context, state) => const PantallaCarta(),
          ),
          GoRoute(
            path: '/mostrador',
            builder: (context, state) => const SalesPage(),
          ),
          GoRoute(
            path: '/cocina',
            builder: (context, state) => const PantallaCocina(),
          ),
          GoRoute(
            path: '/caja',
            builder: (context, state) => const PantallaCaja(),
          ),
          GoRoute(
            path: '/mas',
            builder: (context, state) => const _PantallaMas(),
          ),
        ],
      ),
      GoRoute(
        path: '/cuenta-mesa',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final pedidoId = extra?['pedidoId'] as int? ?? 0;
          final nombreMesa = extra?['nombreMesa'] as String? ?? 'Mesa';
          return PantallaCuentaMesa(pedidoId: pedidoId, nombreMesa: nombreMesa);
        },
      ),
    ],
    redirect: (context, state) async {
      final haySesion = await _sesion.haySesion();
      final estaEnLogin = state.matchedLocation == '/inicio-sesion';
      if (!haySesion && !estaEnLogin) {
        return '/inicio-sesion';
      }
      if (haySesion && estaEnLogin) {
        return '/mesas';
      }
      return null;
    },
    refreshListenable: _EscuchadorSesion(),
  );
}

class _EscuchadorSesion extends ChangeNotifier {
  void notificar() {
    notifyListeners();
  }
}

class _CascaronNavegacion extends StatelessWidget {
  final Widget child;
  const _CascaronNavegacion({required this.child});

  @override
  Widget build(BuildContext context) {
    final ubicacion = GoRouterState.of(context).matchedLocation;
    int indice = 0;
    if (ubicacion.startsWith('/carta')) indice = 1;
    if (ubicacion.startsWith('/mostrador')) indice = 2;
    if (ubicacion.startsWith('/cocina')) indice = 3;
    if (ubicacion.startsWith('/caja')) indice = 4;
    if (ubicacion.startsWith('/mas')) indice = 5;

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: indice,
        onDestinationSelected: (i) {
          switch (i) {
            case 0:
              context.go('/mesas');
              break;
            case 1:
              context.go('/carta');
              break;
            case 2:
              context.go('/mostrador');
              break;
            case 3:
              context.go('/cocina');
              break;
            case 4:
              context.go('/caja');
              break;
            case 5:
              context.go('/mas');
              break;
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.table_restaurant_outlined), selectedIcon: Icon(Icons.table_restaurant), label: 'Mesas'),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Carta'),
          NavigationDestination(icon: Icon(Icons.point_of_sale_outlined), selectedIcon: Icon(Icons.point_of_sale), label: 'Mostrador'),
          NavigationDestination(icon: Icon(Icons.soup_kitchen_outlined), selectedIcon: Icon(Icons.soup_kitchen), label: 'Cocina'),
          NavigationDestination(icon: Icon(Icons.attach_money_outlined), selectedIcon: Icon(Icons.attach_money), label: 'Caja'),
          NavigationDestination(icon: Icon(Icons.more_horiz), selectedIcon: Icon(Icons.more_horiz), label: 'Más'),
        ],
      ),
    );
  }
}

class _PantallaMas extends StatelessWidget {
  const _PantallaMas();

  @override
  Widget build(BuildContext context) {
    final sesion = ServicioSesion.instancia;
    return Scaffold(
      appBar: AppBar(title: const Text('Más')),
      body: Center(
        child: FilledButton.icon(
          onPressed: () async {
            await sesion.cerrarSesion();
            if (context.mounted) context.go('/inicio-sesion');
          },
          icon: const Icon(Icons.logout),
          label: const Text('Cerrar sesión'),
        ),
      ),
    );
  }
}
