import 'package:flutter/material.dart';

import '../../models/lottery_form.dart';
import '../../repositories/lottery_form_repository.dart';
import 'lotto_form_anchor_layout.dart';
import 'lottery_ticket_preview.dart';

class SubmittedTicketPreviewPage extends StatefulWidget {
  const SubmittedTicketPreviewPage({
    super.key,
    required this.ownerUserId,
    required this.formId,
    required this.repository,
    this.title,
  });

  final String ownerUserId;
  final String formId;
  final LotteryFormRepository repository;
  final String? title;

  @override
  State<SubmittedTicketPreviewPage> createState() =>
      _SubmittedTicketPreviewPageState();
}

class _SubmittedTicketPreviewPageState
    extends State<SubmittedTicketPreviewPage> {
  bool _showDebug = true;
  String? _lastLogKey;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(titleText),
        actions: [
          IconButton(
            onPressed: () => setState(() => _showDebug = !_showDebug),
            tooltip: 'מצב דיבאג',
            icon: Icon(
              _showDebug ? Icons.bug_report : Icons.bug_report_outlined,
            ),
          ),
        ],
      ),
      body: StreamBuilder<LotteryForm>(
        stream: widget.repository.watchForm(
          userId: widget.ownerUserId,
          formId: widget.formId,
        ),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final LotteryForm form = snapshot.data!;
          _logDebugSamplesIfNeeded(form);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    _showDebug
                        ? 'מצב דיבאג פעיל: מוצגות נקודות עוגן ונקודות מחושבות.'
                        : 'תצוגה לקריאה בלבד מתוך הטופס שנשלח בפועל',
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
                        tables: form.tables,
                        showDebug: _showDebug,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String get titleText =>
      widget.title == null ? 'תצוגת טופס שנשלח' : 'תצוגת טופס: ${widget.title}';

  void _logDebugSamplesIfNeeded(LotteryForm form) {
    if (!_showDebug) {
      return;
    }

    final String key =
        '${form.formId}:${form.updatedAt?.millisecondsSinceEpoch}:$_showDebug';
    if (_lastLogKey == key) {
      return;
    }
    _lastLogKey = key;

    for (final String line in LottoFormAnchorLayout.debugSamples()) {
      debugPrint(line);
    }
  }
}
