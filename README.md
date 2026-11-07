# Facturacion App

Aplicacion Flutter para el flujo movil de facturacion. Este proyecto es
independiente del backend Laravel y del frontend web existentes.

## Estado actual

La aplicación inicia con autenticación contra el backend Laravel y, después de
iniciar sesión, muestra el flujo local mínimo para una venta:

- Catalogo de productos de muestra.
- Busqueda por nombre o categoria.
- Agregado y ajuste de cantidades.
- Calculo del total en soles.
- Preparacion local de la venta.

La sesión se guarda con almacenamiento seguro y se conserva entre reinicios
hasta que expire. Las APIs de ventas, clientes, inventario y SUNAT se
incorporarán por etapas, conservando este flujo como base.

## Ejecutar contra backend local

Requiere Flutter stable y un backend disponible en el puerto `8000`.

```powershell
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

`10.0.2.2` es la dirección del host desde Android Emulator. Para iOS
Simulator usa `http://127.0.0.1:8000`. En un dispositivo físico usa la IP
local de la PC, por ejemplo `http://192.168.1.20:8000`, y permite el puerto
`8000` en el firewall.

## Ejecutar contra Railway

Reemplaza la URL por el dominio público del backend Railway:

```powershell
flutter run --release `
  --dart-define=API_BASE_URL=https://backend.example.up.railway.app
```

La URL se entrega en tiempo de compilación; no se incluyen credenciales ni
URLs de producción en el código de la aplicación.

## Probar

```powershell
flutter test
```
