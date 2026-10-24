import 'package:flutter/material.dart';

import '../domain/product.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  final _searchController = TextEditingController();
  final Map<String, int> _cart = {};
  String _search = '';

  static const _products = [
    Product(
      id: 'polo-basico',
      name: 'Polo básico',
      priceInCents: 3990,
      category: 'Ropa',
    ),
    Product(
      id: 'jean-clasico',
      name: 'Jean clásico',
      priceInCents: 8990,
      category: 'Ropa',
    ),
    Product(
      id: 'zapatillas-urbanas',
      name: 'Zapatillas urbanas',
      priceInCents: 12990,
      category: 'Calzado',
    ),
    Product(
      id: 'gorra',
      name: 'Gorra deportiva',
      priceInCents: 2990,
      category: 'Accesorios',
    ),
  ];

  List<Product> get _filteredProducts {
    final query = _search.trim().toLowerCase();
    if (query.isEmpty) return _products;

    return _products
        .where(
          (product) =>
              product.name.toLowerCase().contains(query) ||
              product.category.toLowerCase().contains(query),
        )
        .toList();
  }

  List<Product> get _cartProducts =>
      _products.where((product) => (_cart[product.id] ?? 0) > 0).toList();

  int get _totalInCents => _cartProducts.fold(
    0,
    (total, product) => total + product.priceInCents * _cart[product.id]!,
  );

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _addProduct(Product product) {
    setState(() {
      _cart.update(product.id, (quantity) => quantity + 1, ifAbsent: () => 1);
    });
  }

  void _removeProduct(Product product) {
    setState(() {
      final quantity = _cart[product.id] ?? 0;
      if (quantity <= 1) {
        _cart.remove(product.id);
      } else {
        _cart[product.id] = quantity - 1;
      }
    });
  }

  Future<void> _confirmClearCart() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Vaciar venta'),
        content: const Text(
          'Se quitarán todos los productos del detalle de venta.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Vaciar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _cart.clear());
  }

  void _showPendingSyncMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Venta preparada localmente. La sincronización se agregará en la siguiente etapa.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nueva venta'),
        actions: [
          IconButton(
            onPressed: () {},
            tooltip: 'Configuración',
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;
          final products = _buildProducts();
          final cart = _buildCart();

          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: products),
                SizedBox(width: 360, child: cart),
              ],
            );
          }

          return Column(
            children: [
              Expanded(child: products),
              SizedBox(height: 320, child: cart),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProducts() {
    final products = _filteredProducts;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Productos',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _search = value),
            decoration: const InputDecoration(
              hintText: 'Buscar producto o categoría',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: products.isEmpty
                ? const Center(child: Text('No se encontraron productos.'))
                : GridView.builder(
                    itemCount: products.length,
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 240,
                          mainAxisExtent: 190,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                    itemBuilder: (context, index) {
                      final product = products[index];
                      return _ProductCard(
                        product: product,
                        quantity: _cart[product.id] ?? 0,
                        onAdd: () => _addProduct(product),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCart() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Detalle de venta',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton.icon(
                  onPressed: _cart.isEmpty ? null : _confirmClearCart,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('Vaciar'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _cartProducts.isEmpty
                  ? const Center(child: Text('Agrega productos para comenzar.'))
                  : ListView.separated(
                      itemCount: _cartProducts.length,
                      separatorBuilder: (_, _) => const Divider(height: 20),
                      itemBuilder: (context, index) {
                        final product = _cartProducts[index];
                        final quantity = _cart[product.id]!;
                        return Row(
                          children: [
                            Expanded(
                              child: Text(
                                product.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              onPressed: () => _removeProduct(product),
                              icon: const Icon(Icons.remove_circle_outline),
                              visualDensity: VisualDensity.compact,
                            ),
                            Text('$quantity'),
                            IconButton(
                              onPressed: () => _addProduct(product),
                              icon: const Icon(Icons.add_circle_outline),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        );
                      },
                    ),
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'S/ ${(_totalInCents / 100).toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _cart.isEmpty ? null : _showPendingSyncMessage,
                icon: const Icon(Icons.receipt_long),
                label: const Text('Preparar venta'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.quantity,
    required this.onAdd,
  });

  final Product product;
  final int quantity;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onAdd,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  Icons.inventory_2_outlined,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const Spacer(),
              Text(
                product.category,
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 4),
              Text(
                product.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      product.formattedPrice,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (quantity > 0)
                    Badge(
                      label: Text('$quantity'),
                      child: const Icon(Icons.shopping_cart_outlined),
                    )
                  else
                    const Icon(Icons.add_circle_outline),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
