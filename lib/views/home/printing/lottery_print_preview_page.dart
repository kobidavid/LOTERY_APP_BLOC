import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import 'lottery_print_renderer.dart';

class LotteryPrintPreviewPage extends StatefulWidget {
  const LotteryPrintPreviewPage({
    super.key,
    required this.rows,
  });

  final List<List<int?>> rows;

  @override
  State<LotteryPrintPreviewPage> createState() =>
      _LotteryPrintPreviewPageState();
}

class _LotteryPrintPreviewPageState extends State<LotteryPrintPreviewPage> {
  bool _debugMode = true;
  bool _includeDebugSample = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Print Preview'),
        actions: [
          IconButton(
            tooltip: 'Toggle anchor dots',
            icon: Icon(
              _debugMode ? Icons.bug_report : Icons.bug_report_outlined,
            ),
            onPressed: () => setState(() {
              _debugMode = !_debugMode;
            }),
          ),
          IconButton(
            tooltip: 'Toggle sample rows',
            icon: Icon(
              _includeDebugSample ? Icons.science : Icons.science_outlined,
            ),
            onPressed: () => setState(() {
              _includeDebugSample = !_includeDebugSample;
            }),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Text(
              _debugMode
                  ? 'Debug mode is enabled. Anchor dots are shown and the known sample selection is overlaid on tables 1 and 2.'
                  : 'Previewing the calibrated Lotto PDF overlay.',
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: PdfPreview(
              allowPrinting: false,
              allowSharing: false,
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
              build: (format) async {
                final LotteryPrintRenderResult result =
                    await LotteryPrintRenderer.renderPdf(
                  rows: widget.rows,
                  debugMode: _debugMode,
                  includeDebugSample: _includeDebugSample,
                );
                return result.pdfBytes;
              },
            ),
          ),
        ],
      ),
    );
  }
}
