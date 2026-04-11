import 'dart:ui' show Offset;

import 'package:pdf/pdf.dart' show PdfPoint;

import '../../../features/lottery_form/lotto_form_anchor_layout.dart';

/// Physical coordinate mapping for the Israeli Lotto paper form.
///
/// Source coordinates are pixels from [LottoFormAnchorLayout] (500×1516 px
/// template).  This class converts them to PDF points for direct vector
/// drawing at physical positions on the real printed form.
///
/// Coordinate system notes:
///   - Template origin: top-left, y increases downward.
///   - PDF page origin: bottom-left, y increases upward.
///   - [toPdfPoint] handles the axis flip automatically.
///
/// Calibration:
///   After a first print, measure how far marks landed from box centres and
///   set [calibrationDxMm] / [calibrationDyMm] to compensate.
///   Positive dx  → marks shift RIGHT on paper.
///   Positive dy  → marks shift DOWN  on paper.
class LottoPhysicalLayout {
  const LottoPhysicalLayout({
    this.calibrationDxMm = 3,
    this.calibrationDyMm = -7,
  });

  // -------------------------------------------------------------------------
  // Physical paper dimensions (measured manually from a real blank form).
  // -------------------------------------------------------------------------

  static const double formWidthMm = 82.0;
  static const double formHeightMm = 252.0;

  // -------------------------------------------------------------------------
  // Template pixel dimensions — must match LottoFormAnchorLayout.
  // -------------------------------------------------------------------------

  static const double _templateWidthPx = 500.0;
  static const double _templateHeightPx = 1516.0;

  // -------------------------------------------------------------------------
  // Unit conversion:  1 mm = 72 / 25.4 PDF points.
  // -------------------------------------------------------------------------

  static const double mmToPt = 72.0 / 25.4; // ≈ 2.8346

  // -------------------------------------------------------------------------
  // Derived PDF page size.
  // -------------------------------------------------------------------------

  static const double pageWidthPt = formWidthMm * mmToPt;
  static const double pageHeightPt = formHeightMm * mmToPt;

  // -------------------------------------------------------------------------
  // Physical mark dimensions.
  //
  // Regular column step  ≈ (387 − 155) / 6 × 0.164 mm/px ≈ 6.3 mm → 4.5 mm mark.
  // Strong  column step  ≈ (462 − 426) ×   0.164 mm/px   ≈ 5.9 mm → 3.5 mm mark.
  // -------------------------------------------------------------------------

  static const double regularMarkHalfLengthPt = (4.5 / 2) * mmToPt;
  static const double strongMarkHalfLengthPt = (3.5 / 2) * mmToPt;
  static const double markStrokeWidthPt = 0.6 * mmToPt;

  // Debug anchor dot: 0.7 mm half-size square.
  static const double debugDotHalfSizePt = 0.7 * mmToPt;

  // -------------------------------------------------------------------------
  // Per-printer calibration offsets (mm).
  // -------------------------------------------------------------------------

  /// Shifts all marks right on paper when positive.
  final double calibrationDxMm;

  /// Shifts all marks down on paper when positive.
  final double calibrationDyMm;

  // -------------------------------------------------------------------------
  // Coordinate conversion.
  // -------------------------------------------------------------------------

  /// Convert a template-pixel [Offset] to a PDF-point [PdfPoint].
  ///
  /// This is the single authoritative transformation for the whole pipeline.
  /// All other position methods go through here.
  PdfPoint toPdfPoint(Offset templatePx) {
    final double x =
        (templatePx.dx / _templateWidthPx) * formWidthMm * mmToPt +
            calibrationDxMm * mmToPt;

    // Y is flipped: template y=0 is the top; PDF y=0 is the bottom.
    final double y =
        pageHeightPt -
            (templatePx.dy / _templateHeightPx) * formHeightMm * mmToPt -
            calibrationDyMm * mmToPt;

    return PdfPoint(x, y);
  }

  // -------------------------------------------------------------------------
  // Position helpers — delegate to LottoFormAnchorLayout for pixel coords.
  // -------------------------------------------------------------------------

  /// Centre of the box for [number] (1–37) in [tableIndex] (0–13).
  PdfPoint regularNumberPosition(int tableIndex, int number) =>
      toPdfPoint(LottoFormAnchorLayout.getNumberPosition(tableIndex, number));

  /// Centre of the box for [strongNumber] (1–7) in [tableIndex] (0–13).
  PdfPoint strongNumberPosition(int tableIndex, int strongNumber) => toPdfPoint(
        LottoFormAnchorLayout.getStrongNumberPosition(tableIndex, strongNumber),
      );
}
