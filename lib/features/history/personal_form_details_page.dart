import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/lottery_form.dart';
import '../../repositories/lottery_form_repository.dart';
import '../form_presentation_utils.dart';
import '../lottery_form/lottery_ticket_preview.dart';

class PersonalFormDetailsPage extends StatelessWidget {
  const PersonalFormDetailsPage({
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title ?? 'טופס אישי'),
      ),
      body: StreamBuilder<LotteryForm>(
        stream: repository.watchForm(
          userId: ownerUserId,
          formId: formId,
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
          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(ownerUserId)
                .collection('forms')
                .doc(formId)
                .snapshots(),
            builder: (context, rawSnapshot) {
              final Map<String, dynamic> rawData =
                  rawSnapshot.data?.data() ?? const <String, dynamic>{};
              final num ticketCost = _ticketCost(form);
              final String statusLabel = _statusLabel(form);
              final String winningsLabel = _winningStatusLabel(form);
              final String drawDateLabel = _formatDate(
                form.salesCloseAt ??
                    form.submittedAt ??
                    form.savedAt ??
                    form.updatedAt,
              );
              final DateTime? receiptUploadedAt = presentationAsDateTime(
                rawData['stationReceiptUploadedAt'],
              );
              final String? receiptUrl = extractReceiptUrl(rawData);
              final bool hasReceipt = _hasOpenableReceiptTarget(receiptUrl);
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  LotteryTicketPreviewCard(
                    filledTablesCount:
                        form.tables.where((table) => !table.isEmpty).length,
                    baseTicketCost: ticketCost,
                    isFullTicket: form.isComplete,
                    actionLabel: 'פתח תצוגת טופס',
                    onOpenFullScreen: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => LotteryTicketPreviewPage(
                            title: title ?? 'טופס אישי',
                            subtitle: 'תצוגה לקריאה בלבד של הטופס שנשמר במערכת',
                            tables: form.tables,
                            showDebug: false,
                          ),
                        ),
                      );
                    },
                    onSecondaryAction: hasReceipt
                        ? () => _openReceipt(
                              context: context,
                              receiptUrl: receiptUrl,
                            )
                        : null,
                    secondaryActionLabel: hasReceipt ? 'צפה בקבלה' : null,
                  ),
                  const SizedBox(height: 12),
                  _PersonalFormTracker(
                    form: form,
                  ),
                  const SizedBox(height: 12),
                  _InfoCard(
                    title: 'פרטי הטופס',
                    rows: [
                      _InfoRow(label: 'סוג', value: 'טופס אישי'),
                      _InfoRow(label: 'סטטוס', value: statusLabel),
                      _InfoRow(label: 'עלות טופס', value: '$ticketCost ש״ח'),
                      _InfoRow(label: 'תאריך הגרלה', value: drawDateLabel),
                      _InfoRow(
                        label: 'מועד שליחה',
                        value: _formatDate(form.submittedAt),
                      ),
                      _InfoRow(
                        label: 'מועד יצירה',
                        value: _formatDate(
                          form.createdAt ?? form.savedAt ?? form.updatedAt,
                        ),
                      ),
                      _InfoRow(label: 'זכייה', value: winningsLabel),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _InfoCard(
                    title: 'פרטי תוצאה וקבלה',
                    rows: [
                      _InfoRow(
                        label: 'מצב תוצאה',
                        value: _resultStatusLabel(form.resultStatus),
                      ),
                      _InfoRow(
                        label: 'קבלה מצורפת',
                        value: hasReceipt ? 'קיימת' : 'לא הועלתה',
                      ),
                      if (hasReceipt)
                        _InfoRow(
                          label: 'מועד העלאת קבלה',
                          value: _formatDate(receiptUploadedAt),
                        ),
                      _InfoRow(
                        label: 'מזהה טופס',
                        value: form.formId ?? 'לא זמין',
                        isMonospace: true,
                        canCopy: form.formId != null,
                      ),
                    ],
                    footer: null,
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  num _ticketCost(LotteryForm form) {
    final int populatedTableCount =
        form.tables.where((table) => !table.isEmpty).length;
    if (populatedTableCount <= 0) {
      return 0;
    }
    final int tablePairs = (populatedTableCount / 2).ceil();
    return tablePairs * 6;
  }

  String _statusLabel(LotteryForm form) {
    if (form.status == LotteryFormStatus.saved) {
      return 'טיוטה';
    }
    switch (form.resultStatus) {
      case LotteryResultStatus.winner:
        return 'זכייה';
      case LotteryResultStatus.loser:
        return 'ללא זכייה';
      case LotteryResultStatus.checked:
        return 'נבדק';
      case LotteryResultStatus.waitingForResults:
        return 'ממתין לתוצאות';
      case null:
        return form.status == LotteryFormStatus.submitted ? 'נשלח' : 'טיוטה';
    }
  }

  String _resultStatusLabel(LotteryResultStatus? status) {
    switch (status) {
      case LotteryResultStatus.waitingForResults:
        return 'ממתין לתוצאות';
      case LotteryResultStatus.checked:
        return 'נבדק';
      case LotteryResultStatus.winner:
        return 'זכייה';
      case LotteryResultStatus.loser:
        return 'ללא זכייה';
      case null:
        return 'לא זמין';
    }
  }

  String _winningStatusLabel(LotteryForm form) {
    if (form.resultStatus == null && form.winAmount <= 0) {
      return 'ממתין לתוצאות';
    }
    return '${_formatAmount(form.winAmount)} ש״ח';
  }

  String _formatDate(DateTime? date) {
    return formatPresentationDateTime(date);
  }

  bool _hasOpenableReceiptTarget(String? receiptUrl) {
    if (receiptUrl == null || receiptUrl.isEmpty) {
      return false;
    }
    final Uri? uri = Uri.tryParse(receiptUrl);
    return uri != null &&
        uri.hasScheme &&
        (uri.host.isNotEmpty || uri.scheme == 'file');
  }

  Future<void> _openReceipt({
    required BuildContext context,
    required String? receiptUrl,
  }) async {
    if (!_hasOpenableReceiptTarget(receiptUrl)) {
      return;
    }

    final Uri uri = Uri.parse(receiptUrl!);
    final bool launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('פתיחת הקבלה נכשלה.')),
      );
    }
  }
}

