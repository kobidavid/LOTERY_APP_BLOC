import 'package:flutter/material.dart';

import '../../models/lottery_table.dart';
import 'lotto_form_anchor_layout.dart';

class LotteryTicketPreviewCard extends StatelessWidget {
  const LotteryTicketPreviewCard({
    super.key,
    required this.filledTablesCount,
    required this.baseTicketCost,
    required this.isFullTicket,
    this.onOpenFullScreen,
    this.actionLabel = 'צפה בטופס',
  });

  final int filledTablesCount;
  final num baseTicketCost;
  final bool isFullTicket;
  final VoidCallback? onOpenFullScreen;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'הטופס הקבוצתי',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              if (onOpenFullScreen != null)
                TextButton.icon(
                  onPressed: onOpenFullScreen,
                  icon: const Icon(Icons.open_in_full_outlined),
                  label: Text(actionLabel),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _PreviewMetaChip(
                label: 'טבלאות',
                value: '$filledTablesCount',
              ),
              _PreviewMetaChip(
                label: 'עלות בסיס',
                value: '$baseTicketCost ש״ח',
              ),
              _PreviewMetaChip(
                label: 'סוג טופס',
                value: isFullTicket ? 'טופס מלא' : 'טופס חלקי',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class LotteryTicketPreviewPage extends StatelessWidget {
  const LotteryTicketPreviewPage({
    super.key,
    required this.title,
    required this.tables,
    required this.showDebug,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<LotteryTable> tables;
  final bool showDebug;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                  textAlign: TextAlign.right,
                ),
              ),
            ),
          Expanded(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: LotteryTicketPreviewCanvas(
                    tables: tables,
                    showDebug: showDebug,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LotteryTicketPreviewCanvas extends StatelessWidget {
  const LotteryTicketPreviewCanvas({
    super.key,
    required this.tables,
    required this.showDebug,
    this.borderRadius = 20,
  });

  final List<LotteryTable> tables;
  final bool showDebug;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: LottoFormAnchorLayout.templateAspectRatio,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: const [
            BoxShadow(
              blurRadius: 18,
              offset: Offset(0, 8),
              color: Color(0x22000000),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const Image(
                image: AssetImage(LottoFormAnchorLayout.backgroundAssetPath),
                fit: BoxFit.fill,
              ),
              RepaintBoundary(
                child: CustomPaint(
                  painter: _LotteryTicketPainter(
                    tables: tables,
                    showDebug: showDebug,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LotteryTicketPainter extends CustomPainter {
  const _LotteryTicketPainter({
    required this.tables,
    required this.showDebug,
  });

  final List<LotteryTable> tables;
  final bool showDebug;

  @override
  void paint(Canvas canvas, Size size) {
    LotteryTicketRenderer.paint(
      canvas: canvas,
      size: size,
      tables: tables,
      showDebug: showDebug,
    );
  }

  @override
  bool shouldRepaint(covariant _LotteryTicketPainter oldDelegate) {
    return oldDelegate.tables != tables || oldDelegate.showDebug != showDebug;
  }
}

class LotteryTicketRenderer {
  const LotteryTicketRenderer._();

  static void paint({
    required Canvas canvas,
    required Size size,
    required List<LotteryTable> tables,
    required bool showDebug,
  }) {
    final double scaleX = LottoFormAnchorLayout.scaleX(size);
    final double scaleY = LottoFormAnchorLayout.scaleY(size);
    final Paint markPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = LottoFormAnchorLayout.strokeWidthPx * scaleY;

    final double horizontalInset =
        LottoFormAnchorLayout.strokeInsetXPx * scaleX;
    final double lineWidth =
        (LottoFormAnchorLayout.strokeLogicalWidthPx * scaleX) -
            (horizontalInset * 2);
    final double halfLineWidth = lineWidth / 2;
    final double boxVerticalOffset =
        LottoFormAnchorLayout.boxVerticalOffsetPx * scaleY;

    for (final LotteryTable table in tables) {
      final int tableIndex = table.tableIndex - 1;
      if (tableIndex < 0 || tableIndex > 13) {
        continue;
      }

      for (final int number in table.regularNumbers) {
        final Offset center = LottoFormAnchorLayout.mapToCanvas(
          LottoFormAnchorLayout.getNumberPosition(tableIndex, number),
          size,
        );
        final double adjustedY = center.dy + boxVerticalOffset;
        canvas.drawLine(
          Offset(center.dx - halfLineWidth, adjustedY),
          Offset(center.dx + halfLineWidth, adjustedY),
          markPaint,
        );
      }

      final int? strongNumber = table.strongNumber;
      if (strongNumber == null) {
        continue;
      }

      final Offset center = LottoFormAnchorLayout.mapToCanvas(
        LottoFormAnchorLayout.getStrongNumberPosition(tableIndex, strongNumber),
        size,
      );
      final double adjustedY = center.dy + boxVerticalOffset;
      canvas.drawLine(
        Offset(center.dx - halfLineWidth, adjustedY),
        Offset(center.dx + halfLineWidth, adjustedY),
        markPaint,
      );
    }

    if (showDebug) {
      _paintDebugDots(canvas, size);
    }
  }

  static void _paintDebugDots(Canvas canvas, Size size) {
    final Paint anchorPaint = Paint()..color = Colors.red;
    final Paint computedPaint = Paint()..color = const Color(0xCCFF5252);

    for (final Offset anchor in LottoFormAnchorLayout.anchorPoints) {
      canvas.drawCircle(
        LottoFormAnchorLayout.mapToCanvas(anchor, size),
        2.2,
        anchorPaint,
      );
    }

    for (final Offset point in LottoFormAnchorLayout.getAllRegularPositions()) {
      canvas.drawCircle(
        LottoFormAnchorLayout.mapToCanvas(point, size),
        1.4,
        computedPaint,
      );
    }

    for (final Offset point in LottoFormAnchorLayout.getAllStrongPositions()) {
      canvas.drawCircle(
        LottoFormAnchorLayout.mapToCanvas(point, size),
        1.4,
        computedPaint,
      );
    }
  }
}

class _PreviewMetaChip extends StatelessWidget {
  const _PreviewMetaChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}
