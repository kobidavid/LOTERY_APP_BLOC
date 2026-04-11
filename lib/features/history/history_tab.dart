import 'package:flutter/material.dart';

import '../../models/lottery_form.dart';
import '../../repositories/lottery_form_repository.dart';
import '../../repositories/lottery_group_repository.dart';
import '../../services/group_invite_link_service.dart';
import '../lottery_form/group_details_page.dart';

class HistoryTab extends StatelessWidget {
  const HistoryTab({
    super.key,
    required this.userId,
    required this.repository,
    required this.groupRepository,
    required this.inviteLinkService,
    required this.onFormSelected,
    required this.onDeleteSavedForm,
  });

  final String userId;
  final LotteryFormRepository repository;
  final LotteryGroupRepository groupRepository;
  final GroupInviteLinkService inviteLinkService;
  final ValueChanged<LotteryForm> onFormSelected;
  final Future<bool> Function(LotteryForm) onDeleteSavedForm;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LotteryForm>>(
      stream: repository.watchSubmittedForms(userId),
      builder: (context, submittedFormsSnapshot) {
        return StreamBuilder<List<SubmittedGroupHistoryItem>>(
          stream: groupRepository.watchSubmittedGroupsForUser(userId),
          builder: (context, submittedGroupsSnapshot) {
            return StreamBuilder<List<LotteryForm>>(
              stream: repository.watchSavedForms(userId),
              builder: (context, savedFormsSnapshot) {
                return StreamBuilder<List<UserGroupListItem>>(
                  stream: groupRepository.watchGroupsForUser(userId),
                  builder: (context, activeGroupsSnapshot) {
                    final List<_FormsListItem> submittedItems = [
                      ...(submittedFormsSnapshot.data ?? const <LotteryForm>[])
                          .map(
                        (form) => _FormsListItem.personalSubmitted(form),
                      ),
                      ...(submittedGroupsSnapshot.data ??
                              const <SubmittedGroupHistoryItem>[])
                          .map(
                        (item) => _FormsListItem.groupSubmitted(item),
                      ),
                    ]..sort(
                        (a, b) => b.sortDate.compareTo(a.sortDate),
                      );

                    final List<_FormsListItem> draftItems = [
                      ...(savedFormsSnapshot.data ?? const <LotteryForm>[]).map(
                        (form) => _FormsListItem.personalDraft(form),
                      ),
                      ...(activeGroupsSnapshot.data ??
                              const <UserGroupListItem>[])
                          .map(
                        (item) => _FormsListItem.groupDraft(item),
                      ),
                    ]..sort(
                        (a, b) => b.sortDate.compareTo(a.sortDate),
                      );

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      children: [
                        _FormsSection(
                          title: 'טפסים שנשלחו / שולמו',
                          subtitle: 'טפסים אישיים וקבוצתיים שכבר הוגשו',
                          items: submittedItems,
                          emptyText: 'אין עדיין טפסים שנשלחו להצגה',
                          onItemTap: (item) =>
                              _handleItemTap(context: context, item: item),
                          onDeleteDraft: null,
                        ),
                        const SizedBox(height: 16),
                        _FormsSection(
                          title: 'טיוטות',
                          subtitle: 'טפסים שמורים או קבוצות שעדיין בתהליך',
                          items: draftItems,
                          emptyText: 'אין כרגע טיוטות להצגה',
                          onItemTap: (item) =>
                              _handleItemTap(context: context, item: item),
                          onDeleteDraft: (item) {
                            if (item.personalForm == null ||
                                item.kind != _FormsItemKind.personalDraft) {
                              return Future<bool>.value(false);
                            }
                            return onDeleteSavedForm(item.personalForm!);
                          },
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  void _handleItemTap({
    required BuildContext context,
    required _FormsListItem item,
  }) {
    switch (item.kind) {
      case _FormsItemKind.personalSubmitted:
      case _FormsItemKind.personalDraft:
        if (item.personalForm != null) {
          onFormSelected(item.personalForm!);
        }
        return;
      case _FormsItemKind.groupSubmitted:
      case _FormsItemKind.groupDraft:
        if (item.groupId == null) {
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => GroupDetailsPage(
              groupId: item.groupId!,
              currentUserId: userId,
              inviteLinkService: inviteLinkService,
              repository: groupRepository,
            ),
          ),
        );
    }
  }
}

enum _FormsItemKind {
  personalSubmitted,
  personalDraft,
  groupSubmitted,
  groupDraft,
}

class _FormsListItem {
  const _FormsListItem._({
    required this.kind,
    required this.sortDate,
    this.personalForm,
    this.submittedGroup,
    this.activeGroup,
  });

  factory _FormsListItem.personalSubmitted(LotteryForm form) {
    return _FormsListItem._(
      kind: _FormsItemKind.personalSubmitted,
      sortDate: form.submittedAt ?? form.updatedAt ?? DateTime(0),
      personalForm: form,
    );
  }

  factory _FormsListItem.personalDraft(LotteryForm form) {
    return _FormsListItem._(
      kind: _FormsItemKind.personalDraft,
      sortDate: form.savedAt ?? form.updatedAt ?? DateTime(0),
      personalForm: form,
    );
  }

  factory _FormsListItem.groupSubmitted(SubmittedGroupHistoryItem item) {
    return _FormsListItem._(
      kind: _FormsItemKind.groupSubmitted,
      sortDate: item.submittedAt ?? DateTime(0),
      submittedGroup: item,
    );
  }

  factory _FormsListItem.groupDraft(UserGroupListItem item) {
    return _FormsListItem._(
      kind: _FormsItemKind.groupDraft,
      sortDate: item.updatedAt ?? DateTime(0),
      activeGroup: item,
    );
  }

  final _FormsItemKind kind;
  final DateTime sortDate;
  final LotteryForm? personalForm;
  final SubmittedGroupHistoryItem? submittedGroup;
  final UserGroupListItem? activeGroup;

  String? get groupId => submittedGroup?.groupId ?? activeGroup?.groupId;
}

class _FormsSection extends StatelessWidget {
  const _FormsSection({
    required this.title,
    required this.subtitle,
    required this.items,
    required this.emptyText,
    required this.onItemTap,
    required this.onDeleteDraft,
  });

  final String title;
  final String subtitle;
  final List<_FormsListItem> items;
  final String emptyText;
  final ValueChanged<_FormsListItem> onItemTap;
  final Future<bool> Function(_FormsListItem item)? onDeleteDraft;

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
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                emptyText,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          else
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _FormsSummaryTile(
                  item: item,
                  onTap: () => onItemTap(item),
                  onDelete:
                      onDeleteDraft == null ? null : () => onDeleteDraft!(item),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FormsSummaryTile extends StatelessWidget {
  const _FormsSummaryTile({
    required this.item,
    required this.onTap,
    required this.onDelete,
  });

  final _FormsListItem item;
  final VoidCallback onTap;
  final Future<bool> Function()? onDelete;

  @override
  Widget build(BuildContext context) {
    final Widget tile = Material(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(16),
      child: ListTile(
        onTap: onTap,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          _titleText(),
          textAlign: TextAlign.right,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            _subtitleText(),
            textAlign: TextAlign.right,
          ),
        ),
        trailing: const Icon(Icons.chevron_left),
      ),
    );

    if (onDelete == null ||
        item.kind != _FormsItemKind.personalDraft ||
        item.personalForm?.formId == null) {
      return tile;
    }

    return Dismissible(
      key: ValueKey<String>('draft-form-${item.personalForm!.formId}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => onDelete!(),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          Icons.delete_outline,
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
      ),
      child: tile,
    );
  }

  String _titleText() {
    switch (item.kind) {
      case _FormsItemKind.personalSubmitted:
      case _FormsItemKind.personalDraft:
        return 'טופס אישי';
      case _FormsItemKind.groupSubmitted:
        return item.submittedGroup!.groupName;
      case _FormsItemKind.groupDraft:
        return item.activeGroup!.groupName;
    }
  }

  String _subtitleText() {
    switch (item.kind) {
      case _FormsItemKind.personalSubmitted:
        final LotteryForm form = item.personalForm!;
        final List<String> lines = [
          'סטטוס: ${_personalStatusLabel(form)}',
          'עלות טופס: ${_ticketCost(form)} ש״ח',
          'תאריך הגרלה: ${_formatDate(form.salesCloseAt ?? form.submittedAt)}',
        ];
        if (form.resultStatus != null || form.winAmount > 0) {
          lines.add('זכייה: ${form.winAmount} ש״ח');
        }
        return lines.join('\n');
      case _FormsItemKind.personalDraft:
        final LotteryForm form = item.personalForm!;
        return [
          'סטטוס: טיוטה',
          'עלות טופס: ${_ticketCost(form)} ש״ח',
          'עודכן: ${_formatDate(form.savedAt ?? form.updatedAt)}',
        ].join('\n');
      case _FormsItemKind.groupSubmitted:
        final SubmittedGroupHistoryItem group = item.submittedGroup!;
        return [
          'נוצר על ידי: ${group.creatorName}',
          'סטטוס: ${_groupStatusLabel(group.groupStatus)}',
          'העלות שלי: ${group.myEffectiveShare} ש״ח',
        ].join('\n');
      case _FormsItemKind.groupDraft:
        final UserGroupListItem group = item.activeGroup!;
        return [
          'נוצר על ידי: ${group.creatorUserId}',
          'סטטוס: ${_groupStatusLabel(group.groupStatus)}',
          'עלות שלי: ${_draftGroupCostLabel(group)}',
          'מצב תגובה: ${_responseStatusLabel(group.responseStatus)}',
        ].join('\n');
    }
  }

  String _personalStatusLabel(LotteryForm form) {
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

  String _groupStatusLabel(String rawStatus) {
    switch (rawStatus) {
      case 'submitted':
        return 'נשלח';
      case 'ready_for_submission':
        return 'מוכן לשליחה';
      case 'awaiting_payments':
        return 'ממתין לתשלומים';
      case 'collecting_responses':
        return 'איסוף משתתפים';
      case 'cancelled':
        return 'בוטל';
      default:
        return rawStatus.isEmpty ? 'בטיפול' : rawStatus;
    }
  }

  String _responseStatusLabel(String rawStatus) {
    switch (rawStatus) {
      case 'interested':
        return 'מעוניין';
      case 'undecided':
        return 'טרם הוחלט';
      case 'declined':
        return 'לא מצטרף';
      default:
        return rawStatus.isEmpty ? 'לא עודכן' : rawStatus;
    }
  }

  String _draftGroupCostLabel(UserGroupListItem group) {
    if (group.lockedIn && group.paymentStatus == 'paid') {
      return 'שולם';
    }
    if (group.lockedIn && group.paymentStatus == 'unpaid') {
      return 'ממתין לתשלום';
    }
    return 'ייקבע בהמשך';
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

  String _formatDate(DateTime? date) {
    if (date == null) {
      return 'ללא תאריך';
    }

    String twoDigits(int value) => value.toString().padLeft(2, '0');

    return '${twoDigits(date.day)}/${twoDigits(date.month)}/${date.year} '
        '${twoDigits(date.hour)}:${twoDigits(date.minute)}';
  }
}
