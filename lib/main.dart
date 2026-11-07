import 'package:flutter/material.dart';

import 'features/auth/data/auth_repository.dart';
import 'features/auth/domain/auth_session.dart';
import 'features/auth/presentation/login_page.dart';
import 'features/shell/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(FacturacionApp(authRepository: AuthRepository()));
}

class FacturacionApp extends StatelessWidget {
  const FacturacionApp({
    required this.authRepository,
    this.initialSession,
    super.key,
  });

  final AuthRepository authRepository;
  final AuthSession? initialSession;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2F6B4F),
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'Facturación',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F7F5),
        appBarTheme: AppBarTheme(
          backgroundColor: colorScheme.primary,
          foregroundColor: Colors.white,
          toolbarHeight: 56,
          titleTextStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
          elevation: 0,
          scrolledUnderElevation: 1,
        ),
        visualDensity: VisualDensity.standard,
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 1,
          shadowColor: const Color(0xFF173D2B).withValues(alpha: 0.08),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFE5ECE7)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD7E1DA)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD7E1DA)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: colorScheme.primary, width: 1.8),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: colorScheme.error),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: colorScheme.error, width: 1.8),
          ),
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 17,
          ),
          labelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          hintStyle: const TextStyle(color: Color(0xFF87948C), fontSize: 14),
          prefixIconColor: const Color(0xFF718078),
          suffixIconColor: const Color(0xFF718078),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
      home: _AuthenticatedApp(
        authRepository: authRepository,
        initialSession: initialSession,
      ),
    );
  }
}

class _AuthenticatedApp extends StatefulWidget {
  const _AuthenticatedApp({required this.authRepository, this.initialSession});

  final AuthRepository authRepository;
  final AuthSession? initialSession;

  @override
  State<_AuthenticatedApp> createState() => _AuthenticatedAppState();
}

class _AuthenticatedAppState extends State<_AuthenticatedApp> {
  late AuthSession? _session = widget.initialSession;
  late bool _isLoading = widget.initialSession == null;
  String? _restoreError;

  @override
  void initState() {
    super.initState();
    if (widget.initialSession == null) _restoreSession();
  }

  Future<void> _restoreSession() async {
    setState(() {
      _isLoading = true;
      _restoreError = null;
    });
    try {
      final session = await widget.authRepository.loadSession();
      if (!mounted) return;
      setState(() {
        _session = session;
        _isLoading = false;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _restoreError = error.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_restoreError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'No se pudo restaurar la sesión guardada.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(_restoreError!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _restoreSession,
                  child: const Text('Reintentar'),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _session = null;
                    _restoreError = null;
                  }),
                  child: const Text('Ir al inicio de sesión'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_session == null) {
      return LoginPage(
        authRepository: widget.authRepository,
        onAuthenticated: (session) => setState(() => _session = session),
      );
    }

    return HomeShell(
      session: _session!,
      onLogout: () async {
        await widget.authRepository.clearSession();
        if (mounted) setState(() => _session = null);
      },
    );
  }
}
