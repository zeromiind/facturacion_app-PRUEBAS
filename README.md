# Facturacion App

Aplicacion Flutter para el flujo movil de facturacion. Este proyecto es
independiente del backend Laravel y del frontend web existentes.

## Estado inicial

La primera pantalla implementa el flujo local minimo para una venta:

- Catalogo de productos de muestra.
- Busqueda por nombre o categoria.
- Agregado y ajuste de cantidades.
- Calculo del total en soles.
- Preparacion local de la venta.

La sincronizacion con el backend, autenticacion, clientes, inventario y envio a
SUNAT se incorporaran por etapas, conservando este flujo como base.

## Ejecutar

Requiere Flutter stable.

```powershell
flutter pub get
flutter run
```

## Probar

```powershell
flutter test
```
