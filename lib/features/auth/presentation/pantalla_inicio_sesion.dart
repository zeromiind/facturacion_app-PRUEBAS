import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../dato/servicio_autenticacion.dart';

class PantallaInicioSesion extends StatefulWidget {
  const PantallaInicioSesion({super.key});

  @override
  State<PantallaInicioSesion> createState() => _PantallaInicioSesionState();
}

class _PantallaInicioSesionState extends State<PantallaInicioSesion> {
  final _formKey = GlobalKey<FormState>();
  final _controladorUsuario = TextEditingController(text: 'rest');
  final _controladorContrasena = TextEditingController(text: '12345678');
  final _servicio = ServicioAutenticacion.instancia;
  bool _cargando = false;
  bool _verContrasena = false;
  String? _error;

  @override
  void dispose() {
    _controladorUsuario.dispose();
    _controladorContrasena.dispose();
    super.dispose();
  }

  Future<void> _ingresar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await _servicio.iniciarSesion(
        usuario: _controladorUsuario.text.trim(),
        contrasena: _controladorContrasena.text,
      );
      if (mounted) {
        context.go('/mesas');
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _cargando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.restaurant_menu, size: 48, color: esquema.primary),
                      const SizedBox(height: 16),
                      Text(
                        'Sistema de Facturación',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Módulo de Restaurante',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 32),
                      TextFormField(
                        controller: _controladorUsuario,
                        decoration: const InputDecoration(
                          labelText: 'Usuario',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingrese el usuario' : null,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _controladorContrasena,
                        obscureText: !_verContrasena,
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => _verContrasena = !_verContrasena),
                            icon: Icon(_verContrasena ? Icons.visibility_off : Icons.visibility),
                          ),
                        ),
                        validator: (v) => (v == null || v.isEmpty) ? 'Ingrese la contraseña' : null,
                        onFieldSubmitted: (_) => _ingresar(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          style: TextStyle(color: esquema.error),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _cargando ? null : _ingresar,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: _cargando
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Ingresar'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
