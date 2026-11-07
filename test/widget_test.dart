import 'dart:convert';
import 'dart:io';

import 'package:facturacion_app/core/api/api_client.dart';
import 'package:facturacion_app/core/session/app_context.dart';
import 'package:facturacion_app/core/session/app_menu.dart';
import 'package:facturacion_app/core/time/lima_time.dart';
import 'package:facturacion_app/features/auth/data/auth_repository.dart';
import 'package:facturacion_app/features/auth/domain/auth_session.dart';
import 'package:facturacion_app/features/auth/presentation/login_page.dart';
import 'package:facturacion_app/features/customers/data/customers_repository.dart';
import 'package:facturacion_app/features/restaurant/presentation/restaurant_cash_page.dart';
import 'package:facturacion_app/features/restaurant/presentation/restaurant_pages.dart';
import 'package:facturacion_app/features/shell/home_shell.dart';
import 'package:facturacion_app/features/sales/data/sales_documents_repository.dart';
import 'package:facturacion_app/features/sales/data/sales_repository.dart';
import 'package:facturacion_app/features/sales/domain/product.dart';
import 'package:facturacion_app/features/sales/presentation/sales_ticket_pdf.dart';
import 'package:facturacion_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

AppContext _context({required bool workshop}) => AppContext(
  branchId: 1,
  warehouseId: 2,
  cashRegisterId: 3,
  verticalName: '',
  companyName: 'Demo',
  features: {if (workshop) 'SALES_WORKSHOP_MULTI_VEHICLE'},
  documentKinds: const [
    DocumentKind(
      id: 1,
      code: 'RECEIPT',
      label: 'Boleta',
      kindGroup: 'TRIBUTARY',
    ),
    DocumentKind(
      id: 2,
      code: 'QUOTATION',
      label: 'Cotización',
      kindGroup: 'PRE_DOCUMENT',
    ),
  ],
  paymentMethods: const [NamedOption(id: 5, code: 'CASH', name: 'Efectivo')],
  taxCategories: const [TaxCategory(id: 9, ratePercent: 18)],
  currencies: const [CurrencyOption(id: 1, symbol: 'S/', isDefault: true)],
  unitId: 7,
);

AppContext _menuContext(String verticalCode) => AppContext(
  branchId: 1,
  warehouseId: 2,
  cashRegisterId: 3,
  verticalName: verticalCode,
  verticalCode: verticalCode,
  companyName: 'Demo',
  roleCode: 'ADMIN',
  features: const {},
  documentKinds: const [],
  paymentMethods: const [],
  taxCategories: const [],
  currencies: const [],
  unitId: 7,
);

Future<Map<String, dynamic>> _submit({
  required bool workshop,
  SunatSendMode sunatSendMode = SunatSendMode.direct,
}) async {
  Map<String, dynamic>? sent;
  final api = ApiClient(
    accessToken: 't',
    client: MockClient((request) async {
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'data': {'id': 1},
        }),
        201,
      );
    }),
  );
  final context = _context(workshop: workshop);
  final repository = SalesRepository(api, context);
  await repository.createDocument(
    SaleDraft(
      documentKind: context.documentKinds.first,
      series: 'B001',
      customerId: 10,
      paymentMethodId: 5,
      sunatSendMode: sunatSendMode,
      vehicleId: 4,
      odometerKm: 55000,
      nextOdometerKm: 60000,
      lines: [
        CartLine(product: const Product(id: 1, name: 'Aceite', salePrice: 118)),
      ],
    ),
  );
  return sent!;
}

class _FailingAuthRepository extends Fake implements AuthRepository {
  @override
  Future<AuthSession?> loadSession() async {
    throw const FormatException('Respuesta de sesión inválida.');
  }
}