class _PersonalFormTracker extends StatefulWidget {
  const _PersonalFormTracker({
    required this.form,
  });

  final LotteryForm form;

  @override
  State<_PersonalFormTracker> createState() => _PersonalFormTrackerState();
}

class _PersonalFormTrackerState extends State<_PersonalFormTracker>
    with SingleTickerProviderStateMixin {
  static const List<_TrackerStepData> _steps = <_TrackerStepData>[
    _TrackerStepData(label: 'הגשת הטופס', icon: Icons.send_rounded),
    _TrackerStepData(label: 'הדפסת הטופס', icon: Icons.print_rounded),
    _TrackerStepData(label: 'מסירה בתחנה', icon: Icons.storefront_rounded),
    _TrackerStepData(label: 'בדיקת תוצאות', icon: Icons.verified_outlined),
  ];

  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int completedCount = _deriveCompletedStepCount();
    final int? currentIndex =
        completedCount >= _steps.length ? null : completedCount;
    final ThemeData theme = Theme.of(context);
    final Color trackerColor = theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'מעקב התקדמות הטופס',
            textAlign: TextAlign.right,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          Directionality(
            textDirection: TextDirection.rtl,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List<Widget>.generate(_steps.length, (stepIndex) {
                final _TrackerStepData step = _steps[stepIndex];
                return Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            return _TrackerStep(
                              step: step,
                              isCompleted: stepIndex < completedCount,
                              isCurrent: currentIndex != null &&
                                  stepIndex == currentIndex,
                              pulseValue: _pulseController.value,
                              color: trackerColor,
                            );
                          },
                        ),
                      ),
                      if (stepIndex < _steps.length - 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: _TrackerConnector(
                            filled: completedCount > stepIndex,
                            glow: currentIndex != null &&
                                currentIndex == stepIndex + 1,
                            color: trackerColor,
                          ),
                        ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  int _deriveCompletedStepCount() {
    if (_areResultsChecked) {
      return 4;
    }
    if (_isSubmittedToStationCompleted) {
      return 3;
    }
    if (_isPrintedCompleted) {
      return 2;
    }
    if (_isSubmitted) {
      return 1;
    }
    return 0;
  }

  bool get _isSubmitted => widget.form.submittedAt != null;

  bool get _isPrintedCompleted => widget.form.printedAt != null;

  bool get _isSubmittedToStationCompleted =>
      widget.form.submittedToStationAt != null;

  bool get _areResultsChecked =>
      widget.form.resultStatus == LotteryResultStatus.checked ||
      widget.form.resultStatus == LotteryResultStatus.winner ||
      widget.form.resultStatus == LotteryResultStatus.loser;
}

class _TrackerStepData {
  const _TrackerStepData({
    required this.label,
    required this.icon,
  });

  final String label;
  final IconData icon;
}

class _TrackerConnector extends StatelessWidget {
  const _TrackerConnector({
    required this.filled,
    required this.glow,
    required this.color,
  });

  final bool filled;
  final bool glow;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final Color baseColor = Theme.of(context)
        .colorScheme
        .outlineVariant
        .withValues(alpha: 0.45);
    return Container(
      width: 10,
      height: 4,
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: glow ? 0.8 : 0.65) : baseColor,
        borderRadius: BorderRadius.circular(999),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.18),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }
}

