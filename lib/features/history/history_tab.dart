import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/lottery_form.dart';
import '../../repositories/lottery_form_repository.dart';
import '../../repositories/lottery_group_repository.dart';
import '../../services/group_invite_link_service.dart';
import '../form_presentation_utils.dart';
import 'personal_form_details_page.dart';
import 'personal_submission_bundle_details_page.dart';
import '../lottery_form/group_details_page.dart';

class HistoryTab extends StatefulWidget {
  const HistoryTab({
    super.key,
    required this.userId,
    required this.repository,
    required this.groupRepository,
    required this.inviteLinkService,
    required this.onFormSelected,
    required this.onCancelGroupDraft,
  });

  final String userId;
  final LotteryFormRepository repository;
  final LotteryGroupRepository groupRepository;
  final GroupInviteLinkService inviteLinkService;
  final ValueChanged<LotteryForm> onFormSelected;
  final Future<bool> Function(String groupId) onCancelGroupDraft;

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  int? _expandedSectionIndex = 0;
  final Set<String> _hiddenDraftItemKeys = <String>{};
  int _draftDismissGeneration = 0;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LotteryForm>>(
      stream: widget.repository.watchSubmittedForms(widget.userId),
      builder: (context, submittedFormsSnapshot) {
        return StreamBuilder<List<PersonalSubmittedBundle>>(
          stream: widget.repository.watchPersonalSubmissionBundles(widget.userId),
          builder: (context, personalBundlesSnapshot) {
            return StreamBuilder<List<SubmittedGroupHistoryItem>>(
              stream:
                  widget.groupRepository.watchSubmittedGroupsForUser(widget.userId),
              builder: (context, submittedGroupsSnapshot) {
                return StreamBuilder<List<LotteryForm>>(
                  stream: widget.repository.watchSavedForms(widget.userId),
                  builder: (context, savedFormsSnapshot) {
                    return StreamBuilder<List<UserGroupListItem>>(
                      stream:
                          widget.groupRepository.watchGroupsForUser(widget.userId),
                      builder: (context, activeGroupsSnapshot) {
                        return StreamBuilder<List<CancelledGroupHistoryItem>>(
                          stream: widget.groupRepository
                              .watchCancelledGroupsForUser(widget.userId),
                          builder: (context, cancelledGroupsSnapshot) {
                        final List<SubmittedGroupHistoryItem> submittedGroups =
                            submittedGroupsSnapshot.data ??
                                const <SubmittedGroupHistoryItem>[];
                        final List<CancelledGroupHistoryItem> cancelledGroups =
                            cancelledGroupsSnapshot.data ??
                                const <CancelledGroupHistoryItem>[];
                        final Set<String> submittedGroupIds =
                            submittedGroups.map((item) => item.groupId).toSet();
                        final Set<String> cancelledGroupIds =
                            cancelledGroups.map((item) => item.groupId).toSet();

                        final List<_FormsListItem> submittedItems = [
                          ...(submittedFormsSnapshot.data ??
                                  const <LotteryForm>[])
                              .where(
                                (form) =>
                                    form.status == LotteryFormStatus.submitted,
                              )
                              .map(
                                (form) =>
                                    _FormsListItem.personalSubmitted(form),
                              ),
                          ...(personalBundlesSnapshot.data ??
                                  const <PersonalSubmittedBundle>[])
                              .map(
                                (bundle) =>
                                    _FormsListItem.personalSubmissionBundle(bundle),
                              ),
                          ...submittedGroups.map(
                            (item) => _FormsListItem.groupSubmitted(item),
                          ),
                        ]..sort(
                            (a, b) => b.sortDate.compareTo(a.sortDate),
                          );

                        final List<_FormsListItem> draftItems = [
                          ...(savedFormsSnapshot.data ?? const <LotteryForm>[])
                              .where(
                                (form) =>
                                    form.status == LotteryFormStatus.saved,
                              )
                              .map(
                                (form) => _FormsListItem.personalDraft(form),
                              ),
                          ...(activeGroupsSnapshot.data ??
                                  const <UserGroupListItem>[])
                              .where(
                                (item) =>
                                    item.groupStatus != 'submitted' &&
                                    item.groupStatus != 'cancelled' &&
                                    !submittedGroupIds.contains(item.groupId) &&
                                    !cancelledGroupIds.contains(item.groupId),
                              )
                              .map(
                                (item) => _FormsListItem.groupDraft(item),
                              ),
                        ]
                            .where(
                              (item) => !_hiddenDraftItemKeys
                                  .contains(item.stableKey),
                            )
                            .toList()
                          ..sort(
                            (a, b) => b.sortDate.compareTo(a.sortDate),
                          );

                        final List<_FormsListItem> cancelledItems = [
                          ...cancelledGroups.map(
                            (item) => _FormsListItem.groupCancelled(item),
                          ),
                        ]..sort(
                            (a, b) => b.sortDate.compareTo(a.sortDate),
                          );

                        return ListView(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                          children: [
                            _FormsSection(
                              viewerUserId: widget.userId,
                              title: 'טפסים שנשלחו / שולמו',
                              subtitle: 'טפסים אישיים וקבוצתיים שכבר הוגשו',
                              items: submittedItems,
                              emptyText: 'אין עדיין טפסים שנשלחו להצגה',
                              onItemTap: (item) =>
                                  _handleItemTap(context: context, item: item),
                              onCancelDraft: null,
                              dismissGeneration: 0,
                              isExpanded: _expandedSectionIndex == 0,
                              onToggle: () {
                                setState(() {
                                  _expandedSectionIndex =
                                      _expandedSectionIndex == 0 ? null : 0;
                                });
                              },
                            ),
                            const SizedBox(height: 16),
                            _FormsSection(
                              viewerUserId: widget.userId,
                              title: 'טיוטות',
                              subtitle: 'טפסים שמורים או קבוצות שעדיין בתהליך',
                              items: draftItems,
                              emptyText: 'אין כרגע טיוטות להצגה',
                              onItemTap: (item) =>
                                  _handleItemTap(context: context, item: item),
                              onCancelDraft: (item) async {
                                if (item.kind != _FormsItemKind.groupDraft ||
                                    item.groupId == null) {
                                  return false;
                                }

                                final bool confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (dialogContext) => AlertDialog(
                                        title: const Text('ביטול טופס קבוצתי'),
                                        content: const Text(
                                          'האם אתה בטוח? רק מי שכבר שילם על הטופס יזוכה בארנק שלו.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.of(
                                              dialogContext,
                                            ).pop(false),
                                            child: const Text('חזרה'),
                                          ),
                                          FilledButton(
                                            onPressed: () => Navigator.of(
                                              dialogContext,
                                            ).pop(true),
                                            child: const Text('אשר ביטול'),
                                          ),
                                        ],
                                      ),
                                    ) ??
                                    false;

                                if (!confirmed) {
                                  return false;
                                }

                                final bool cancelled = await widget
                                    .onCancelGroupDraft(item.groupId!);
                                if (cancelled && mounted) {
                                  setState(() {
                                    _hiddenDraftItemKeys.add(item.stableKey);
                                    _draftDismissGeneration++;
                                  });
                                }
                                return cancelled;
                              },
                              dismissGeneration: _draftDismissGeneration,
                              isExpanded: _expandedSectionIndex == 1,
                              onToggle: () {
                                setState(() {
                                  _expandedSectionIndex =
                                      _expandedSectionIndex == 1 ? null : 1;
                                });
                              },
                            ),
                            const SizedBox(height: 16),
                            _FormsSection(
                              viewerUserId: widget.userId,
                              title: 'טפסים שבוטלו',
                              subtitle:
                                  'טפסים קבוצתיים שבוטלו כולל זיכויים למי שכבר שילם',
                              items: cancelledItems,
                              emptyText: 'אין כרגע טפסים שבוטלו להצגה',
                              onItemTap: (item) =>
                                  _handleItemTap(context: context, item: item),
                              onCancelDraft: null,
                              dismissGeneration: 0,
                              isExpanded: _expandedSectionIndex == 2,
                              onToggle: () {
                                setState(() {
                                  _expandedSectionIndex =
                                      _expandedSectionIndex == 2 ? null : 2;
                                });
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
        if (item.personalForm?.formId != null) {
          String pageTitle = 'טופס אישי';
          if (item.kind == _FormsItemKind.personalDraft) {
            pageTitle = 'טיוטת טופס אישי';
          }
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PersonalFormDetailsPage(
                ownerUserId: widget.userId,
                formId: item.personalForm!.formId!,
                repository: widget.repository,
                title: pageTitle,
              ),
            ),
          );
        }
        return;
      case _FormsItemKind.personalSubmissionBundle:
        if (item.personalSubmissionBundle == null) {
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PersonalSubmissionBundleDetailsPage(
              ownerUserId: widget.userId,
              bundle: item.personalSubmissionBundle!,
              repository: widget.repository,
            ),
          ),
        );
        return;
      case _FormsItemKind.groupSubmitted:
      case _FormsItemKind.groupDraft:
      case _FormsItemKind.groupCancelled:
        if (item.groupId == null) {
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => GroupDetailsPage(
              groupId: item.groupId!,
              currentUserId: widget.userId,
              inviteLinkService: widget.inviteLinkService,
              repository: widget.groupRepository,
            ),
          ),
        );
    }
  }
}

enum _FormsItemKind {
  personalSubmitted,
  personalDraft,
  personalSubmissionBundle,
  groupSubmitted,
  groupDraft,
  groupCancelled,
}

class _FormsListItem {
  const _FormsListItem._({
    required this.kind,
    required this.sortDate,
    this.personalForm,
    this.personalSubmissionBundle,
    this.submittedGroup,
    this.activeGroup,
    this.cancelledGroup,
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

  factory _FormsListItem.personalSubmissionBundle(
    PersonalSubmittedBundle bundle,
  ) {
    return _FormsListItem._(
      kind: _FormsItemKind.personalSubmissionBundle,
      sortDate: bundle.submittedAt ?? DateTime(0),
      personalSubmissionBundle: bundle,
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

  factory _FormsListItem.groupCancelled(CancelledGroupHistoryItem item) {
    return _FormsListItem._(
      kind: _FormsItemKind.groupCancelled,
      sortDate: item.cancelledAt ?? DateTime(0),
      cancelledGroup: item,
    );
  }

  final _FormsItemKind kind;
  final DateTime sortDate;
  final LotteryForm? personalForm;
  final PersonalSubmittedBundle? personalSubmissionBundle;
  final SubmittedGroupHistoryItem? submittedGroup;
  final UserGroupListItem? activeGroup;
  final CancelledGroupHistoryItem? cancelledGroup;

  String? get groupId =>
      submittedGroup?.groupId ??
      activeGroup?.groupId ??
      cancelledGroup?.groupId;

  String get stableKey {
    switch (kind) {
      case _FormsItemKind.personalSubmitted:
      case _FormsItemKind.personalDraft:
        return 'personal-${personalForm?.formId ?? sortDate.toIso8601String()}';
      case _FormsItemKind.personalSubmissionBundle:
        return 'personal-bundle-${personalSubmissionBundle?.submissionId ?? sortDate.toIso8601String()}';
      case _FormsItemKind.groupSubmitted:
        return 'group-submitted-${submittedGroup?.groupId ?? sortDate.toIso8601String()}';
      case _FormsItemKind.groupDraft:
        return 'group-draft-${activeGroup?.groupId ?? sortDate.toIso8601String()}';
      case _FormsItemKind.groupCancelled:
        return 'group-cancelled-${cancelledGroup?.groupId ?? sortDate.toIso8601String()}';
    }
  }
}

class _FormsSection extends StatelessWidget {
  const _FormsSection({
    required this.viewerUserId,
    required this.title,
    required this.subtitle,
    required this.items,
    required this.emptyText,
    required this.onItemTap,
    required this.onCancelDraft,
    required this.dismissGeneration,
    required this.isExpanded,
    required this.onToggle,
  });

  final String viewerUserId;
  final String title;
  final String subtitle;
  final List<_FormsListItem> items;
  final String emptyText;
  final ValueChanged<_FormsListItem> onItemTap;
  final Future<bool> Function(_FormsListItem item)? onCancelDraft;
  final int dismissGeneration;
  final bool isExpanded;
  final VoidCallback onToggle;

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
          const SizedBox(height: 6),
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: const Icon(Icons.expand_more_rounded),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      subtitle,
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        emptyText,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : Column(
                      children: items
                          .map(
                            (item) => Padding(
                              key: ValueKey<String>(item.stableKey),
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _FormsSummaryTile(
                                viewerUserId: viewerUserId,
                                item: item,
                                dismissGeneration: dismissGeneration,
                                onTap: () => onItemTap(item),
                                onDelete: onCancelDraft == null
                                    ? null
                                    : () => onCancelDraft!(item),
                              ),
                            ),
                          )
                          .toList(),
                    ),
            ),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
            sizeCurve: Curves.easeInOut,
          ),
        ],
      ),
    );
  }
}

class _FormsSummaryTile extends StatefulWidget {
  const _FormsSummaryTile({
    required this.viewerUserId,
    required this.item,
    required this.dismissGeneration,
    required this.onTap,
    required this.onDelete,
  });

  final String viewerUserId;
  final _FormsListItem item;
  final int dismissGeneration;
  final VoidCallback onTap;
  final Future<bool> Function()? onDelete;

  @override
  State<_FormsSummaryTile> createState() => _FormsSummaryTileState();
}

class _FormsSummaryTileState extends State<_FormsSummaryTile> {
  bool _isCollapsed = false;

  @override
  void didUpdateWidget(covariant _FormsSummaryTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dismissGeneration != widget.dismissGeneration &&
        _isCollapsed) {
      _isCollapsed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCollapsed) {
      return AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        child: const SizedBox.shrink(),
      );
    }

    final Widget tile = Material(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(16),
      child: ListTile(
        onTap: widget.onTap,
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
          child: _buildSubtitle(),
        ),
        trailing: const Icon(Icons.chevron_left),
      ),
    );

    final bool dismissibleGroupDraft =
        widget.item.kind == _FormsItemKind.groupDraft &&
            widget.item.groupId != null &&
            widget.item.activeGroup?.creatorUserId == widget.viewerUserId;

    if (widget.onDelete == null || !dismissibleGroupDraft) {
      return tile;
    }

    return Dismissible(
      key: ValueKey<String>(
        'draft-group-${widget.item.groupId}-${widget.dismissGeneration}',
      ),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          Icons.cancel_outlined,
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          Icons.cancel_outlined,
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
      ),
      confirmDismiss: (_) async {
        final bool cancelled = await widget.onDelete!();
        if (cancelled && mounted) {
          setState(() => _isCollapsed = true);
        }
        return false;
      },
      child: tile,
    );
  }

  Widget _buildSubtitle() {
    if (widget.item.kind == _FormsItemKind.groupSubmitted ||
        widget.item.kind == _FormsItemKind.groupDraft ||
        widget.item.kind == _FormsItemKind.groupCancelled) {
      return _GroupSummaryDetails(
        item: widget.item,
        viewerUserId: widget.viewerUserId,
      );
    }

    return Text(
      _subtitleText(),
      textAlign: TextAlign.right,
    );
  }

  String _titleText() {
    switch (widget.item.kind) {
      case _FormsItemKind.personalSubmitted:
      case _FormsItemKind.personalDraft:
        return 'טופס אישי';
      case _FormsItemKind.personalSubmissionBundle:
        return 'שליחת טפסים אישיים';
      case _FormsItemKind.groupSubmitted:
        return widget.item.submittedGroup!.groupName;
      case _FormsItemKind.groupDraft:
        return widget.item.activeGroup!.groupName;
      case _FormsItemKind.groupCancelled:
        return widget.item.cancelledGroup!.groupName;
    }
  }

  String _subtitleText() {
    switch (widget.item.kind) {
      case _FormsItemKind.personalSubmitted:
        final LotteryForm form = widget.item.personalForm!;
        final List<String> lines = [
          'סטטוס: ${_personalStatusLabel(form)}',
          'עלות טופס: ${_ticketCost(form)} ש״ח',
          'זכייה: ${_personalWinningStatusLabel(form)}',
          'תאריך הגרלה: ${_formatDate(form.salesCloseAt ?? form.submittedAt)}',
          'נשלח: ${_formatDate(form.submittedAt ?? form.updatedAt)}',
        ];
        return lines.join('\n');
      case _FormsItemKind.personalDraft:
        final LotteryForm form = widget.item.personalForm!;
        return [
          'סטטוס: טיוטה',
          'עלות טופס: ${_ticketCost(form)} ש״ח',
          'זכייה: ממתין לתוצאות',
          'נוצר: ${_formatDate(form.createdAt ?? form.savedAt ?? form.updatedAt)}',
        ].join('\n');
      case _FormsItemKind.personalSubmissionBundle:
        final PersonalSubmittedBundle bundle = widget.item.personalSubmissionBundle!;
        return [
          'סטטוס: נשלחו כמה טפסים אישיים',
          'מספר טפסים: ${bundle.formCount}',
          'סה״כ טבלאות: ${bundle.totalTableCount}',
          'עלות כוללת: ${bundle.totalCost} ש״ח',
          'זכייה: ${_bundleWinningStatusLabel(bundle)}',
          'נשלח: ${_formatDate(bundle.submittedAt)}',
        ].join('\n');
      case _FormsItemKind.groupSubmitted:
        final SubmittedGroupHistoryItem group = widget.item.submittedGroup!;
        return [
          'נוצר על ידי: ${group.creatorName}',
          'סטטוס: ${_groupStatusLabel(group.groupStatus)}',
          'העלות שלי: ${group.myEffectiveShare} ש״ח',
        ].join('\n');
      case _FormsItemKind.groupDraft:
        final UserGroupListItem group = widget.item.activeGroup!;
        return [
          'נוצר על ידי: ${group.creatorName ?? group.creatorUserId}',
          'סטטוס: ${_groupStatusLabel(group.groupStatus)}',
          'עלות שלי: ${_draftGroupCostLabel(group)}',
          'מצב תגובה: ${_responseStatusLabel(group.responseStatus)}',
        ].join('\n');
      case _FormsItemKind.groupCancelled:
        final CancelledGroupHistoryItem group = widget.item.cancelledGroup!;
        return [
          'נוצר על ידי: ${group.creatorName}',
          'סטטוס: בוטל',
          'בוטל על ידי: ${group.cancelledByDisplayName}',
          'מועד ביטול: ${_formatDate(group.cancelledAt)}',
          'זיכוי לארנק: ${group.myRefundAmount} ש״ח',
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

  String _personalWinningStatusLabel(LotteryForm form) {
    if (form.resultStatus == null && form.winAmount <= 0) {
      return 'ממתין לתוצאות';
    }
    return '${form.winAmount} ש״ח';
  }

  String _bundleWinningStatusLabel(PersonalSubmittedBundle bundle) {
    if (bundle.forms.isEmpty) {
      return 'ממתין לתוצאות';
    }

    final bool hasAnyResolvedResult = bundle.forms.any(
      (form) => form.resultStatus != null || form.winAmount > 0,
    );
    if (!hasAnyResolvedResult) {
      return 'ממתין לתוצאות';
    }

    final num totalWinAmount = bundle.forms.fold<num>(
      0,
      (num total, PersonalSubmittedBundleForm form) => total + form.winAmount,
    );
    return '$totalWinAmount ש״ח';
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
    return formatPresentationDateTime(date);
  }
}

class _GroupSummaryDetails extends StatelessWidget {
  const _GroupSummaryDetails({
    required this.item,
    required this.viewerUserId,
  });

  final _FormsListItem item;
  final String viewerUserId;

  @override
  Widget build(BuildContext context) {
    final String? groupId = item.groupId;
    if (groupId == null) {
      return Text(
        _fallbackText(),
        textAlign: TextAlign.right,
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('lottery_groups')
          .doc(groupId)
          .snapshots(),
      builder: (context, groupSnapshot) {
        final Map<String, dynamic> groupData =
            groupSnapshot.data?.data() ?? const <String, dynamic>{};
        final DateTime? createdAt =
            presentationAsDateTime(groupData['createdAt']);
        final DateTime? submittedAt =
            presentationAsDateTime(groupData['submittedAt']);
        final String? creatorUserId = groupData['creatorUserId'] as String?;
        final String? submittedFormId = groupData['submittedFormId'] as String?;
        final String? sourceFormId = groupData['sourceFormId'] as String?;

        if (item.kind == _FormsItemKind.groupSubmitted &&
            creatorUserId != null &&
            creatorUserId.isNotEmpty &&
            submittedFormId != null &&
            submittedFormId.isNotEmpty) {
          return Text(
            _submittedText(
              submittedAt: submittedAt,
            ),
            textAlign: TextAlign.right,
          );
        }

        if (item.kind == _FormsItemKind.groupDraft &&
            creatorUserId != null &&
            creatorUserId.isNotEmpty &&
            sourceFormId != null &&
            sourceFormId.isNotEmpty) {
          return Text(
            _draftText(
              createdAt: createdAt,
            ),
            textAlign: TextAlign.right,
          );
        }

        if (item.kind == _FormsItemKind.groupCancelled) {
          return Text(
            _cancelledText(),
            textAlign: TextAlign.right,
          );
        }

        return Text(
          _draftText(createdAt: createdAt),
          textAlign: TextAlign.right,
        );
      },
    );
  }

  String _submittedText({
    required DateTime? submittedAt,
  }) {
    final SubmittedGroupHistoryItem group = item.submittedGroup!;

    final List<String> lines = <String>[
      'נוצר על ידי: ${group.creatorName}',
      'סטטוס: ${_submittedStatusLabel(group.dispatchStatus)}',
      'מס׳ הגרלה: —',
      'העלות שלי: ${group.myEffectiveShare} ש״ח',
      'נשלח: ${formatPresentationDateTime(submittedAt ?? group.submittedAt)}',
      'הזכייה שלי: טרם פורסם',
    ];
    return lines.join('\n');
  }

  String _draftText({
    required DateTime? createdAt,
  }) {
    if (item.kind == _FormsItemKind.groupDraft) {
      final UserGroupListItem group = item.activeGroup!;
      return [
        'נוצר על ידי: ${group.creatorName ?? group.creatorUserId}',
        'סטטוס: ${_groupStatusLabel(group.groupStatus)}',
        'מס׳ הגרלה: —',
        'עלות שלי: ${_draftGroupCostLabel(group)}',
        'נוצר: ${formatPresentationDateTime(createdAt ?? group.updatedAt)}',
        'מצב תגובה: ${_responseStatusLabel(group.responseStatus)}',
      ].join('\n');
    }

    return _fallbackText();
  }

  String _cancelledText() {
    final CancelledGroupHistoryItem group = item.cancelledGroup!;
    return [
      'נוצר על ידי: ${group.creatorName}',
      'סטטוס: בוטל',
      'בוטל על ידי: ${group.cancelledByDisplayName}',
      'מועד ביטול: ${formatPresentationDateTime(group.cancelledAt)}',
      'זיכוי לארנק: ${group.myRefundAmount} ש״ח',
    ].join('\n');
  }

  String _submittedStatusLabel(String rawDispatchStatus) {
    switch (rawDispatchStatus) {
      case LotteryGroupRepository.dispatchStatusSubmittedToStation:
        return 'נמסר לתחנה';
      case LotteryGroupRepository.dispatchStatusPrinted:
        return 'הודפס';
      case LotteryGroupRepository.dispatchStatusQueuedForPrint:
      default:
        return 'ממתין להדפסה';
    }
  }

  String _fallbackText() {
    if (item.kind == _FormsItemKind.groupSubmitted) {
      final SubmittedGroupHistoryItem group = item.submittedGroup!;
      return [
        'נוצר על ידי: ${group.creatorName}',
        'סטטוס: ${_groupStatusLabel(group.groupStatus)}',
        'מס׳ הגרלה: —',
        'העלות שלי: ${group.myEffectiveShare} ש״ח',
        'נשלח: ${formatPresentationDateTime(group.submittedAt)}',
        'הזכייה שלי: טרם פורסם',
      ].join('\n');
    }

    if (item.kind == _FormsItemKind.groupCancelled) {
      return _cancelledText();
    }

    final UserGroupListItem group = item.activeGroup!;
    return [
      'נוצר על ידי: ${group.creatorName ?? group.creatorUserId}',
      'סטטוס: ${_groupStatusLabel(group.groupStatus)}',
      'מס׳ הגרלה: —',
      'עלות שלי: ${_draftGroupCostLabel(group)}',
      'נוצר: ${formatPresentationDateTime(group.updatedAt)}',
      'מצב תגובה: ${_responseStatusLabel(group.responseStatus)}',
    ].join('\n');
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
      case 'not_interested':
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
}
