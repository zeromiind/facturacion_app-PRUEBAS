class Product {
  const Product({
    required this.id,
    required this.name,
    required this.salePrice,
    this.sku,
    this.unitId,
    this.unitCode,
    this.categoryName,
    this.lotTracking = false,
  });

  final int id;
  final String name;
  final double salePrice;
  final String? sku;
  final int? unitId;
  final String? unitCode;
  final String? categoryName;
  final bool lotTracking;
}
