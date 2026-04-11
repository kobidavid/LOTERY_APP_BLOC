import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'lotto_physical_layout.dart';
import 'lottery_print_layout.dart' show LotteryPrintLayout; // debug sample only

/// Result of a physical-print render.
///
/// Identical shape to [LotteryPrintRenderResult] so callers can treat both
/// renderers uniformly if needed — but this is a separate type so the two
/// pipelines never share state.
class LotteryPhysicalPrintRenderResult {
  const LotteryPhysicalPrintRenderResult({
    required this.pdfBytes,
  });

  final Uint8List pdfBytes;
}

/// Renderer for physical placement printing onto a real Israeli Lotto form.
///
/// Output is a PDF whose page is declared at the exact physical paper size
/// (82 × 252 mm).  The page contains ONLY vector marks — no background image,
/// no rasterisation.  When the operator prints at ACTUAL SIZE (100 %, no
/// scaling) each mark lands at the physical position of the corresponding box
/// on the pre-printed paper form.
///
/// This class is completely independent of [LotteryPrintRenderer].
/// The existing visual/logical print flow is unaffected.
class LotteryPhysicalPrintRenderer {
  const LotteryPhysicalPrintRenderer._();

  /// Render [rows] to a calibrated physical-placement PDF.
  ///
  /// [rows] — 14 rows × 7 slots:
  ///   slots 0–5 = regular numbers (1–37, or null if not selected),
  ///   slot  6   = strong number   (1–7,  or null if not selected).
  ///
  /// [layout] — supply a [LottoPhysicalLayout] with non-zero calibration
  ///   offsets after measuring the first print error in millimetres.
  ///
  /// [debugMode] — when true, draws small filled squares at every anchor
  ///   position so the operator can verify alignment before final use.
  ///
  /// [includeDebugSample] — when true AND [debugMode] is true, overlays the
  ///   known sample selection (tables 1–2) in blue for cross-checking.
  static Future<LotteryPhysicalPrintRenderResult> renderPdf({
    required List<List<int?>> rows,
    LottoPhysicalLayout layout = const LottoPhysicalLayout(),
    bool debugMode = false,
    bool includeDebugSample = false,
  }) async {
    final pw.Document document = pw.Document();

    document.addPage(
      pw.Page(
        // Page is declared at the exact physical paper size — no margins.
        pageFormat: PdfPageFormat(
          LottoPhysicalLayout.pageWidthPt,
          LottoPhysicalLayout.pageHeightPt,
          marginAll: 0,
        ),
        margin: pw.EdgeInsets.zero,
        build: (context) => pw.FullPage(
          ignoreMargins: true,
          child: pw.CustomPaint(
            size: const PdfPoint(
              LottoPhysicalLayout.pageWidthPt,
              LottoPhysicalLayout.pageHeightPt,
            ),
            painter: (canvas, size) {
              // 1. Actual selection marks in black.
              _drawMarks(
                canvas,
                rows: rows,
                layout: layout,
                color: PdfColors.black,
              );

              // 2. Optional known-sample overlay (blue) for calibration check.
              if (debugMode && includeDebugSample) {
                _drawMarks(
                  canvas,
                  rows: LotteryPrintLayout.buildDebugSampleRows(),
                  layout: layout,
                  color: PdfColors.blue,
                );
              }

              // 3. Anchor dots: orange = regular boxes, green = strong boxes.
              if (debugMode) {
                _drawAnchorDots(canvas, layout: layout);
              }
            },
          ),
        ),
      ),
    );

    return LotteryPhysicalPrintRenderResult(
      pdfBytes: await document.save(),
    );
  }

  // ---------------------------------------------------------------------------
  // Private drawing helpers
  // ---------------------------------------------------------------------------

  /// Draws a horizontal mark centred on each selected number's box.
  static void _drawMarks(
    PdfGraphics canvas, {
    required List<List<int?>> rows,
    required LottoPhysicalLayout layout,
    required PdfColor color,
  }) {
    canvas.setStrokeColor(color);
    canvas.setLineWidth(LottoPhysicalLayout.markStrokeWidthPt);

    for (int tableIndex = 0; tableIndex < rows.length; tableIndex++) {
      final List<int?> row = rows[tableIndex];

      // Regular numbers: slots 0–5.
      for (final int number in row.take(6).whereType<int>()) {
        final PdfPoint center = layout.regularNumberPosition(tableIndex, number);
        canvas.moveTo(
          center.x - LottoPhysicalLayout.regularMarkHalfLengthPt,
          center.y,
        );
        canvas.lineTo(
          center.x + LottoPhysicalLayout.regularMarkHalfLengthPt,
          center.y,
        );
        canvas.strokePath();
      }

      // Strong number: slot 6.
      if (row.length > 6 && row[6] != null) {
        final int strongNumber = row[6]!;
        final PdfPoint center =
            layout.strongNumberPosition(tableIndex, strongNumber);
        canvas.moveTo(
          center.x - LottoPhysicalLayout.strongMarkHalfLengthPt,
          center.y,
        );
        canvas.lineTo(
          center.x + LottoPhysicalLayout.strongMarkHalfLengthPt,
          center.y,
        );
        canvas.strokePath();
      }
    }
  }

  /// Draws a small filled square at every box centre for calibration
  /// verification.  Orange = regular numbers, green = strong numbers.
  static void _drawAnchorDots(
    PdfGraphics canvas, {
    required LottoPhysicalLayout layout,
  }) {
    const double half = LottoPhysicalLayout.debugDotHalfSizePt;

    canvas.setFillColor(PdfColors.orange);
    for (int tableIndex = 0; tableIndex < 14; tableIndex++) {
      for (int number = 1; number <= 37; number++) {
        final PdfPoint c = layout.regularNumberPosition(tableIndex, number);
        canvas.drawRect(c.x - half, c.y - half, half * 2, half * 2);
        canvas.fillPath();
      }
    }

    canvas.setFillColor(PdfColors.green);
    for (int tableIndex = 0; tableIndex < 14; tableIndex++) {
      for (int strongNumber = 1; strongNumber <= 7; strongNumber++) {
        final PdfPoint c =
            layout.strongNumberPosition(tableIndex, strongNumber);
        canvas.drawRect(c.x - half, c.y - half, half * 2, half * 2);
        canvas.fillPath();
      }
    }
  }
}
