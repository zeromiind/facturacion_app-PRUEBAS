import '../../../core/api/api_client.dart';
import '../domain/customer.dart';

class CustomersRepository {
  const CustomersRepository(this._api);

  final ApiClient _api;

  List<T> _rows<T>(
    Map<String, dynamic> body,
    T Function(Map<String, dynamic>) parse,
  ) {
    final data = body['data'];
    if (data is! List) return const [];
    return data.whereType<Map>().map((e) => parse(e.cast())).toList();
  }

  Future<List<Customer>> list({String query = '', int limit = 100}) async =>
      _rows(
        await _api.get('/api/sales/customers', {
          'q': query.trim(),
          'limit': '$limit',
        }),
        Customer.fromJson,
      );

  Future<List<Customer>> autocomplete(String query) async => _rows(
    await _api.get('/api/sales/customers/autocomplete', {
      'q': query.trim(),
      'limit': '12',
    }),
    Customer.fromJson,
  );

  Future<List<CustomerType>> types() async =>
      _rows(await _api.get('/api/sales/customer-types'), CustomerType.fromJson);

  /// Consulta RENIEC/SUNAT (o local) por DNI/RUC, igual que la web.
  Future<Customer> resolveDocument(String document) async {
    final body = await _api.get('/api/sales/customers/resolve-document', {
      'document': document.trim(),
    });
    return Customer.fromJson((body['data'] as Map).cast());
  }

  Future<int?> create(Map<String, dynamic> payload) async =>
      toIntOrNull((await _api.post('/api/sales/customers', payload))['id']);

  Future<void> update(int id, Map<String, dynamic> payload) =>
      _api.put('/api/sales/customers/$id', payload);

  Future<List<CustomerVehicle>> vehicles(int customerId) async => _rows(
    await _api.get('/api/sales/customers/$customerId/vehicles'),
    CustomerVehicle.fromJson,
  );

  Future<CustomerVehicle?> createVehicle(
    int customerId,
    Map<String, dynamic> payload,
  ) async {
    final body = await _api.post(
      '/api/sales/customers/$customerId/vehicles',
      payload,
    );
    final data = body['data'];
    if (data is Map) return CustomerVehicle.fromJson(data.cast());
    final id = toIntOrNull(body['id']);
    if (id == null) return null;
    return CustomerVehicle(
      id: id,
      plate: (payload['plate'] ?? '').toString().toUpperCase(),
      brand: payload['brand']?.toString(),
      model: payload['model']?.toString(),
      isDefault: payload['is_default'] == true,
    );
  }

  Future<void> updateVehicle(
    int customerId,
    int vehicleId,
    Map<String, dynamic> payload,
  ) =>
      _api.put('/api/sales/customers/$customerId/vehicles/$vehicleId', payload);

  Future<void> deleteVehicle(int customerId, int vehicleId) =>
      _api.delete('/api/sales/customers/$customerId/vehicles/$vehicleId');
}
