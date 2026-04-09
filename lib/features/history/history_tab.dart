import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/lottery_form.dart';
import '../../repositories/lottery_form_repository.dart';
import '../../repositories/lottery_group_repository.dart';
import '../../services/group_invite_link_service.dart';
import '../lottery_form/group_details_page.dart';
import 'history_cubit.dart';

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
    return BlocBuilder<HistoryCubit, HistorySection?>(
      builder: (context, expandedSection) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _HistorySectionCard(
              title: 'רשימת טפסים קבוצתיים שנשלחו',
              isExpanded: expandedSection == HistorySection.groupSubmitted,
              onTap: () => context
                  .read<HistoryCubit>()
                  .toggle(HistorySection.groupSubmitted),
              child: StreamBuilder<List<SubmittedGroupHistoryItem>>(
                stream: groupRepository.watchSubmittedGroupsForUser(userId),
                builder: (context, snapshot) {
                  return _SubmittedGroupsList(
                    items: snapshot.data ?? const <SubmittedGroupHistoryItem>[],
                    emptyText: 'אין טפסים קבוצתיים שנשלחו עדיין',
                    onOpen: (item) {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => GroupDetailsPage(
                            groupId: item.groupId,
                            currentUserId: userId,
                            inviteLinkService: inviteLinkService,
                            repository: groupRepository,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            _HistorySectionCard(
              title: 'רשימת טפסים שהלקוח שלח',
              isExpanded: expandedSection == HistorySection.submitted,
              onTap: () =>
                  context.read<HistoryCubit>().toggle(HistorySection.submitted),
              child: StreamBuilder<List<LotteryForm>>(
                stream: repository.watchSubmittedForms(userId),
                builder: (context, snapshot) {
                  return _HistoryFormsList(
                    forms: snapshot.data ?? const <LotteryForm>[],
                    emptyText: 'אין טפסים שנשלחו עדיין',
                    onFormSelected: onFormSelected,
                    onDelete: null,
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            _HistorySectionCard(
              title: 'רשימת הטפסים שהלקוח שמר',
              isExpanded: expandedSection == HistorySection.saved,
              onTap: () =>
                  context.read<HistoryCubit>().toggle(HistorySection.saved),
              child: StreamBuilder<List<LotteryForm>>(
                stream: repository.watchSavedForms(userId),
                builder: (context, snapshot) {
                  return _HistoryFormsList(
                    forms: snapshot.data ?? const <LotteryForm>[],
                    emptyText: 'אין טפסים שמורים',
                    onFormSelected: onFormSelected,
                    onDelete: onDeleteSavedForm,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SubmittedGroupsList extends StatelessWidget {
  const _SubmittedGroupsList({
    required this.items,
    required this.emptyText,
    required this.onOpen,
  });

  final List<SubmittedGroupHistoryItem> items;
  final String emptyText;
  final ValueChanged<SubmittedGroupHistoryItem> onOpen;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          emptyText,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return Column(
      children: items
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
                child: ListTile(
                  onTap: () => onOpen(item),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  title: Text(
                    item.groupName,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    'נוצר על ידי: ${item.creatorName}\n'
                    'סטטוס עסקי: ${item.groupStatus}\n'
                    'מצב שליחה: ${_dispatchStatusLabel(item.dispatchStatus)}\n'
                    'נשלח: ${_formatDate(item.submittedAt)}\n'
                    'החלק שלי: ${item.myEffectiveShare} ש״ח',
                    textAlign: TextAlign.right,
                  ),
                  trailing: const Icon(Icons.chevron_left),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) {
      return 'ללא תאריך';
    }

    String twoDigits(int value) => value.toString().padLeft(2, '0');

    return '${twoDigits(date.day)}/${twoDigits(date.month)}/${date.year} '
        '${twoDigits(date.hour)}:${twoDigits(date.minute)}';
  }

  String _dispatchStatusLabel(String dispatchStatus) {
    switch (dispatchStatus) {
      case LotteryGroupRepository.dispatchStatusPrinted:
        return 'הודפס';
      case LotteryGroupRepository.dispatchStatusSubmittedToStation:
        return 'נמסר לתחנה';
      case LotteryGroupRepository.dispatchStatusQueuedForPrint:
      default:
        return 'ממתין להדפסה';
    }
  }
}

class _HistorySectionCard extends StatelessWidget {
  const _HistorySectionCard({
    required this.title,
    required this.isExpanded,
    required this.onTap,
    required this.child,
  });

  final String title;
  final bool isExpanded;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
        ),
        child: ExpansionTile(
          key: PageStorageKey<String>(title),
          initiallyExpanded: isExpanded,
          onExpansionChanged: (_) => onTap(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            title,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          children: [child],
        ),
      ),
    );
  }
}

class _HistoryFormsList extends StatelessWidget {
  const _HistoryFormsList({
    required this.forms,
    required this.emptyText,
    required this.onFormSelected,
    required this.onDelete,
  });

  final List<LotteryForm> forms;
  final String emptyText;
  final ValueChanged<LotteryForm> onFormSelected;
  final Future<bool> Function(LotteryForm)? onDelete;

  @override
  Widget build(BuildContext context) {
    if (forms.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          emptyText,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return Column(
      children: forms
          .map(
            (form) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _HistoryFormTile(
                form: form,
                onTap: () => onFormSelected(form),
                onDelete: onDelete == null ? null : () => onDelete!(form),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _HistoryFormTile extends StatelessWidget {
  const _HistoryFormTile({
    required this.form,
    required this.onTap,
    required this.onDelete,
  });

  final LotteryForm form;
  final VoidCallback onTap;
  final Future<bool> Function()? onDelete;

  @override
  Widget build(BuildContext context) {
    final DateTime? date = form.status == LotteryFormStatus.submitted
        ? form.submittedAt
        : form.savedAt ?? form.updatedAt;

    final Widget tile = Material(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(14),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        title: Text(
          _formatDate(date),
          textAlign: TextAlign.right,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          form.status == LotteryFormStatus.submitted ? 'נשלח' : 'נשמר',
          textAlign: TextAlign.right,
        ),
        trailing: const Icon(Icons.chevron_left),
      ),
    );

    if (onDelete == null || form.formId == null) {
      return tile;
    }

    return Dismissible(
      key: ValueKey<String>('saved-form-${form.formId}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => onDelete!.call(),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          Icons.delete_outline,
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
      ),
      child: tile,
    );
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
