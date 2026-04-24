import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/lottery_form.dart';
import '../../repositories/lottery_form_repository.dart';
import '../form_presentation_utils.dart';
import '../lottery_form/lottery_ticket_preview.dart';

class PersonalSubmissionBundleDetailsPage extends StatelessWidget {
  const PersonalSubmissionBundleDetailsPage({
    super.key,
    required this.ownerUserId,
    required this.bundle,
    required this.repository,
  });

  final String ownerUserId;
  final PersonalSubmittedBundle bundle;
  final LotteryFormRepository repository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('שליחת טפסים אישיים')),
      body: StreamBuilder<List<PersonalSubmittedBundleForm>>(
        stream: repository.watchPersonalSubmissionBundleForms(
          userId: ownerUserId,
          submissionId: bundle.submissionId,
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

          final List<PersonalSubmittedBundleForm> forms =
              snapshot.data ?? bundle.forms;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _BundleSummaryCard(bundle: bundle, forms: forms),
              const SizedBox(height: 12),
              _BundleFormsSection(forms: forms),
            ],
          );
        },
      ),
    );
  }
}

class _BundleSummaryCard extends StatelessWidget {
  const _BundleSummaryCard({
    required this.bundle,
    required this.forms,
  });

  final PersonalSubmittedBundle bundle;
  final List<PersonalSubmittedBundleForm> forms;

  @override
  Widget build(BuildContext context) {
    final int totalTables = forms.fold<int>(
      0,
      (int total, PersonalSubmittedBundleForm form) => total + form.tableCount,
    );
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
            'סיכום שליחה',
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 12),
          _SummaryRow(label: 'מספר טפסים', value: '${forms.length}'),
          _SummaryRow(label: 'סה״כ טבלאות', value: '$totalTables'),
          _SummaryRow(
            label: 'עלות כוללת',
            value: '${_formatAmount(bundle.totalCost)} ש״ח',
          ),
          _SummaryRow(
            label: 'נשלח',
            value: formatPresentationDateTime(bundle.submittedAt),
          ),
        ],
      ),
    );
  }
}

class _PersonalFormTracker extends StatefulWidget {
  const _PersonalFormTracker({
    required this.form,
  });

  final PersonalSubmittedBundleForm form;

  @override
  State<_PersonalFormTracker> createState() => _PersonalFormTrackerState();
}

class _PersonalFormTrackerState extends State<_PersonalFormTracker>
    with SingleTickerProviderStateMixin {
  static const List<_TrackerStepData> _steps = <_TrackerStepData>[
    _TrackerStepData(label: 'הגשת הטפסים', icon: Icons.send_rounded),
    _TrackerStepData(label: 'הדפסת הטפסים', icon: Icons.print_rounded),
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
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
    if (_areAllSubmittedToStation) {
      return 3;
    }
    if (_areAllPrinted) {
      return 2;
    }
    if (_isSubmitted) {
      return 1;
    }
    return 0;
  }

  bool get _isSubmitted => widget.form.submittedAt != null;

  bool get _areAllPrinted =>
      widget.form.printedAt != null;

  bool get _areAllSubmittedToStation =>
      widget.form.submittedToStationAt != null;

  bool get _areResultsChecked =>
      widget.form.resultStatus == LotteryResultStatus.checked ||
      widget.form.resultStatus == LotteryResultStatus.winner ||
      widget.form.resultStatus == LotteryResultStatus.loser;
}

class _BundleFormsSection extends StatelessWidget {
  const _BundleFormsSection({
    required this.forms,
  });

  final List<PersonalSubmittedBundleForm> forms;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'הטפסים שנשלחו',
            textAlign: TextAlign.right,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          ...List.generate(forms.length, (index) {
            final PersonalSubmittedBundleForm form = forms[index];
            return Column(
              children: [
                _BundleFormRow(form: form),
                if (index < forms.length - 1)
                  Divider(
                    height: 18,
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _BundleFormRow extends StatelessWidget {
  const _BundleFormRow({
    required this.form,
  });

  final PersonalSubmittedBundleForm form;

  @override
  Widget build(BuildContext context) {
    final bool canOpenReceipt = _hasOpenableReceiptTarget(form.receiptUrl);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'טופס ${form.displayOrder}',
          textAlign: TextAlign.right,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 6,
          children: [
            _MetaText(value: 'סוג טופס: ${form.isDoubleMode ? 'דאבל' : 'רגיל'}'),
            _MetaText(value: 'מספר טבלאות: ${form.tableCount}'),
            _MetaText(value: 'עלות הטופס: ${_formatAmount(form.cost)} ש״ח'),
            _MetaText(value: 'זכייה: ${_formWinningStatusLabel(form)}'),
          ],
        ),
        const SizedBox(height: 10),
        _PersonalFormTracker(form: form),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 10,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LotteryTicketPreviewPage(
                      title: 'טופס ${form.displayOrder}',
                      subtitle: 'תצוגה לקריאה בלבד של טופס מתוך שליחה מרובת טפסים',
                      tables: form.tables,
                      showDebug: false,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('צפה בטופס'),
            ),
            OutlinedButton.icon(
              onPressed: canOpenReceipt
                  ? () => _openReceipt(
                        context: context,
                        receiptUrl: form.receiptUrl,
                      )
                  : null,
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('צפה בקבלה'),
            ),
          ],
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.left,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _MetaText extends StatelessWidget {
  const _MetaText({
    required this.value,
  });

  final String value;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      textAlign: TextAlign.right,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
    );
  }
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
          _displayLabel,
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

  String get _displayLabel {
    if (step.label == 'הגשת הטפסים') {
      return 'הגשת הטופס';
    }
    return step.label;
  }
}

bool _hasOpenableReceiptTarget(String? receiptUrl) {
  if (receiptUrl == null || receiptUrl.isEmpty) {
    return false;
  }
  final Uri? uri = Uri.tryParse(receiptUrl);
  return uri != null && uri.hasScheme && (uri.host.isNotEmpty || uri.scheme == 'file');
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

String _formatAmount(num value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toStringAsFixed(1);
}

String _formWinningStatusLabel(PersonalSubmittedBundleForm form) {
  if (form.resultStatus == null && form.winAmount <= 0) {
    return 'ממתין לתוצאות';
  }
  return '${_formatAmount(form.winAmount)} ש״ח';
}
