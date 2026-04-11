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
              final String winningsLabel =
                  form.resultStatus != null || form.winAmount > 0
                      ? '${form.winAmount} ש״ח'
                      : 'טרם פורסם';
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
              final bool hasReceipt = receiptUrl != null;

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
                    footer: hasReceipt
                        ? Align(
                            alignment: Alignment.centerRight,
                            child: OutlinedButton.icon(
                              onPressed: () => _openReceipt(
                                context: context,
                                receiptUrl: receiptUrl,
                              ),
                              icon: const Icon(Icons.receipt_long_outlined),
                              label: const Text('פתח קבלה'),
                            ),
                          )
                        : null,
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

  String _formatDate(DateTime? date) {
    return formatPresentationDateTime(date);
  }

  Future<void> _openReceipt({
    required BuildContext context,
    required String? receiptUrl,
  }) async {
    if (receiptUrl == null || receiptUrl.isEmpty) {
      return;
    }

    final Uri uri = Uri.parse(receiptUrl);
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
        children: [
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
          const SizedBox(width: 12),
          Text(
            '$label:',
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      ),
    );
  }
}
