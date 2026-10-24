import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facturacion_app/features/sales/presentation/sales_page.dart';

void main() {
  testWidgets('permite agregar un producto a la venta', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpWidget(const MaterialApp(home: SalesPage()));

    expect(find.text('Nueva venta'), findsOneWidget);
    expect(find.text('Detalle de venta'), findsOneWidget);
    expect(find.text('Agrega productos para comenzar.'), findsOneWidget);

    await tester.tap(find.text('Polo básico'));
    await tester.pump();

    expect(find.text('Polo básico'), findsNWidgets(2));
    expect(find.text('1'), findsNWidgets(2));
    expect(find.text('Preparar venta'), findsOneWidget);

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('permite vaciar toda la venta', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpWidget(const MaterialApp(home: SalesPage()));

    final vaciar = find.widgetWithText(TextButton, 'Vaciar');

    // Deshabilitado mientras el detalle está vacío.
    expect(tester.widget<TextButton>(vaciar).onPressed, isNull);

    await tester.tap(find.text('Polo básico'));
    await tester.pump();
    await tester.tap(find.text('Jean clásico'));
    await tester.pump();

    expect(find.text('Agrega productos para comenzar.'), findsNothing);
    expect(find.text('S/ 129.80'), findsOneWidget);

    await tester.tap(vaciar);
    await tester.pumpAndSettle();
    expect(find.text('Vaciar venta'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Vaciar'));
    await tester.pumpAndSettle();

    expect(find.text('Agrega productos para comenzar.'), findsOneWidget);
    expect(tester.widget<TextButton>(vaciar).onPressed, isNull);

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('cancelar conserva los productos de la venta', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpWidget(const MaterialApp(home: SalesPage()));

    await tester.tap(find.text('Polo básico'));
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, 'Vaciar'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
    await tester.pumpAndSettle();

    expect(find.text('Polo básico'), findsNWidgets(2));
    // Aparece en la tarjeta y en el total (39.90).
    expect(find.text('S/ 39.90'), findsNWidgets(2));

    await tester.binding.setSurfaceSize(null);
  });
}
