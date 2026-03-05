import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PdfService {

  /// Generates a PDF with a grid of QR Codes for a specific item
  Future<void> printItemLabels(String itemName, String itemId, int quantity) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return pw.Wrap(
            spacing: 12,
            runSpacing: 12,
            children: List.generate(quantity, (index) {
              return _buildLabel(itemName, itemId);
            }),
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Labels_$itemName.pdf',
    );
  }

  pw.Widget _buildLabel(String name, String data) {
    return pw.Container(
      width: 180,
      height: 72,
      padding: const pw.EdgeInsets.all(4),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: 1),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        children: [
          pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: data,
            width: 50,
            height: 50,
            color: PdfColors.black,
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(
                  name,
                  maxLines: 2,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                  overflow: pw.TextOverflow.clip
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  data.substring(0, data.length > 6 ? 6 : data.length).toUpperCase(),
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