void main() {
  testWidgets('restaurar sesión fallida no deja la app en carga infinita', (
    tester,
  ) async {
    final repository = _FailingAuthRepository();
    await tester.pumpWidget(FacturacionApp(authRepository: repository));
    await tester.pumpAndSettle();

    expect(
      find.text('No se pudo restaurar la sesión guardada.'),
      findsOneWidget,
    );
    expect(find.text('Reintentar'), findsOneWidget);
    await tester.tap(find.text('Ir al inicio de sesión'));
    await tester.pumpAndSettle();
    expect(find.text('Ingresa a tu espacio de trabajo'), findsOneWidget);
  });

  testWidgets('error inesperado al cargar contexto muestra reintento', (
    tester,
  ) async {
    final session = AuthSession(
      accessToken: 'test-token',
      refreshToken: 'test-refresh',
      accessExpiresAt: DateTime(2030),
      deviceId: 'test-device',
      username: 'test',
      firstName: 'Test',
      lastName: 'User',
    );
    final api = ApiClient(
      accessToken: session.accessToken,
      client: MockClient(
        (_) async => http.Response(jsonEncode({'selected': 'invalid'}), 200),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(session: session, onLogout: () {}, apiClient: api),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'No se pudo interpretar la información recibida. Reintenta o cierra sesión.',
      ),
      findsOneWidget,
    );
    expect(find.text('Reintentar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('restaurante solo muestra sus cuatro módulos', () {
    final context = _menuContext('RESTAURANT');
    final entries = visibleMenu(context);

    expect(entries.map((entry) => entry.id).toSet(), {
      'restaurant-orders',
      'cash',
      'tables',
      'restaurant-menu',
    });
    expect(
      entries
          .firstWhere((entry) => entry.id == 'restaurant-orders')
          .labelFor('RESTAURANT'),
      'Pedidos',
    );
  });

  testWidgets('al detectar una caja abierta actualiza la sesión visible', (
    tester,
  ) async {
    final requestedPaths = <String>[];
    final api = ApiClient(
      accessToken: 'test-token',
      client: MockClient((request) async {
        requestedPaths.add(request.url.path);
        if (request.method == 'GET' &&
            request.url.path == '/api/cash/sessions/current') {
          return http.Response(jsonEncode({'session': null}), 200);
        }
        if (request.method == 'POST' &&
            request.url.path == '/api/cash/sessions') {
          return http.Response(
            jsonEncode({'message': 'La caja ya tiene una sesión abierta'}),
            409,
          );
        }
        if (request.method == 'GET' &&
            request.url.path == '/api/cash/sessions') {
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 42, 'cash_register_id': 3, 'status': 'OPEN'},
              ],
            }),
            200,
          );
        }
        if (request.method == 'GET' &&
            request.url.path == '/api/cash/sessions/42/detail') {
          return http.Response(
            jsonEncode({
              'session': {
                'id': 42,
                'cash_register_name': 'Caja principal',
                'opened_at': '2026-11-06T10:00:00Z',
                'opening_balance': 20,
                'expected_balance': 20,
                'status': 'OPEN',
              },
              'movements': [],
              'payment_method_breakdown': [],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({'message': 'Unexpected request: ${request.url.path}'}),
          500,
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RestaurantCashPage(
          api: api,
          appContext: _menuContext('RESTAURANT'),
          onUnauthorized: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abrir caja'));
    await tester.pumpAndSettle();

    expect(requestedPaths, contains('/api/cash/sessions'));
    expect(requestedPaths, contains('/api/cash/sessions/42/detail'));
    expect(find.text('Caja principal'), findsOneWidget);
    expect(find.textContaining('Sesión abierta'), findsOneWidget);
    expect(find.text('Abrir caja'), findsNothing);
    expect(find.text('La caja ya tiene una sesión abierta'), findsNothing);
    expect(
      requestedPaths.where((path) => path == '/api/cash/sessions/current'),
      hasLength(2),
    );
    expect(tester.takeException(), isNull);
  });

  test('los módulos exclusivos de restaurante no aparecen en retail', () {
    final entries = visibleMenu(_menuContext('RETAIL'));
    final ids = entries.map((entry) => entry.id).toSet();

    expect(ids, contains('sales'));
    expect(ids, contains('products'));
    expect(ids, isNot(contains('restaurant-orders')));
    expect(ids, isNot(contains('restaurant-menu')));
    expect(ids, isNot(contains('tables')));
  });

  test(
    'restaurante conserva su navegación aunque falten permisos generales',
    () {
      final context = _menuContext('RESTAURANT');
      final entries = restaurantMenu(context);

      expect(entries.map((entry) => entry.id).toSet(), {
        'restaurant-orders',
        'cash',
        'tables',
        'restaurant-menu',
      });
    },
  );

  testWidgets('editar producto del menú no falla al guardar', (tester) async {
    var updated = false;
    final api = ApiClient(
      accessToken: 'test-token',
      client: MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path.endsWith('/api/inventory/products')) {
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 8,
                  'name': 'Producto de prueba',
                  'unit_id': 2,
                  'sale_price': 10,
                  'cost_price': 5,
                  'status': 1,
                },
              ],
            }),
            200,
          );
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/api/inventory/product-lookups')) {
          return http.Response(
            jsonEncode({
              'units': [
                {'id': 2, 'name': 'Unidad', 'code': 'UND'},
              ],
            }),
            200,
          );
        }
        if (request.method == 'PUT' &&
            request.url.path.endsWith('/api/inventory/products/8')) {
          updated = true;
          return http.Response(jsonEncode({'id': 8}), 200);
        }
        return http.Response(
          jsonEncode({'message': 'Unexpected request: ${request.url.path}'}),
          500,
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RestaurantMenuPage(
          api: api,
          appContext: _menuContext('RESTAURANT'),
          onUnauthorized: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Editar producto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(updated, isTrue);
  });

  testWidgets(
    'si falla la imagen conserva el producto y reintenta sin duplicarlo',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      final imageFile = File(
        '${Directory.systemTemp.path}\\restaurant-menu-image-test.jpg',
      );
      await imageFile.writeAsBytes([1, 2, 3]);
      addTearDown(() async {
        if (await imageFile.exists()) await imageFile.delete();
      });

      const imagePickerChannel = MethodChannel(
        'plugins.flutter.io/image_picker',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(imagePickerChannel, (call) async {
            if (call.method == 'pickImage') return imageFile.path;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(imagePickerChannel, null),
      );

      var createCount = 0;
      var updateCount = 0;
      var uploadCount = 0;
      var loggedOut = false;
      final api = ApiClient(
        accessToken: 'test-token',
        client: MockClient((request) async {
          if (request.method == 'GET' &&
              request.url.path.endsWith('/api/inventory/products')) {
            return http.Response(
              jsonEncode({
                'data': [
                  if (createCount > 0)
                    {
                      'id': 55,
                      'name': 'Plato nuevo',
                      'unit_id': 2,
                      'sale_price': 10,
                      'cost_price': 5,
                      'status': 1,
                    },
                ],
              }),
              200,
            );
          }
          if (request.method == 'GET' &&
              request.url.path.endsWith('/api/inventory/product-lookups')) {
            return http.Response(
              jsonEncode({
                'units': [
                  {'id': 2, 'name': 'Unidad', 'code': 'UND'},
                ],
              }),
              200,
            );
          }
          if (request.method == 'POST' &&
              request.url.path == '/api/inventory/products') {
            createCount++;
            return http.Response(jsonEncode({'id': 55}), 201);
          }
          if (request.method == 'PUT' &&
              request.url.path == '/api/inventory/products/55') {
            updateCount++;
            return http.Response(jsonEncode({'id': 55}), 200);
          }
          if (request.method == 'POST' &&
              request.url.path == '/api/inventory/products/55/image') {
            uploadCount++;
            if (uploadCount == 1) {
              return http.Response(
                jsonEncode({'message': 'No se pudo guardar la imagen.'}),
                500,
              );
            }
            return http.Response(
              jsonEncode({'image_url': 'https://example.test/product.jpg'}),
              200,
            );
          }
          return http.Response(
            jsonEncode({'message': 'Unexpected request: ${request.url.path}'}),
            500,
          );
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RestaurantMenuPage(
            api: api,
            appContext: _menuContext('RESTAURANT'),
            onUnauthorized: () => loggedOut = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agregar al menú'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Plato nuevo');
      await tester.tap(find.text('Cambiar imagen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agregar').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('El producto se guardó'), findsOneWidget);
      expect(createCount, 1);
      expect(uploadCount, 1);
      expect(loggedOut, isFalse);

      await tester.tap(find.text('Guardar').last);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(createCount, 1);
      expect(updateCount, 1);
      expect(uploadCount, 2);
      expect(loggedOut, isFalse);
    },
  );

  testWidgets('venta rápida permite filtrar categorías y armar pedido', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    final api = ApiClient(
      accessToken: 'test-token',
      client: MockClient((request) async {
        switch (request.url.path) {
          case '/api/restaurant/bootstrap':
            return http.Response(
              jsonEncode({
                'restaurant_quick_sale_enabled': true,
                'series_numbers': [],
                'payment_methods': [
                  {'id': 5, 'code': 'CASH', 'name': 'Efectivo'},
                ],
                'currencies': [
                  {'id': 1, 'symbol': 'S/', 'is_default': true},
                ],
              }),
              200,
            );
          case '/api/restaurant/tables':
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': 1,
                    'code': 'M01',
                    'name': 'Mesa 1',
                    'capacity': 4,
                    'status': 'AVAILABLE',
                  },
                ],
              }),
              200,
            );
          case '/api/restaurant/orders':
            return http.Response(jsonEncode({'data': []}), 200);
          case '/api/sales/customers/autocomplete':
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': 10,
                    'name': 'CLIENTES VARIOS',
                    'doc_number': '11111111',
                    'doc_type': '1',
                    'status': 1,
                  },
                ],
              }),
              200,
            );
          case '/api/inventory/products':
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': 21,
                    'name': 'Cerveza',
                    'category_name': 'Bebidas',
                    'sale_price': 12,
                    'unit_id': 2,
                    'product_nature': 'PRODUCT',
                    'status': 1,
                  },
                  {
                    'id': 22,
                    'name': 'Pastel',
                    'category_name': 'Postres',
                    'sale_price': 8,
                    'unit_id': 2,
                    'product_nature': 'PRODUCT',
                    'status': 1,
                  },
                ],
              }),
              200,
            );
          default:
            return http.Response(jsonEncode({'data': []}), 200);
        }
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RestaurantOrdersPage(
          api: api,
          appContext: _menuContext('RESTAURANT'),
          customers: CustomersRepository(api),
          onUnauthorized: () {},
          showAppBar: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Selecciona una mesa'), findsOneWidget);
    expect(find.text('Cerveza'), findsNothing);
    await tester.tap(find.text('Mesa 1'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(find.text('Selecciona una mesa'), findsNothing);
    expect(find.text('M01 · Mesa 1'), findsOneWidget);
    expect(find.text('¿Cuántas personas?'), findsOneWidget);
    expect(find.text('Cerveza'), findsNothing);
    await tester.tap(find.byTooltip('Agregar una persona'));
    await tester.tap(find.text('Continuar al menú'));
    await tester.pumpAndSettle();

    expect(find.text('Comensales: 2'), findsOneWidget);
    expect(find.text('CLIENTES VARIOS'), findsNothing);
    expect(find.text('Bebidas'), findsOneWidget);
    expect(find.text('Postres'), findsOneWidget);
    await tester.tap(find.text('Bebidas'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cerveza'), findsOneWidget);
    expect(find.text('Pastel'), findsNothing);
    await tester.tap(find.text('Cerveza'));
    await tester.pumpAndSettle();

    expect(find.text('1 producto'), findsOneWidget);
    for (final size in [
      const Size(360, 640),
      const Size(768, 1024),
      const Size(1366, 768),
      const Size(1920, 1080),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.text('Ver pedido'));
    await tester.pumpAndSettle();
    expect(find.text('Total estimado'), findsOneWidget);
    expect(find.text('CLIENTES VARIOS'), findsOneWidget);
    expect(find.text('Comensales: 2'), findsNWidgets(2));
    expect(find.text('Medio de pago'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mesa ocupada muestra pedido y registra cobro en caja', (
    tester,
  ) async {
    Map<String, dynamic>? checkoutPayload;
    var checkedOut = false;
    final api = ApiClient(
      accessToken: 'test-token',
      client: MockClient((request) async {
        switch (request.url.path) {
          case '/api/restaurant/bootstrap':
            return http.Response(
              jsonEncode({
                'restaurant_quick_sale_enabled': true,
                'payment_methods': [
                  {'id': 5, 'code': 'CASH', 'name': 'Efectivo'},
                ],
                'currencies': [
                  {'id': 1, 'symbol': 'S/', 'is_default': true},
                ],
              }),
              200,
            );
          case '/api/restaurant/tables':
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': 1,
                    'code': 'M01',
                    'name': 'Mesa 1',
                    'capacity': 4,
                    'status': checkedOut ? 'AVAILABLE' : 'OCCUPIED',
                  },
                ],
              }),
              200,
            );
          case '/api/restaurant/orders':
            return http.Response(
              jsonEncode({
                'data': checkedOut
                    ? []
                    : [
                        {
                          'id': 77,
                          'series': 'P001',
                          'number': '000077',
                          'issue_at': limaIsoOffset(
                            limaNow().subtract(const Duration(days: 1)),
                          ),
                          'status': 'DRAFT',
                          'table_id': '1',
                          'table_label': 'M01 Mesa 1',
                          'customer_name': 'CLIENTES VARIOS',
                          'line_count': 1,
                          'total_qty': 1,
                          'total': 12,
                          'items': [
                            {
                              'description': 'Cerveza',
                              'quantity': 1,
                              'total': 12,
                            },
                          ],
                        },
                      ],
              }),
              200,
            );
          case '/api/sales/customers/autocomplete':
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': 10,
                    'name': 'CLIENTES VARIOS',
                    'doc_number': '11111111',
                    'doc_type': '1',
                    'status': 1,
                  },
                ],
              }),
              200,
            );
          default:
            if (request.method == 'POST' &&
                request.url.path.endsWith('/checkout')) {
              checkoutPayload =
                  jsonDecode(request.body) as Map<String, dynamic>;
              checkedOut = true;
              return http.Response(
                jsonEncode({
                  'data': {'status': 'ISSUED'},
                }),
                200,
              );
            }
            return http.Response(jsonEncode({'data': []}), 200);
        }
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RestaurantOrdersPage(
          api: api,
          appContext: _menuContext('RESTAURANT'),
          customers: CustomersRepository(api),
          onUnauthorized: () {},
          showAppBar: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mesa 1'));
    await tester.pumpAndSettle();

    expect(find.text('Pedido de Mesa 1'), findsOneWidget);
    expect(find.textContaining('Cerveza'), findsOneWidget);
    expect(find.text('Cliente: CLIENTES VARIOS'), findsOneWidget);
    expect(find.text('Medio de pago'), findsOneWidget);
    await tester.ensureVisible(find.text('Cobrar pedido'));
    await tester.tap(find.text('Cobrar pedido'));
    await tester.pumpAndSettle();

    expect(checkoutPayload, {
      'target_document_kind': 'SALES_ORDER',
      'cash_register_id': 3,
      'payment_method_id': 5,
    });
    expect(find.text('Selecciona una mesa'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('crear mesa guarda el contrato esperado sin error de widget', (
    tester,
  ) async {
    Map<String, dynamic>? savedTable;
    final api = ApiClient(
      accessToken: 'test-token',
      client: MockClient((request) async {
        if (request.url.path == '/api/restaurant/tables' &&
            request.method == 'POST') {
          savedTable = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'id': 4}), 201);
        }
        if (request.url.path == '/api/restaurant/tables') {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        return http.Response(jsonEncode({'data': []}), 200);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RestaurantTablesPage(
          api: api,
          appContext: _menuContext('RESTAURANT'),
          onUnauthorized: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agregar mesa'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'm01');
    await tester.enterText(find.byType(TextFormField).at(1), 'Terraza 1');
    await tester.enterText(find.byType(TextFormField).at(2), '4');
    await tester.tap(find.text('Crear mesa'));
    await tester.pumpAndSettle();

    expect(savedTable, {
      'branch_id': 1,
      'code': 'M01',
      'name': 'Terraza 1',
      'capacity': 4,
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('pedido recién creado queda disponible para cobrar', (
    tester,
  ) async {
    final orders = <Map<String, dynamic>>[];
    Map<String, dynamic>? orderPayload;
    var checkedOut = false;
    final api = ApiClient(
      accessToken: 'test-token',
      client: MockClient((request) async {
        switch (request.url.path) {
          case '/api/restaurant/bootstrap':
            return http.Response(
              jsonEncode({
                'restaurant_quick_sale_enabled': true,
                'series_numbers': [
                  {
                    'series': 'P001',
                    'document_kind': 'SALES_ORDER',
                    'is_enabled': true,
                  },
                ],
                'payment_methods': [
                  {'id': 5, 'code': 'CASH', 'name': 'Efectivo'},
                ],
                'currencies': [
                  {'id': 1, 'symbol': 'S/', 'is_default': true},
                ],
              }),
              200,
            );
          case '/api/restaurant/tables':
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': 1,
                    'code': 'M01',
                    'name': 'Mesa 1',
                    'capacity': 4,
                    'status': orders.isEmpty || checkedOut
                        ? 'AVAILABLE'
                        : 'OCCUPIED',
                  },
                ],
              }),
              200,
            );
          case '/api/restaurant/orders':
            if (request.method == 'POST') {
              orderPayload = jsonDecode(request.body) as Map<String, dynamic>;
              orders.add({
                'id': 77,
                'series': 'P001',
                'number': '000077',
                'status': 'DRAFT',
                'table_id': '1',
                'table_label': 'M01 Mesa 1',
                'customer_name': 'CLIENTES VARIOS',
                'line_count': 1,
                'total_qty': 1,
                'total': 12,
                'items': [
                  {'description': 'Cerveza', 'quantity': 1, 'total': 12},
                ],
              });
              return http.Response(jsonEncode({'id': 77}), 201);
            }
            return http.Response(
              jsonEncode({'data': checkedOut ? [] : orders}),
              200,
            );
          case '/api/sales/customers/autocomplete':
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': 10,
                    'name': 'CLIENTES VARIOS',
                    'doc_number': '11111111',
                    'doc_type': '1',
                    'status': 1,
                  },
                ],
              }),
              200,
            );
          case '/api/inventory/products':
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': 21,
                    'name': 'Cerveza',
                    'sale_price': 12,
                    'unit_id': 2,
                    'product_nature': 'PRODUCT',
                    'status': 1,
                  },
                ],
              }),
              200,
            );
          default:
            if (request.method == 'POST' &&
                request.url.path.endsWith('/checkout')) {
              checkedOut = true;
              return http.Response(
                jsonEncode({
                  'data': {'status': 'ISSUED'},
                }),
                200,
              );
            }
            return http.Response(jsonEncode({'data': []}), 200);
        }
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RestaurantOrdersPage(
          api: api,
          appContext: _menuContext('RESTAURANT'),
          customers: CustomersRepository(api),
          onUnauthorized: () {},
          showAppBar: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mesa 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar al menú'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cerveza'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver pedido'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar precio'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '15.50');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registrar pedido'));
    await tester.pumpAndSettle();

    expect(orderPayload, isNotNull);
    expect(orderPayload!['payment_method_id'], 5);
    expect((orderPayload!['items'] as List).single['unit_price'], 15.5);
    expect((orderPayload!['items'] as List).single['total'], 15.5);
    expect(find.text('Pedido de Mesa 1'), findsOneWidget);
    expect(find.textContaining('Cerveza'), findsOneWidget);
    await tester.ensureVisible(find.text('Cobrar pedido'));
    await tester.tap(find.text('Cobrar pedido'));
    await tester.pumpAndSettle();

    expect(checkedOut, isTrue);
    expect(find.text('Selecciona una mesa'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login conserva sus campos en tamaños móviles y amplios', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    final repository = AuthRepository(
      client: MockClient((_) async => http.Response('{}', 401)),
    );

    for (final size in [
      const Size(360, 640),
      const Size(768, 1024),
      const Size(1366, 768),
      const Size(1920, 1080),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          home: LoginPage(authRepository: repository, onAuthenticated: (_) {}),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Facturación'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    }
  });

  test('carga productos rapidos desde el endpoint de inventario', () async {
    Uri? requestedUri;
    final api = ApiClient(
      accessToken: 'test-access-token',
      client: MockClient((request) async {
        requestedUri = request.url;
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 12,
                'name': 'Producto de prueba',
                'sale_price': '25.50',
                'unit_id': 4,
              },
            ],
          }),
          200,
        );
      }),
    );
    final repository = SalesRepository(api, _context(workshop: false));

    final products = await repository.quickProducts();

    expect(requestedUri?.path, '/api/inventory/products');
    expect(requestedUri?.queryParameters, {
      'warehouse_id': '2',
      'status': '1',
      'limit': '4',
    });
    expect(products.single.id, 12);
    expect(products.single.name, 'Producto de prueba');
    expect(products.single.salePrice, 25.5);
  });

  test('genera ticket local de 58mm desde el documento cargado', () async {
    final bytes = await buildSalesTicketPdf(
      SaleDocument(
        id: 42,
        documentKind: 'RECEIPT',
        series: 'B001',
        number: '000042',
        issueAt: DateTime(2026, 10, 23),
        status: 'ISSUED',
        sunatStatus: 'ACCEPTED',
        total: 118,
        balanceDue: 0,
        customerName: 'Cliente de prueba',
        customerDocNumber: '12345678',
        plate: null,
        vehicleLabel: '',
        paymentMethod: 'Efectivo',
        createdBy: 'Vendedor',
      ),
      documentKindLabel: 'Boleta',
      companyName: 'Empresa Demo',
      currencySymbol: 'S/',
      statusLabel: 'Emitido',
      sunatStatusLabel: 'Aceptado',
      showSunatStatus: true,
      items: const [
        SaleDocumentItem(
          description: 'Aceite de motor',
          quantity: 2,
          unitPrice: 59,
          total: 118,
          unitLabel: 'UND',
        ),
      ],
    );

    expect(bytes.take(5).toList(), [37, 80, 68, 70, 45]);
    expect(
      latin1.decode(bytes),
      matches(RegExp(r'/MediaBox\[0 0 164\.40\d+ ')),
    );
  });

  test('SUNAT solo aplica a documentos tributarios y su ticket', () {
    final context = _context(workshop: false);
    expect(context.isTributaryDocument('RECEIPT'), isTrue);
    expect(context.isTributaryDocument('QUOTATION'), isFalse);
    expect(context.isTributaryDocument('UNKNOWN'), isFalse);

    const document = SaleDocument(
      id: 42,
      documentKind: 'QUOTATION',
      series: 'C001',
      number: '000042',
      issueAt: null,
      status: 'DRAFT',
      sunatStatus: null,
      total: 118,
      balanceDue: 118,
      customerName: 'Cliente de prueba',
      customerDocNumber: null,
      plate: null,
      vehicleLabel: '',
      paymentMethod: null,
      createdBy: null,
    );
    final ticketFormat = salesTicketPageFormat(
      document,
      companyName: 'Empresa Demo',
      items: const [],
      showSunatStatus: false,
    );
    final tributaryFormat = salesTicketPageFormat(
      document,
      companyName: 'Empresa Demo',
      items: const [],
      showSunatStatus: true,
    );

    expect(ticketFormat.height, lessThan(tributaryFormat.height));
  });

  test(
    'detalle de venta consulta el JSON y mapea productos para el ticket',
    () async {
      Uri? requestedUri;
      final repository = SalesDocumentsRepository(
        ApiClient(
          accessToken: 'test-access-token',
          client: MockClient((request) async {
            requestedUri = request.url;
            return http.Response(
              jsonEncode({
                'data': {
                  'items': [
                    {
                      'description': 'Aceite de motor',
                      'qty': 2,
                      'unitLabel': 'UND',
                      'unitPrice': 59,
                      'lineTotal': 118,
                    },
                  ],
                },
              }),
              200,
            );
          }),
        ),
        _context(workshop: false),
      );

      final items = await repository.fetchItems(42);

      expect(requestedUri?.path, '/api/sales/commercial-documents/42');
      expect(items.single.description, 'Aceite de motor');
      expect(items.single.quantity, 2);
      expect(items.single.unitLabel, 'UND');
      expect(items.single.unitPrice, 59);
      expect(items.single.total, 118);
    },
  );

  test(
    'no permite imprimir silenciosamente un detalle sin productos',
    () async {
      final repository = SalesDocumentsRepository(
        ApiClient(
          accessToken: 'test-access-token',
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'data': {'items': []},
              }),
              200,
            ),
          ),
        ),
        _context(workshop: false),
      );

      await expectLater(
        repository.fetchItems(42),
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'message',
            contains('no devolvió productos'),
          ),
        ),
      );
    },
  );

  test('reporte obtiene solo la página solicitada', () async {
    Uri? requestedUri;
    final repository = SalesDocumentsRepository(
      ApiClient(
        accessToken: 'test-access-token',
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 42,
                  'document_kind': 'RECEIPT',
                  'series': 'B001',
                  'number': '000042',
                  'status': 'ISSUED',
                  'sunat_status': 'ACCEPTED',
                  'total': 118,
                  'balance_due': 0,
                  'customer_name': 'Cliente de prueba',
                },
              ],
              'meta': {'page': 2, 'last_page': 4, 'total': 76},
            }),
            200,
          );
        }),
      ),
      _context(workshop: false),
    );

    final page = await repository.fetch(const DocumentFilters(), page: 2);

    expect(requestedUri?.queryParameters['page'], '2');
    expect(requestedUri?.queryParameters['per_page'], '20');
    expect(page.page, 2);
    expect(page.lastPage, 4);
    expect(page.total, 76);
    expect(page.items.single.id, 42);
  });

  test(
    'el envío SUNAT directo queda activo por defecto en tributarios',
    () async {
      final body = await _submit(workshop: false);
      final metadata = body['metadata'] as Map<String, dynamic>;

      expect(metadata['defer_sunat_send'], isFalse);
      expect(metadata['receipt_send_mode'], 'DIRECT');
    },
  );

  test(
    'permite diferir el envío SUNAT y usar resumen diario en boletas',
    () async {
      final deferred = await _submit(
        workshop: false,
        sunatSendMode: SunatSendMode.disabled,
      );
      final deferredMetadata = deferred['metadata'] as Map<String, dynamic>;
      expect(deferredMetadata['defer_sunat_send'], isTrue);

      final summarized = await _submit(
        workshop: false,
        sunatSendMode: SunatSendMode.dailySummary,
      );
      final summarizedMetadata = summarized['metadata'] as Map<String, dynamic>;
      expect(summarizedMetadata['defer_sunat_send'], isFalse);
      expect(summarizedMetadata['receipt_send_mode'], 'SUMMARY');
    },
  );

  test('en taller envía vehículo y kilometraje', () async {
    final body = await _submit(workshop: true);
    final metadata = body['metadata'] as Map<String, dynamic>;
    expect(body['customer_vehicle_id'], 4);
    expect(metadata['vehicle_odometer_km'], 55000);
    expect(metadata['vehicle_next_odometer_km'], 60000);
  });

  test('sin modo taller ignora datos de vehículo', () async {
    final body = await _submit(workshop: false);
    final metadata = body['metadata'] as Map<String, dynamic>;
    expect(body['customer_vehicle_id'], isNull);
    expect(metadata['vehicle_odometer_km'], isNull);
  });

  test('menú depende del rubro, permisos y flujo', () {
    AppContext ctx(
      String vertical,
      String role,
      Map<String, bool> perms, {
      bool seller = false,
    }) => AppContext(
      branchId: 1,
      warehouseId: 2,
      cashRegisterId: 3,
      verticalName: vertical,
      verticalCode: vertical,
      roleCode: role,
      permissions: perms,
      companyName: 'Demo',
      features: {if (seller) 'SALES_SELLER_TO_CASHIER'},
      documentKinds: const [],
      paymentMethods: const [],
      taxCategories: const [],
      currencies: const [],
      unitId: 7,
    );
    List<String> ids(AppContext c) => visibleMenu(c).map((e) => e.id).toList();

    final admin = ids(ctx('WORKSHOP', 'ADMIN', {}));
    expect(admin, contains('sales-report'));
    expect(admin, isNot(contains('gre-guides')));
    expect(admin, isNot(contains('comandas')));
    expect(ids(ctx('RESTAURANT', 'ADMIN', {})).toSet(), {
      'restaurant-orders',
      'cash',
      'tables',
      'restaurant-menu',
    });
    expect(ids(ctx('RETAIL', 'USER', {'SALES': true})), contains('customers'));
    expect(ids(ctx('RETAIL', 'USER', {})), isEmpty);
    expect(
      ids(ctx('RETAIL', 'VENDEDOR', {'SALES': true}, seller: true)),
      isNot(contains('cash')),
    );
  });

  test('reporte arma filtros por pestaña como la web', () {
    final context = _context(workshop: true);
    final repo = SalesDocumentsRepository(ApiClient(accessToken: 't'), context);
    final tributary = repo.buildParams(
      const DocumentFilters(tab: DocumentTab.tributary, vehicle: 'ABC'),
    );
    expect(tributary['document_kind_id'], '1');
    expect(tributary['vehicle'], 'ABC');
    final orders = repo.buildParams(
      const DocumentFilters(tab: DocumentTab.orders),
    );
    expect(orders['document_kind'], 'QUOTATION,SALES_ORDER');
  });

  test('calcula IGV con precio incluido', () async {
    final body = await _submit(workshop: false);
    final item = (body['items'] as List).first as Map<String, dynamic>;
    expect(item['subtotal'], 100.0);
    expect(item['tax_total'], 18.0);
    expect(item['total'], 118.0);
  });
}
