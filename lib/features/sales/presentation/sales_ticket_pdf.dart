import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/sales_documents_repository.dart';

int _lineCount(String text, {int charactersPerLine = 28}) =>
    math.max(1, (text.length / charactersPerLine).ceil());

PdfPageFormat salesTicketPageFormat(
  SaleDocument document, {
  required String companyName,
  required List<SaleDocumentItem> items,
  required bool showSunatStatus,
}) {
  final customer = document.customerName.trim().isEmpty
      ? 'Cliente varios'
      : document.customerName.trim();
  final details = <String>[
    if ((document.customerDocNumber ?? '').trim().isNotEmpty)
      'Documento: ${document.customerDocNumber}',
    if ((document.paymentMethod ?? '').trim().isNotEmpty)
      'Medio de pago: ${document.paymentMethod}',
    if (document.plate?.trim().isNotEmpty ?? false) 'Placa: ${document.plate}',
    if (document.vehicleLabel.trim().isNotEmpty)
      'Vehículo: ${document.vehicleLabel}',
  ];
  final itemLines = items.fold<int>(
    0,
    (count, item) =>
        count +
        _lineCount(item.description) +
        _lineCount(
          '${item.quantity.toStringAsFixed(2)} ${item.unitLabel ?? ''} x '
          '${item.unitPrice.toStringAsFixed(2)}',
        ) +
        2,
  );
  final estimatedLines =
      _lineCount(companyName) +
      _lineCount(customer) +
      details.fold<int>(0, (count, line) => count + _lineCount(line)) +
      itemLines +
      (showSunatStatus ? 11 : 10);
  return PdfPageFormat(
    58 * PdfPageFormat.mm,
    math.max(125.0, estimatedLines * 8.5 + 28),
    marginAll: 5,
  );
}

Future<Uint8List> buildSalesTicketPdf(
  SaleDocument document, {
  required String documentKindLabel,
  required String companyName,
  required String currencySymbol,
  required String statusLabel,
  required String sunatStatusLabel,
  required List<SaleDocumentItem> items,
  required bool showSunatStatus,
}) async {
  final customer = document.customerName.trim().isEmpty
      ? 'Cliente varios'
      : document.customerName.trim();
  final number = document.fullNumber;
  final date = document.issueAt == null
      ? '-'
      : '${document.issueAt!.day.toString().padLeft(2, '0')}/'
            '${document.issueAt!.month.toString().padLeft(2, '0')}/'
            '${document.issueAt!.year}';
  final kind = documentKindLabel.trim().isEmpty
      ? document.documentKind
      : documentKindLabel;
  final details = <String>[
    if ((document.customerDocNumber ?? '').trim().isNotEmpty)
      'Documento: ${document.customerDocNumber}',
    if ((document.paymentMethod ?? '').trim().isNotEmpty)
      'Medio de pago: ${document.paymentMethod}',
    if (document.plate?.trim().isNotEmpty ?? false) 'Placa: ${document.plate}',
    if (document.vehicleLabel.trim().isNotEmpty)
      'Vehículo: ${document.vehicleLabel}',
  ];
  final pdf = pw.Document();
  final regular = pw.Font.courier();
  final bold = pw.Font.courierBold();

  pw.Widget row(String label, String value, {bool emphasize = false}) => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Text(
          label,
          style: pw.TextStyle(
            font: emphasize ? bold : regular,
            fontSize: emphasize ? 9 : 7,
          ),
        ),
      ),
      pw.SizedBox(width: 3),
      pw.Text(
        value,
        textAlign: pw.TextAlign.right,
        style: pw.TextStyle(
          font: emphasize ? bold : regular,
          fontSize: emphasize ? 9 : 7,
        ),
      ),
    ],
  );

  pdf.addPage(
    pw.Page(
      pageFormat: salesTicketPageFormat(
        document,
        companyName: companyName,
        items: items,
        showSunatStatus: showSunatStatus,
      ),
      theme: pw.ThemeData.withFont(base: regular, bold: bold).copyWith(
        paragraphStyle: pw.TextStyle.defaultStyle().copyWith(
          font: regular,
          fontNormal: regular,
          fontBold: bold,
          fontSize: 7,
          lineSpacing: 0,
          height: 1,
        ),
      ),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            companyName,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: bold, fontSize: 9),
          ),
          pw.SizedBox(height: 4),
          pw.Divider(height: 1),
          pw.Text(
            kind.toUpperCase(),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: bold, fontSize: 8),
          ),
          pw.Text(
            number,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: bold, fontSize: 10),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Fecha: $date',
            style: pw.TextStyle(font: regular, fontSize: 7),
          ),
          pw.Text(
            'Cliente: $customer',
            style: pw.TextStyle(font: regular, fontSize: 7),
          ),
          for (final detail in details)
            pw.Text(detail, style: pw.TextStyle(font: regular, fontSize: 7)),
          pw.SizedBox(height: 4),
          pw.Divider(height: 1),
          if (items.isNotEmpty) ...[
            pw.Text('PRODUCTOS', style: pw.TextStyle(font: bold, fontSize: 7)),
            for (final item in items) ...[
              pw.SizedBox(height: 2),
              pw.Text(
                item.description,
                style: pw.TextStyle(font: regular, fontSize: 7),
              ),
              pw.Text(
                '${item.quantity.toStringAsFixed(2)} '
                '${item.unitLabel ?? ''} x '
                '$currencySymbol ${item.unitPrice.toStringAsFixed(2)}',
                style: pw.TextStyle(font: regular, fontSize: 6),
              ),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  'Importe: $currencySymbol ${item.total.toStringAsFixed(2)}',
                  style: pw.TextStyle(font: regular, fontSize: 6),
                ),
              ),
            ],
            pw.SizedBox(height: 4),
            pw.Divider(height: 1),
          ],
          row('Estado', statusLabel),
          if (showSunatStatus) row('SUNAT', sunatStatusLabel),
          pw.SizedBox(height: 4),
          pw.Divider(height: 1),
          row(
            'TOTAL',
            '$currencySymbol ${document.total.toStringAsFixed(2)}',
            emphasize: true,
          ),
          row(
            'Saldo',
            '$currencySymbol ${document.balanceDue.toStringAsFixed(2)}',
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'ID: ${document.id}',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: regular, fontSize: 6),
          ),
        ],
      ),
    ),
  );
  return pdf.save();
}
