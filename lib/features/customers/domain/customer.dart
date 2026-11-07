import '../../../core/api/api_client.dart';

class Customer {
  const Customer({
    required this.id,
    required this.name,
    this.docType,
    this.docNumber,
    this.tradeName,
    this.address,
    this.phone,
    this.customerTypeId,
    this.customerTypeName,
    this.status = 1,
  });

  final int id;
  final String name;
  final String? docType;
  final String? docNumber;
  final String? tradeName;
  final String? address;
  final String? phone;
  final int? customerTypeId;
  final String? customerTypeName;
  final int status;

  bool get isActive => status == 1;

  String get documentLabel {
    final number = (docNumber ?? '').trim();
    if (number.isEmpty) return 'Sin documento';
    final type = (docType ?? '').trim();
    return type.isEmpty ? number : '${_docTypeAlias(type)} $number';
  }

  static String _docTypeAlias(String code) => switch (code) {
    '1' => 'DNI',
    '6' => 'RUC',
    '4' => 'CE',
    '7' => 'PAS',
    _ => code,
  };

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
    id: toIntOrNull(json['id']) ?? 0,
    name: (json['name'] ?? '').toString(),
    docType: json['doc_type']?.toString(),
    docNumber: json['doc_number']?.toString(),
    tradeName: json['trade_name']?.toString(),
    address: json['address']?.toString(),
    phone: json['phone']?.toString(),
    customerTypeId: toIntOrNull(json['customer_type_id']),
    customerTypeName: json['customer_type_name']?.toString(),
    status: toIntOrNull(json['status']) ?? 1,
  );
}

class CustomerType {
  const CustomerType({
    required this.id,
    required this.name,
    required this.sunatCode,
  });

  final int id;
  final String name;
  final int sunatCode;

  factory CustomerType.fromJson(Map<String, dynamic> json) => CustomerType(
    id: toIntOrNull(json['id']) ?? 0,
    name: (json['name'] ?? '').toString(),
    sunatCode: toIntOrNull(json['sunat_code']) ?? 0,
  );
}

class CustomerVehicle {
  const CustomerVehicle({
    required this.id,
    required this.plate,
    this.brand,
    this.model,
    this.year,
    this.color,
    this.vin,
    this.isDefault = false,
  });

  final int id;
  final String plate;
  final String? brand;
  final String? model;
  final int? year;
  final String? color;
  final String? vin;
  final bool isDefault;

  String get label {
    final detail = [brand, model].where((e) => (e ?? '').isNotEmpty).join(' ');
    return detail.isEmpty ? plate : '$plate · $detail';
  }

  factory CustomerVehicle.fromJson(Map<String, dynamic> json) =>
      CustomerVehicle(
        id: toIntOrNull(json['id']) ?? 0,
        plate: (json['plate'] ?? '').toString(),
        brand: json['brand']?.toString(),
        model: json['model']?.toString(),
        year: toIntOrNull(json['year']),
        color: json['color']?.toString(),
        vin: json['vin']?.toString(),
        isDefault: toBool(json['is_default']),
      );
}
