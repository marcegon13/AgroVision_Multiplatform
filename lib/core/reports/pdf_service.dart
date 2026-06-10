import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../database/db_helper.dart';

/// SERVICIO DE REPORTES PDF (MÓDULO DE EXPORTACIÓN LOCAL)
///
/// Genera un documento PDF formal, tabulado y limpio con el historial de mediciones
/// del ganado almacenadas en la base de datos local.
class PdfService {
  /// Toma los registros de SQLite y abre la interfaz nativa del dispositivo para imprimir o guardar
  static Future<void> generateAndPrintReport(List<Deteccion> detecciones) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.copyWith(
          marginTop: 40,
          marginBottom: 40,
          marginLeft: 40,
          marginRight: 40,
        ),
        build: (pw.Context context) {
          return [
            // Encabezado principal formal centrado
            pw.Container(
              alignment: pw.Alignment.center,
              padding: const pw.EdgeInsets.only(bottom: 20),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(width: 1.0, color: PdfColors.grey400),
                ),
              ),
              child: pw.Column(
                children: [
                  pw.Text(
                    'AGROVISION IA - REPORTE DE INFERENCIA BIOMÉTRICA LOCAL',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.black,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'Documento generado de forma local y offline - Sistema Mobile Multiplataforma',
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Fecha de generación: ${DateTime.now().toLocal().toString().substring(0, 19)}',
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey600,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // Tabla de Registros
            pw.TableHelper.fromTextArray(
              border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey300),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 9,
                color: PdfColors.black,
              ),
              cellStyle: const pw.TextStyle(
                fontSize: 8,
                color: PdfColors.black,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey100,
              ),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              headerAlignment: pw.Alignment.center,
              cellAlignment: pw.Alignment.center,
              headers: [
                'Caravana ID',
                'Lote',
                'Fecha/Hora',
                'Peso Est. (kg)',
                'Condición Corp.',
                'Llenado Rum.',
                'Estado'
              ],
              data: detecciones.map((d) {
                return [
                  d.caravanaId,
                  d.loteId,
                  d.timestamp,
                  d.pesoEstimado.toStringAsFixed(2),
                  '${d.condicionCorporal.toStringAsFixed(2)}/5',
                  '${d.llenadoRuminal.toStringAsFixed(2)}/5',
                  d.estado,
                ];
              }).toList(),
            ),

            pw.SizedBox(height: 30),

            // Resumen estadístico simple al pie de la tabla
            pw.Container(
              alignment: pw.Alignment.centerRight,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Total animales auditados: ${detecciones.length}',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    'Promedio Peso Estimado: ${_calcularPromedioPeso(detecciones).toStringAsFixed(2)} kg',
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey800,
                    ),
                  ),
                ],
              ),
            ),
          ];
        },
      ),
    );

    // Disparador nativo para imprimir o guardar
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'reporte_biometrico_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  static double _calcularPromedioPeso(List<Deteccion> list) {
    if (list.isEmpty) return 0.0;
    double sum = 0.0;
    for (var d in list) {
      sum += d.pesoEstimado;
    }
    return sum / list.length;
  }
}
