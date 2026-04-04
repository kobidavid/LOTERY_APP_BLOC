import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'lottery_print_layout.dart';

class LotteryPrintRenderResult {
  const LotteryPrintRenderResult({
    required this.pdfBytes,
    required this.usedFallbackTemplate,
  });

  final Uint8List pdfBytes;
  final bool usedFallbackTemplate;
}

class LotteryPrintRenderer {
  const LotteryPrintRenderer._();

  static Future<LotteryPrintRenderResult> renderPdf({
    required List<List<int?>> rows,
    bool debugMode = false,
    bool includeDebugSample = false,
  }) async {
    final _CanvasRenderResult canvasResult = await _renderCanvas(
      rows: rows,
      debugMode: debugMode,
      includeDebugSample: includeDebugSample,
    );

    final pw.Document document = pw.Document();
    final pw.MemoryImage pageImage = pw.MemoryImage(canvasResult.pngBytes);

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          LotteryPrintLayout.pageSize.width,
          LotteryPrintLayout.pageSize.height,
          marginAll: 0,
        ),
        margin: pw.EdgeInsets.zero,
        build: (context) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Image(pageImage, fit: pw.BoxFit.fill),
        ),
      ),
    );

    return LotteryPrintRenderResult(
      pdfBytes: await document.save(),
      usedFallbackTemplate: canvasResult.usedFallbackTemplate,
    );
  }

  static Future<_CanvasRenderResult> _renderCanvas({
    required List<List<int?>> rows,
    required bool debugMode,
    required bool includeDebugSample,
  }) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(
      recorder,
      Offset.zero & LotteryPrintLayout.pageSize,
    );

    final ui.Image? background = await _loadTemplateImage();
    final bool usedFallbackTemplate = background == null;

    _paintBackground(
        canvas, LotteryPrintLayout.pageSize, background, debugMode);
    _paintSelections(
      canvas,
      rows: rows,
      color: Colors.black,
    );

    if (debugMode) {
      _paintAnchorDots(canvas);
      if (includeDebugSample) {
        _paintSelections(
          canvas,
          rows: LotteryPrintLayout.buildDebugSampleRows(),
          color: Colors.blueAccent,
        );
      }
    }

    final ui.Image image = await recorder.endRecording().toImage(
          LotteryPrintLayout.pageSize.width.round(),
          LotteryPrintLayout.pageSize.height.round(),
        );

    final ByteData? pngBytes =
        await image.toByteData(format: ui.ImageByteFormat.png);

    return _CanvasRenderResult(
      pngBytes: pngBytes!.buffer.asUint8List(),
      usedFallbackTemplate: usedFallbackTemplate,
    );
  }

  static Future<ui.Image?> _loadTemplateImage() async {
    try {
      final ByteData data =
          await rootBundle.load(LotteryPrintLayout.templatePreviewAssetPath);
      final Uint8List bytes = data.buffer.asUint8List();
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  static void _paintBackground(
    Canvas canvas,
    Size size,
    ui.Image? image,
    bool debugMode,
  ) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.white,
    );

    if (image != null) {
      paintImage(
        canvas: canvas,
        rect: Offset.zero & size,
        image: image,
        fit: BoxFit.fill,
      );
    }

    if (image == null || debugMode) {
      final Paint formOutlinePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = debugMode ? Colors.redAccent : Colors.grey.shade400;
      canvas.drawRect(LotteryPrintLayout.formBounds, formOutlinePaint);
    }

    if (image == null) {
      final TextPainter painter = TextPainter(
        textDirection: TextDirection.ltr,
        text: const TextSpan(
          text:
              'Calibrated preview only.\nAdd assets/images/lottery_form_template.png to preview over a scanned template page.',
          style: TextStyle(
            color: Colors.red,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      )..layout(maxWidth: size.width - 32);
      painter.paint(canvas, const Offset(24, 24));
    }
  }

  static void _paintSelections(
    Canvas canvas, {
    required List<List<int?>> rows,
    required Color color,
  }) {
    final Paint linePaint = Paint()
      ..color = color
      ..strokeWidth = LotteryPrintLayout.strokeWidth
      ..strokeCap = StrokeCap.round;

    for (int tableIndex = 0; tableIndex < rows.length; tableIndex++) {
      final List<int?> row = rows[tableIndex];

      for (final int number in row.take(6).whereType<int>()) {
        final Offset center = LotteryPrintLayout.calibratePoint(
          LotteryPrintLayout.getRegularNumberPosition(tableIndex, number),
        );
        const double halfLength = LotteryPrintLayout.regularLineLength / 2;
        canvas.drawLine(
          Offset(center.dx - halfLength, center.dy),
          Offset(center.dx + halfLength, center.dy),
          linePaint,
        );
      }

      final int? strongNumber = row.length > 6 ? row[6] : null;
      if (strongNumber == null) {
        continue;
      }

      final Offset center = LotteryPrintLayout.calibratePoint(
        LotteryPrintLayout.getStrongNumberPosition(tableIndex, strongNumber),
      );
      const double halfLength = LotteryPrintLayout.strongLineLength / 2;
      canvas.drawLine(
        Offset(center.dx - halfLength, center.dy),
        Offset(center.dx + halfLength, center.dy),
        linePaint,
      );
    }
  }

  static void _paintAnchorDots(Canvas canvas) {
    final Paint regularDotPaint = Paint()..color = Colors.deepOrangeAccent;
    final Paint strongDotPaint = Paint()..color = Colors.green;

    for (int tableIndex = 0; tableIndex < 14; tableIndex++) {
      for (final Offset point
          in LotteryPrintLayout.getAllRegularAnchorPositions(tableIndex)) {
        final Offset calibratedPoint = LotteryPrintLayout.calibratePoint(point);
        canvas.drawCircle(
          calibratedPoint,
          LotteryPrintLayout.debugAnchorRadius,
          regularDotPaint,
        );
      }
      for (final Offset point
          in LotteryPrintLayout.getAllStrongAnchorPositions(tableIndex)) {
        final Offset calibratedPoint = LotteryPrintLayout.calibratePoint(point);
        canvas.drawCircle(
          calibratedPoint,
          LotteryPrintLayout.debugAnchorRadius,
          strongDotPaint,
        );
      }
    }
  }
}

class _CanvasRenderResult {
  const _CanvasRenderResult({
    required this.pngBytes,
    required this.usedFallbackTemplate,
  });

  final Uint8List pngBytes;
  final bool usedFallbackTemplate;
}
