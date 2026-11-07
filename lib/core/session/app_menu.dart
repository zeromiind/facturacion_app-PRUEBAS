import 'package:flutter/material.dart';

import 'app_context.dart';

enum MenuAction {
  sales,
  salesReport,
  customers,
  products,
  restaurantOrders,
  restaurantTables,
  restaurantMenu,
  none,
}

class MenuEntry {
  const MenuEntry({
    required this.id,
    required this.label,
    required this.moduleCode,
    required this.icon,
    this.action = MenuAction.none,
    this.onlyVerticals = const [],
    this.verticalLabels = const {},
  });

  final String id;
  final String label;
  final String moduleCode;
  final IconData icon;
  final MenuAction action;
  final List<String> onlyVerticals;
  final Map<String, String> verticalLabels;

  bool get implemented => action != MenuAction.none;

  String labelFor(String vertical) => verticalLabels[vertical] ?? label;
}

/// Espejo del MENU_ITEMS / HIDDEN_TABS_BY_VERTICAL de la web.
const menuCatalog = <MenuEntry>[
  MenuEntry(
    id: 'sales',
    label: 'Venta',
    moduleCode: 'SALES',
    icon: Icons.point_of_sale,
    action: MenuAction.sales,
  ),
  MenuEntry(
    id: 'sales-report',
    label: 'Reportes',
    moduleCode: 'SALES',
    icon: Icons.receipt_long,
    action: MenuAction.salesReport,
  ),
  MenuEntry(
    id: 'customers',
    label: 'Clientes',
    moduleCode: 'SALES',
    icon: Icons.people,
    action: MenuAction.customers,
    verticalLabels: {
      'RESTAURANT': 'Comensales',
      'RACING_OPERATIONS': 'Terceros',
    },
  ),
  MenuEntry(
    id: 'cash',
    label: 'Caja',
    moduleCode: 'SALES',
    icon: Icons.account_balance_wallet_outlined,
    verticalLabels: {'RESTAURANT': 'Caja'},
  ),
  MenuEntry(
    id: 'daily-summary',
    label: 'Resumen diario',
    moduleCode: 'SALES',
    icon: Icons.summarize_outlined,
  ),
  MenuEntry(
    id: 'gre-guides',
    label: 'Guías de remisión',
    moduleCode: 'SALES',
    icon: Icons.local_shipping_outlined,
  ),
  MenuEntry(
    id: 'inventory',
    label: 'Inventario',
    moduleCode: 'INVENTORY',
    icon: Icons.inventory_2_outlined,
    verticalLabels: {'RESTAURANT': 'Insumos y Bodega'},
  ),
  MenuEntry(
    id: 'purchases',
    label: 'Compras',
    moduleCode: 'INVENTORY',
    icon: Icons.shopping_cart_outlined,
  ),
  MenuEntry(
    id: 'products',
    label: 'Productos',
    moduleCode: 'INVENTORY',
    icon: Icons.category_outlined,
    action: MenuAction.products,
  ),
  MenuEntry(
    id: 'restaurant-orders',
    label: 'Pedidos',
    moduleCode: 'SALES',
    icon: Icons.receipt_long_outlined,
    action: MenuAction.restaurantOrders,
    onlyVerticals: ['RESTAURANT'],
  ),
  MenuEntry(
    id: 'comandas',
    label: 'Comandas',
    moduleCode: 'SALES',
    icon: Icons.restaurant_menu,
    onlyVerticals: ['RESTAURANT'],
  ),
  MenuEntry(
    id: 'tables',
    label: 'Mesas',
    moduleCode: 'SALES',
    icon: Icons.table_restaurant_outlined,
    action: MenuAction.restaurantTables,
    onlyVerticals: ['RESTAURANT'],
  ),
  MenuEntry(
    id: 'restaurant-menu',
    label: 'Menú',
    moduleCode: 'INVENTORY',
    icon: Icons.restaurant_menu,
    action: MenuAction.restaurantMenu,
    onlyVerticals: ['RESTAURANT'],
  ),
  MenuEntry(
    id: 'racing-ops',
    label: 'Operaciones',
    moduleCode: 'SALES',
    icon: Icons.sports_motorsports_outlined,
    onlyVerticals: ['RACING_OPERATIONS'],
  ),
];

const hiddenByVertical = <String, Set<String>>{
  'RETAIL': {'comandas', 'tables'},
  'RESTAURANT': {
    'sales',
    'sales-report',
    'customers',
    'comandas',
    'daily-summary',
    'gre-guides',
    'inventory',
    'purchases',
    'products',
  },
  'SERVICES': {'inventory', 'purchases', 'gre-guides'},
  'WORKSHOP': {'daily-summary', 'gre-guides'},
};

const _sellerHidden = {'cash', 'daily-summary', 'gre-guides'};

bool isMenuVisible(MenuEntry item, AppContext ctx) {
  final vertical = ctx.verticalCode.toUpperCase();
  if (item.onlyVerticals.isNotEmpty && !item.onlyVerticals.contains(vertical)) {
    return false;
  }
  if (hiddenByVertical[vertical]?.contains(item.id) ?? false) return false;
  if (ctx.isAdmin) return true;
  if (ctx.sellerToCashier &&
      !ctx.isCashier &&
      _sellerHidden.contains(item.id)) {
    return false;
  }
  return ctx.permissions[item.moduleCode] ?? false;
}

List<MenuEntry> visibleMenu(AppContext ctx) =>
    menuCatalog.where((e) => isMenuVisible(e, ctx)).toList();

List<MenuEntry> restaurantMenu(AppContext ctx) {
  if (ctx.verticalCode.toUpperCase() != 'RESTAURANT') return const [];
  const restaurantModuleIds = {
    'restaurant-orders',
    'cash',
    'tables',
    'restaurant-menu',
  };
  return menuCatalog
      .where(
        (entry) => restaurantModuleIds.contains(entry.id),
      )
      .toList();
}
