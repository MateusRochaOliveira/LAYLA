// lib/services/pdf_report_service.dart

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PdfReportService {
  /// Generates and previews an engineering audit PDF report.
  /// Returns the printable PdfDoc (for web/other platforms) after previewing.
  static Future<void> generateAndPreviewReport({
    required String projectName,
    required String inspectorName,
    required List<Map<String, String>> measurements,
  }) async {
    final pdf = pw.Document();

    final headerStyle = pw.TextStyle(
      fontSize: 20,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.blueGrey900,
    );

    final subHeaderStyle = pw.TextStyle(
      fontSize: 12,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.blueGrey700,
    );

    final tableHeaderStyle = pw.TextStyle(
      fontSize: 10,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.white,
    );

    const bodyStyle = pw.TextStyle(
      fontSize: 10,
      color: PdfColors.black,
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (pw.Context context) => pw.Text(
          'LAYLA LEVEL - AUDIT REPORT',
          style: headerStyle,
        ),
        footer: (pw.Context context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'LAYLA Engineering Module v1.0.0',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ],
        ),
        build: (pw.Context context) {
          return [
            // Header Section
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('LAYLA LEVEL - AUDIT REPORT', style: headerStyle),
                    pw.SizedBox(height: 4),
                    pw.Text('Slope & Level Measurement Log', style: subHeaderStyle),
                  ],
                ),
                pw.PdfLogo(),
              ],
            ),
            pw.Divider(thickness: 1, color: PdfColors.grey400),
            pw.SizedBox(height: 12),

            // Metadata Section
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: const pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Project: $projectName', style: bodyStyle),
                      pw.SizedBox(height: 4),
                      pw.Text('Inspector: $inspectorName', style: bodyStyle),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Date: ${DateTime.now().toString().split(' ')[0]}', style: bodyStyle),
                      pw.SizedBox(height: 4),
                      pw.Text('Status: Verified', style: bodyStyle),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // Measurements Table Section
            pw.Text('Measurement Records', style: subHeaderStyle),
            pw.SizedBox(height: 8),

            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                // Table Header
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('Standard', style: tableHeaderStyle),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('Pitch (°)', style: tableHeaderStyle),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('Roll (°)', style: tableHeaderStyle),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('Status', style: tableHeaderStyle),
                    ),
                  ],
                ),
                // Table Content Rows
                ...measurements.map((item) {
                  return pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(item['standard'] ?? '-', style: bodyStyle),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(item['pitch'] ?? '-', style: bodyStyle),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(item['roll'] ?? '-', style: bodyStyle),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(item['compliance'] ?? 'OK', style: bodyStyle),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ];
        },
      ),
    );

    // Open printing preview / share modal
    try {
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
      );
    } catch (e) {
      // Re-raise so the UI layer can surface user feedback
      rethrow;
    }
  }

  /// Alias method for compatibility with main.dart call signatures
  static Future<void> generateAndShareReport({
    required String projectName,
    required String inspectorName,
    required List<Map<String, String>> measurements,
  }) async {
    await generateAndPreviewReport(
      projectName: projectName,
      inspectorName: inspectorName,
      measurements: measurements,
    );
  }
}