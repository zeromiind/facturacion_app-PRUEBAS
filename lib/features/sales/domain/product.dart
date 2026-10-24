class Product {
  const Product({
    required this.id,
    required this.name,
    required this.priceInCents,
    required this.category,
  });

  final String id;
  final String name;
  final int priceInCents;
  final String category;

  String get formattedPrice {
    return 'S/ ${(priceInCents / 100).toStringAsFixed(2)}';
  }
}
