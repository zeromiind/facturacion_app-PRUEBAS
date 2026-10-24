import 'package:flutter/material.dart';

import 'core/routing/enrutador.dart';

void main() {
  runApp(const FacturacionApp());
}

class FacturacionApp extends StatelessWidget {
  const FacturacionApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0F766E),
      brightness: Brightness.light,
    );

    return MaterialApp.router(
      title: 'Facturación',
      debugShowCheckedModeBanner: false,
      routerConfig: Enrutador.instancia.router,
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
        navigationBarTheme: NavigationBarThemeData(
          indicatorColor: colorScheme.primaryContainer,
        ),
      ),
    );
  }
}