class _TrackerStep extends StatelessWidget {
  const _TrackerStep({
    required this.step,
    required this.isCompleted,
    required this.isCurrent,
    required this.pulseValue,
    required this.color,
  });

  final _TrackerStepData step;
  final bool isCompleted;
  final bool isCurrent;
  final double pulseValue;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color futureColor = theme.colorScheme.outlineVariant;
    final Color effectiveColor = isCompleted || isCurrent ? color : futureColor;
    final double scale = isCurrent ? 1 + (pulseValue * 0.04) : 1;

    return Column(
      children: [
        Transform.scale(
          scale: scale,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            width: isCurrent ? 28 : 24,
            height: isCurrent ? 28 : 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCompleted
                  ? effectiveColor
                  : isCurrent
                      ? effectiveColor.withValues(alpha: 0.14)
                      : theme.colorScheme.surface,
              border: Border.all(
                color: effectiveColor.withValues(
                  alpha: isCompleted ? 1 : (isCurrent ? 0.9 : 0.4),
                ),
                width: isCurrent ? 2.2 : 1.4,
              ),
              boxShadow: isCurrent
                  ? [
                      BoxShadow(
                        color: effectiveColor.withValues(alpha: 0.18),
                        blurRadius: 10 + (pulseValue * 6),
                        spreadRadius: 0.8 + (pulseValue * 1.2),
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              isCompleted ? Icons.check_rounded : step.icon,
              size: isCurrent ? 14 : 12,
              color: isCompleted
                  ? theme.colorScheme.onPrimary
                  : isCurrent
                      ? effectiveColor
                      : futureColor.withValues(alpha: 0.9),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          step.label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: isCompleted || isCurrent
                ? theme.colorScheme.onSurface
                : futureColor,
            fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w700,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}

String _formatAmount(num value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toStringAsFixed(1);
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.rows,
    this.footer,
  });

  final String title;
  final List<_InfoRow> rows;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 12),
          ...rows,
          if (footer != null) ...[
            const SizedBox(height: 8),
            footer!,
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.isMonospace = false,
    this.canCopy = false,
  });

  final String label;
  final String value;
  final bool isMonospace;
  final bool canCopy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Text(
            '$label:',
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: isMonospace ? 'monospace' : null,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (canCopy)
            IconButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('הועתק ללוח')),
                );
              },
              icon: const Icon(Icons.copy_outlined, size: 18),
              tooltip: 'העתק',
            ),
        ],
      ),
    );
  }
}
