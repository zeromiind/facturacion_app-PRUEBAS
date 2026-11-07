class AppConfig {
  const AppConfig._();

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    // Descomenta SOLO una opción:
    //defaultValue: 'https://api.fycticonsulting.com', // PRODUCCIÓN
    defaultValue: 'https://facturacionbackendapi-test.up.railway.app', // TEST
    //defaultValue: 'http://10.0.2.2:8000', // LOCAL emulador Android
    //defaultValue: 'http://127.0.0.1:8000', // LOCAL celular físico (IP de tu PC)
  );

  static const loginTimeout = Duration(seconds: 60);
  static const apiTimeout = Duration(seconds: 20);
}
