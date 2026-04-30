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

class _HistoryTabState extends State<HistoryTab>
    with SingleTickerProviderStateMixin {
  final Set<String> _hiddenDraftItemKeys = <String>{};
  int _draftDismissGeneration = 0;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LotteryForm>>(
      stream: widget.repository.watchSubmittedForms(widget.userId),
      builder: (context, submittedFormsSnapshot) {
        return StreamBuilder<List<PersonalSubmittedBundle>>(
          stream:
              widget.repository.watchPersonalSubmissionBundles(widget.userId),
          builder: (context, personalBundlesSnapshot) {
            return StreamBuilder<List<SubmittedGroupHistoryItem>>(
              stream: widget.groupRepository
                  .watchSubmittedGroupsForUser(widget.userId),
              builder: (context, submittedGroupsSnapshot) {
                return StreamBuilder<List<LotteryForm>>(
                  stream: widget.repository.watchSavedForms(widget.userId),
                  builder: (context, savedFormsSnapshot) {
                    return StreamBuilder<List<UserGroupListItem>>(
                      stream: widget.groupRepository
                          .watchGroupsForUser(widget.userId),
                      builder: (context, activeGroupsSnapshot) {
                        return StreamBuilder<List<CancelledGroupHistoryItem>>(
                          stream: widget.groupRepository
                              .watchCancelledGroupsForUser(widget.userId),
                          builder: (context, cancelledGroupsSnapshot) {
                            final List<SubmittedGroupHistoryItem>
                                submittedGroups =
                                submittedGroupsSnapshot.data ??
                                    const <SubmittedGroupHistoryItem>[];
                            final List<CancelledGroupHistoryItem>
                                cancelledGroups =
                                cancelledGroupsSnapshot.data ??
                                    const <CancelledGroupHistoryItem>[];
                            final Set<String> submittedGroupIds =
                                submittedGroups
                                    .map((item) => item.groupId)
                                    .toSet();
                            final Set<String> cancelledGroupIds =
                                cancelledGroups
                                    .map((item) => item.groupId)
                                    .toSet();

                            final List<_FormsListItem> submittedItems = [
                              ..._buildPersonalSubmittedItems(
                                submittedForms: submittedFormsSnapshot.data ??
                                    const <LotteryForm>[],
                                personalBundles: personalBundlesSnapshot.data ??
                                    const <PersonalSubmittedBundle>[],
                              ),
                              ...submittedGroups.map(
                                (item) => _FormsListItem.groupSubmitted(item),
                              ),
                            ]..sort(
                                (a, b) => b.sortDate.compareTo(a.sortDate),
                              );

                            final List<_FormsListItem> draftItems = [
                              ...(savedFormsSnapshot.data ??
                                      const <LotteryForm>[])
                                  .where(
                                    (form) =>
                                        form.status == LotteryFormStatus.saved,
                                  )
                                  .map(
                                    (form) =>
                                        _FormsListItem.personalDraft(form),
                                  ),
                              ...(activeGroupsSnapshot.data ??
                                      const <UserGroupListItem>[])
                                  .where(
                                    (item) =>
                                        item.groupStatus != 'submitted' &&
                                        item.groupStatus != 'cancelled' &&
                                        !submittedGroupIds
                                            .contains(item.groupId) &&
                                        !cancelledGroupIds
                                            .contains(item.groupId),
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

                            return Directionality(
                              textDirection: TextDirection.rtl,
                              child: Column(
                                children: [
                                  Material(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    child: TabBar(
                                      controller: _tabController,
                                      indicatorSize: TabBarIndicatorSize.tab,
                                      dividerColor: Theme.of(context)
                                          .colorScheme
                                          .outlineVariant
                                          .withValues(alpha: 0.35),
                                      labelPadding:
                                          const EdgeInsetsDirectional.symmetric(
                                        horizontal: 8,
                                        vertical: 12,
                                      ),
                                      tabs: const [
                                        Tab(text: 'טפסים שנשלחו'),
                                        Tab(text: 'טיוטות'),
                                        Tab(text: 'טפסים מבוטלים'),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: TabBarView(
                                      controller: _tabController,
                                      children: [
                                        _FormsTabContent(
                                          viewerUserId: widget.userId,
                                          title: 'טפסים שנשלחו',
                                          subtitle:
                                              'טפסים אישיים וקבוצתיים שכבר הוגשו',
                                          items: submittedItems,
                                          emptyText:
                                              'אין עדיין טפסים שנשלחו להצגה',
                                          onItemTap: (item) => _handleItemTap(
                                            context: context,
                                            item: item,
                                          ),
                                          onCancelDraft: null,
                                          dismissGeneration: 0,
                                        ),
                                        _FormsTabContent(
                                          viewerUserId: widget.userId,
                                          title: 'טיוטות',
                                          subtitle:
                                              'טפסים שמורים או קבוצות שעדיין בתהליך',
                                          items: draftItems,
                                          emptyText: 'אין כרגע טיוטות להצגה',
                                          onItemTap: (item) => _handleItemTap(
                                            context: context,
                                            item: item,
                                          ),
                                          onCancelDraft: (item) async {
                                            if (item.kind !=
                                                    _FormsItemKind.groupDraft ||
                                                item.groupId == null) {
                                              return false;
                                            }

                                            final bool confirmed =
                                                await showDialog<bool>(
                                                      context: context,
                                                      builder:
                                                          (dialogContext) =>
                                                              AlertDialog(
                                                        title: const Text(
                                                          'ביטול טופס קבוצתי',
                                                        ),
                                                        content: const Text(
                                                          'האם אתה בטוח? רק מי שכבר שילם על הטופס יזוכה בארנק שלו.',
                                                        ),
                                                        actions: [
                                                          TextButton(
                                                            onPressed: () =>
                                                                Navigator.of(
                                                              dialogContext,
                                                            ).pop(false),
                                                            child: const Text(
                                                              'חזרה',
                                                            ),
                                                          ),
                                                          FilledButton(
                                                            onPressed: () =>
                                                                Navigator.of(
                                                              dialogContext,
                                                            ).pop(true),
                                                            child: const Text(
                                                              'אשר ביטול',
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ) ??
                                                    false;

                                            if (!confirmed) {
                                              return false;
                                            }

                                            final bool cancelled =
                                                await widget.onCancelGroupDraft(
                                              item.groupId!,
                                            );
                                            if (cancelled && mounted) {
                                              setState(() {
                                                _hiddenDraftItemKeys.add(
                                                  item.stableKey,
                                                );
                                                _draftDismissGeneration++;
                                              });
                                            }
                                            return cancelled;
                                          },
                                          dismissGeneration:
                                              _draftDismissGeneration,
                                        ),
                                        _FormsTabContent(
                                          viewerUserId: widget.userId,
                                          title: 'טפסים מבוטלים',
                                          subtitle:
                                              'טפסים קבוצתיים שבוטלו כולל זיכויים למי שכבר שילם',
                                          items: cancelledItems,
                                          emptyText:
                                              'אין כרגע טפסים שבוטלו להצגה',
                                          onItemTap: (item) => _handleItemTap(
                                            context: context,
                                            item: item,
                                          ),
                                          onCancelDraft: null,
                                          dismissGeneration: 0,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
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

  List<_FormsListItem> _buildPersonalSubmittedItems({
    required List<LotteryForm> submittedForms,
    required List<PersonalSubmittedBundle> personalBundles,
  }) {
    final Map<String, PersonalSubmittedBundle> bundlesById =
        <String, PersonalSubmittedBundle>{
      for (final PersonalSubmittedBundle bundle in personalBundles)
        bundle.submissionId: bundle,
    };

    final Map<String, List<LotteryForm>> formsByBundleId =
        <String, List<LotteryForm>>{};
    final List<LotteryForm> standaloneForms = <LotteryForm>[];

    for (final LotteryForm form in submittedForms) {
      final String? bundleId = form.submissionId ?? form.parentSubmissionId;
      if (bundleId == null || bundleId.isEmpty) {
        standaloneForms.add(form);
        continue;
      }
      formsByBundleId.putIfAbsent(bundleId, () => <LotteryForm>[]).add(form);
    }

    final List<_FormsListItem> items = <_FormsListItem>[
      ...standaloneForms.map(_FormsListItem.personalSubmitted),
    ];

    final Set<String> handledBundleIds = <String>{};
    for (final MapEntry<String, List<LotteryForm>> entry
        in formsByBundleId.entries) {
      final String bundleId = entry.key;
      final PersonalSubmittedBundle? existingBundle = bundlesById[bundleId];
      if (existingBundle != null) {
        items.add(_FormsListItem.personalSubmissionBundle(existingBundle));
        handledBundleIds.add(bundleId);
        continue;
      }
      items.add(
        _FormsListItem.personalSubmissionBundle(
          _derivePersonalBundleFromForms(
            submissionId: bundleId,
            forms: entry.value,
          ),
        ),
      );
      handledBundleIds.add(bundleId);
    }

    for (final PersonalSubmittedBundle bundle in personalBundles) {
      if (handledBundleIds.contains(bundle.submissionId)) {
        continue;
      }
      items.add(_FormsListItem.personalSubmissionBundle(bundle));
    }

    return items;
  }

  PersonalSubmittedBundle _derivePersonalBundleFromForms({
    required String submissionId,
    required List<LotteryForm> forms,
  }) {
    final List<LotteryForm> sortedForms = List<LotteryForm>.from(forms)
      ..sort((a, b) {
        final int left =
            (a.createdAt ?? a.savedAt ?? a.updatedAt ?? DateTime(0))
                .millisecondsSinceEpoch;
        final int right =
            (b.createdAt ?? b.savedAt ?? b.updatedAt ?? DateTime(0))
                .millisecondsSinceEpoch;
        return left.compareTo(right);
      });

    final List<PersonalSubmittedBundleForm> bundleForms =
        List<PersonalSubmittedBundleForm>.generate(
      sortedForms.length,
      (index) {
        final LotteryForm form = sortedForms[index];
        return PersonalSubmittedBundleForm(
          formId: form.formId ?? '$submissionId-$index',
          displayOrder: index + 1,
          tableCount: form.tables.where((table) => !table.isEmpty).length,
          cost: _calculatePersonalFormCost(form),
          isDoubleMode: false,
          lotteryId: form.lotteryId,
          salesCloseAt: form.salesCloseAt,
          tables: form.tables,
          submittedAt: form.submittedAt,
          printedAt: form.printedAt,
          submittedToStationAt: form.submittedToStationAt,
          resultPublishedAt: form.resultPublishedAt,
          resultStatus: form.resultStatus,
          winAmount: form.winAmount,
          receiptUrl: form.printReadyUrl,
        );
      },
    );

    return PersonalSubmittedBundle(
      submissionId: submissionId,
      userId: sortedForms.first.userId,
      formCount: bundleForms.length,
      totalCost: bundleForms.fold<num>(
        0,
        (num total, PersonalSubmittedBundleForm form) => total + form.cost,
      ),
      lotteryId: sortedForms.fold<int?>(
        null,
        (int? current, LotteryForm form) =>
            current ??
            ((form.lotteryId != null && form.lotteryId! > 0)
                ? form.lotteryId
                : null),
      ),
      salesCloseAt: sortedForms.fold<DateTime?>(
        null,
        (DateTime? current, LotteryForm form) => current ?? form.salesCloseAt,
      ),
      submittedAt: sortedForms
          .map((form) => form.submittedAt ?? form.updatedAt)
          .whereType<DateTime>()
          .fold<DateTime?>(
            null,
            (DateTime? latest, DateTime current) =>
                latest == null || current.isAfter(latest) ? current : latest,
          ),
      resultPublishedAt: sortedForms
          .map((form) => form.resultPublishedAt)
          .whereType<DateTime>()
          .fold<DateTime?>(
            null,
            (DateTime? latest, DateTime current) =>
                latest == null || current.isAfter(latest) ? current : latest,
          ),
      totalWinningAmount: sortedForms.fold<num>(
        0,
        (num total, LotteryForm form) =>
            total +
            ((form.resultPublishedAt != null ||
                    form.resultStatus == LotteryResultStatus.winner ||
                    form.resultStatus == LotteryResultStatus.loser ||
                    form.resultStatus == LotteryResultStatus.checked)
                ? form.winAmount
                : 0),
      ),
      forms: bundleForms,
    );
  }

  num _calculatePersonalFormCost(LotteryForm form) {
    final int populatedTableCount =
        form.tables.where((table) => !table.isEmpty).length;
    if (populatedTableCount <= 0) {
      return 0;
    }
    final int tablePairs = (populatedTableCount / 2).ceil();
    return tablePairs * 6;
  }
}

bool _isPersonalFormResultPublished(LotteryForm form) {
  return form.resultPublishedAt != null ||
      form.resultStatus == LotteryResultStatus.winner ||
      form.resultStatus == LotteryResultStatus.loser ||
      form.resultStatus == LotteryResultStatus.checked;
}

bool _isPersonalBundleFormResultPublished(PersonalSubmittedBundleForm form) {
  return form.resultPublishedAt != null ||
      form.resultStatus == LotteryResultStatus.winner ||
      form.resultStatus == LotteryResultStatus.loser ||
      form.resultStatus == LotteryResultStatus.checked;
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

class _FormsTabContent extends StatelessWidget {
  const _FormsTabContent({
    required this.viewerUserId,
    required this.title,
    required this.subtitle,
    required this.items,
    required this.emptyText,
    required this.onItemTap,
    required this.onCancelDraft,
    required this.dismissGeneration,
  });

  final String viewerUserId;
  final String title;
  final String subtitle;
  final List<_FormsListItem> items;
  final String emptyText;
  final ValueChanged<_FormsListItem> onItemTap;
  final Future<bool> Function(_FormsListItem item)? onCancelDraft;
  final int dismissGeneration;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                title,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
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
              key: ValueKey<String>(item.stableKey),
              padding: const EdgeInsets.only(bottom: 10),
              child: _FormsSummaryTile(
                viewerUserId: viewerUserId,
                item: item,
                dismissGeneration: dismissGeneration,
                onTap: () => onItemTap(item),
                onDelete:
                    onCancelDraft == null ? null : () => onCancelDraft!(item),
              ),
            ),
          ),
      ],
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

    final bool cancellableGroupDraft =
        widget.item.kind == _FormsItemKind.groupDraft &&
            widget.item.groupId != null &&
            widget.item.activeGroup?.creatorUserId == widget.viewerUserId &&
            widget.onDelete != null;
    final _HistoryCardVisualState visualState =
        _resolveHistoryCardVisualState(widget.item);
    final Color baseCardColor =
        Theme.of(context).colorScheme.primaryContainer;

    final Widget tile = Material(
      color: baseCardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: visualState.accentColor.withValues(alpha: 0.28),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 12),
          child: Stack(
            children: [
              PositionedDirectional(
                top: -12,
                bottom: -12,
                end: -16,
                child: Container(
                  width: 7,
                  decoration: BoxDecoration(
                    color: visualState.accentColor.withValues(alpha: 0.92),
                    borderRadius: const BorderRadiusDirectional.only(
                      topEnd: Radius.circular(16),
                      bottomEnd: Radius.circular(16),
                    ),
                  ),
                ),
              ),
              Row(
                textDirection: TextDirection.rtl,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SizedBox(
                      width: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            textDirection: TextDirection.rtl,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _HistoryResultChip(
                                label: visualState.chipLabel,
                                color: visualState.accentColor,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _titleText(),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _buildSubtitle(),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (cancellableGroupDraft)
                        IconButton(
                          onPressed: () async {
                            final bool cancelled = await widget.onDelete!();
                            if (cancelled && mounted) {
                              setState(() => _isCollapsed = true);
                            }
                          },
                          icon: const Icon(Icons.cancel_outlined),
                          tooltip: 'ביטול טיוטה קבוצתית',
                          visualDensity: VisualDensity.compact,
                        ),
                      const Padding(
                        padding: EdgeInsetsDirectional.only(top: 2),
                        child: Icon(Icons.chevron_left),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return tile;
  }

  Widget _buildSubtitle() {
    if (widget.item.kind == _FormsItemKind.groupSubmitted ||
        widget.item.kind == _FormsItemKind.groupDraft ||
        widget.item.kind == _FormsItemKind.groupCancelled) {
      return SizedBox(
        width: double.infinity,
        child: _GroupSummaryDetails(
          item: widget.item,
          viewerUserId: widget.viewerUserId,
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: Text(
        _subtitleText(),
        textAlign: TextAlign.right,
      ),
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
        final DateTime? safeDrawDate =
            _coerceSafeDrawDate(form.salesCloseAt, form.submittedAt);
        final List<String> lines = [
          'סטטוס: ${_personalStatusLabel(form)}',
          'מס׳ הגרלה: ${form.lotteryId?.toString() ?? '—'}',
          'תאריך הגרלה: ${_formatDate(safeDrawDate)}',
          'עלות טופס: ${_ticketCost(form)} ש״ח',
          'זכייה: ${_personalWinningStatusLabel(form)}',
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
        final PersonalSubmittedBundle bundle =
            widget.item.personalSubmissionBundle!;
        final String bundleStatus = _bundleResultStatusLabel(bundle);
        return [
          'סטטוס: $bundleStatus',
          'מספר טפסים: ${bundle.formCount}',
          'מס׳ הגרלה: ${_bundleLotteryIdLabel(bundle)}',
          'תאריך הגרלה: ${_formatDate(_bundleLotteryDate(bundle))}',
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
    if (!_isPersonalFormResultPublished(form)) {
      return 'טרם פורסם';
    }
    return '${form.winAmount} ש״ח';
  }

  String _bundleWinningStatusLabel(PersonalSubmittedBundle bundle) {
    if (bundle.forms.isEmpty) {
      return 'טרם פורסם';
    }

    final bool hasAnyPublishedResult = bundle.forms.any(
      _isPersonalBundleFormResultPublished,
    );
    if (!hasAnyPublishedResult) {
      return 'טרם פורסם';
    }

    final num totalWinAmount = bundle.forms.fold<num>(
      0,
      (num total, PersonalSubmittedBundleForm form) =>
          total +
          (_isPersonalBundleFormResultPublished(form) ? form.winAmount : 0),
    );
    return '$totalWinAmount ש״ח';
  }

  String _bundleResultStatusLabel(PersonalSubmittedBundle bundle) {
    if (bundle.forms.isEmpty) {
      return 'נשלחו כמה טפסים אישיים';
    }
    final bool hasAnyPublishedResult = bundle.forms.any(
      _isPersonalBundleFormResultPublished,
    );
    if (!hasAnyPublishedResult) {
      return 'ממתין לתוצאות';
    }
    if (bundle.forms
        .any((form) => form.resultStatus == LotteryResultStatus.winner)) {
      return 'פורסמו תוצאות';
    }
    if (bundle.forms.every(
      (form) => form.resultStatus == LotteryResultStatus.loser,
    )) {
      return 'ללא זכייה';
    }
    return 'פורסמו תוצאות';
  }

  String _bundleLotteryIdLabel(PersonalSubmittedBundle bundle) {
    String sourceOfLotteryId = 'none';
    String? resolvedLotteryId;
    debugPrint(
      '[PersonalBundleCardDebug] bundleId=${bundle.submissionId} forms=${bundle.forms.length}',
    );
    for (final PersonalSubmittedBundleForm form in bundle.forms) {
      debugPrint(
        '[PersonalBundleCardDebug] formId=${form.formId} submissionId=${bundle.submissionId} lotteryId=${form.lotteryId?.toString() ?? 'null'} drawNumberAlias=${form.lotteryId?.toString() ?? 'null'} salesCloseAt=${form.salesCloseAt?.toIso8601String() ?? 'null'} drawDateAlias=${form.salesCloseAt?.toIso8601String() ?? 'null'} submittedAt=${form.submittedAt?.toIso8601String() ?? 'null'} resultStatus=${form.resultStatus?.value ?? 'null'} resultPublishedAt=${form.resultPublishedAt?.toIso8601String() ?? 'null'}',
      );
      if (form.lotteryId != null && form.lotteryId! > 0) {
        sourceOfLotteryId = 'childForm';
        resolvedLotteryId = form.lotteryId!.toString();
        break;
      }
    }
    if (resolvedLotteryId == null &&
        bundle.lotteryId != null &&
        bundle.lotteryId! > 0) {
      sourceOfLotteryId = 'parentSubmission';
      resolvedLotteryId = bundle.lotteryId!.toString();
    }
    debugPrint(
      '[PersonalBundleCardDebug] bundleId=${bundle.submissionId} resolvedLotteryId=${resolvedLotteryId ?? 'null'} sourceOfLotteryId=$sourceOfLotteryId',
    );
    return resolvedLotteryId ?? '—';
  }

  DateTime? _bundleLotteryDate(PersonalSubmittedBundle bundle) {
    String sourceOfDrawDate = 'none';
    DateTime? resolvedDrawDate;
    for (final PersonalSubmittedBundleForm form in bundle.forms) {
      final DateTime? safeChildDrawDate = _coerceSafeDrawDate(
        form.salesCloseAt,
        form.submittedAt ?? bundle.submittedAt,
      );
      if (safeChildDrawDate != null) {
        sourceOfDrawDate = 'childForm';
        resolvedDrawDate = safeChildDrawDate;
        break;
      }
    }
    final DateTime? safeParentDrawDate =
        _coerceSafeDrawDate(bundle.salesCloseAt, bundle.submittedAt);
    if (resolvedDrawDate == null && safeParentDrawDate != null) {
      sourceOfDrawDate = 'parentSubmission';
      resolvedDrawDate = safeParentDrawDate;
    }
    debugPrint(
      '[PersonalBundleCardDebug] bundleId=${bundle.submissionId} resolvedDrawDate=${resolvedDrawDate?.toIso8601String() ?? 'null'} sourceOfDrawDate=$sourceOfDrawDate',
    );
    return resolvedDrawDate;
  }

  bool _isPersonalFormResultPublished(LotteryForm form) {
    return form.resultPublishedAt != null ||
        form.resultStatus == LotteryResultStatus.winner ||
        form.resultStatus == LotteryResultStatus.loser ||
        form.resultStatus == LotteryResultStatus.checked;
  }

  bool _isPersonalBundleFormResultPublished(PersonalSubmittedBundleForm form) {
    return form.resultPublishedAt != null ||
        form.resultStatus == LotteryResultStatus.winner ||
        form.resultStatus == LotteryResultStatus.loser ||
        form.resultStatus == LotteryResultStatus.checked;
  }

  DateTime? _coerceSafeDrawDate(DateTime? drawDate, DateTime? submittedAt) {
    if (drawDate == null) {
      return null;
    }
    if (submittedAt == null || !drawDate.isBefore(submittedAt)) {
      return drawDate;
    }
    return null;
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

class _HistoryResultChip extends StatelessWidget {
  const _HistoryResultChip({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withValues(alpha: 0.65),
        ),
      ),
      child: Text(
        label,
        textAlign: TextAlign.right,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
      ),
    );
  }
}

class _HistoryCardVisualState {
  const _HistoryCardVisualState({
    required this.accentColor,
    required this.chipLabel,
  });

  final Color accentColor;
  final String chipLabel;
}

_HistoryCardVisualState _resolveHistoryCardVisualState(_FormsListItem item) {
  switch (item.kind) {
    case _FormsItemKind.personalSubmitted:
      final LotteryForm form = item.personalForm!;
      return _buildHistoryCardVisualState(
        isPublished: _isPersonalFormResultPublished(form),
        winAmount: form.winAmount,
      );
    case _FormsItemKind.personalDraft:
      return _buildHistoryCardVisualState(
        isPublished: false,
        winAmount: 0,
      );
    case _FormsItemKind.personalSubmissionBundle:
      final PersonalSubmittedBundle bundle = item.personalSubmissionBundle!;
      final bool isPublished = bundle.forms.any(
        _isPersonalBundleFormResultPublished,
      );
      final num totalWinAmount = bundle.forms.fold<num>(
        0,
        (num total, PersonalSubmittedBundleForm form) =>
            total +
            (_isPersonalBundleFormResultPublished(form) ? form.winAmount : 0),
      );
      return _buildHistoryCardVisualState(
        isPublished: isPublished,
        winAmount: totalWinAmount,
      );
    case _FormsItemKind.groupSubmitted:
      final SubmittedGroupHistoryItem group = item.submittedGroup!;
      return _buildHistoryCardVisualState(
        isPublished: group.resultPublishedAt != null,
        winAmount: _firstNumericValue(
          <dynamic>[
            group.myWinningAmount,
            group.groupWinningAmount,
          ],
        ),
      );
    case _FormsItemKind.groupDraft:
      return _buildHistoryCardVisualState(
        isPublished: false,
        winAmount: 0,
      );
    case _FormsItemKind.groupCancelled:
      return const _HistoryCardVisualState(
        accentColor: Color(0xFFBDBDBD),
        chipLabel: 'בוטל',
      );
  }
}

_HistoryCardVisualState _buildHistoryCardVisualState({
  required bool isPublished,
  required num winAmount,
}) {
  return _HistoryCardVisualState(
    accentColor: getCardBorderColor(isPublished, winAmount),
    chipLabel: getResultChipLabel(isPublished, winAmount),
  );
}

Color getCardBorderColor(bool isPublished, num winAmount) {
  if (!isPublished) {
    return const Color(0xFFFFC107);
  }
  if (winAmount > 0) {
    return const Color(0xFF4CAF50);
  }
  return const Color(0xFFBDBDBD);
}

String getResultChipLabel(bool isPublished, num winAmount) {
  if (!isPublished) {
    return 'ממתין לתוצאות';
  }
  if (winAmount > 0) {
    return 'זכה';
  }
  return 'לא זכה';
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
        final _GroupHistoryFormMeta directMeta =
            _extractGroupHistoryMeta(groupData);
        final _GroupResultDisplay summaryResultDisplay =
            _resolveGroupResultDisplay(
          groupData: groupData,
          submittedGroup: item.submittedGroup,
        );
        final String? fallbackFormId = submittedFormId?.isNotEmpty == true
            ? submittedFormId
            : sourceFormId;

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('lottery_groups')
              .doc(groupId)
              .collection('forms')
              .snapshots(),
          builder: (context, groupFormsSnapshot) {
            final bool childQueryExecuted =
                groupFormsSnapshot.connectionState != ConnectionState.none;
            final String? childQueryError = groupFormsSnapshot.error?.toString();
            final int loadedChildDocsCount =
                groupFormsSnapshot.data?.docs.length ?? 0;
            final List<Map<String, dynamic>> canonicalForms = groupFormsSnapshot
                    .data?.docs
                    .map((doc) => doc.data())
                    .toList() ??
                const <Map<String, dynamic>>[];
            final _GroupResultDisplay resultDisplay =
                _resolveEffectiveGroupResultDisplay(
              groupData: groupData,
              submittedGroup: item.submittedGroup,
              canonicalForms: canonicalForms,
              viewerUserId: viewerUserId,
              fallbackDisplay: summaryResultDisplay,
              hasLoadedCanonicalForms: loadedChildDocsCount > 0,
            );
            final _GroupResultDebugInfo debugInfo = _buildGroupResultDebugInfo(
              groupId: groupId,
              summaryDisplay: summaryResultDisplay,
              effectiveDisplay: resultDisplay,
              canonicalForms: canonicalForms,
              loadedChildDocsCount: loadedChildDocsCount,
              childQueryExecuted: childQueryExecuted,
              childQueryError: childQueryError,
            );
            debugPrint(
              '[GroupCardDebug] groupId=$groupId childFormsCount=${debugInfo.childFormsCount} loadedChildDocsCount=${debugInfo.loadedChildDocsCount} childQueryExecuted=${debugInfo.childQueryExecuted} childQueryError=${debugInfo.childQueryError ?? 'null'} publishedFormsCount=${debugInfo.publishedFormsCount} sumWinAmount=${debugInfo.sumWinAmount} resolvedHasPublishedResults=${debugInfo.resolvedHasPublishedResults} sourceUsed=${debugInfo.sourceUsed} summaryPublished=${summaryResultDisplay.isPublished} summaryGroupWinningAmount=${summaryResultDisplay.groupWinningAmount} effectiveGroupWinningAmount=${resultDisplay.groupWinningAmount} effectiveMyWinningAmount=${resultDisplay.myWinningAmount}',
            );

            if (directMeta.hasAnyValue) {
              return Text(
                _resolvedText(
                  meta: directMeta,
                  resultDisplay: resultDisplay,
                  debugInfo: debugInfo,
                  createdAt: createdAt,
                  submittedAt: submittedAt,
                ),
                textAlign: TextAlign.right,
              );
            }

            if (creatorUserId != null &&
                creatorUserId.isNotEmpty &&
                fallbackFormId != null &&
                fallbackFormId.isNotEmpty) {
              return FutureBuilder<_GroupHistoryFormMeta>(
                future: _loadFormMetaFromSourceForm(
                  creatorUserId: creatorUserId,
                  formId: fallbackFormId,
                ),
                builder: (context, metaSnapshot) {
                  return Text(
                    _resolvedText(
                      meta: metaSnapshot.data ?? const _GroupHistoryFormMeta(),
                      resultDisplay: resultDisplay,
                      debugInfo: debugInfo,
                      createdAt: createdAt,
                      submittedAt: submittedAt,
                    ),
                    textAlign: TextAlign.right,
                  );
                },
              );
            }

            return Text(
              _resolvedText(
                meta: const _GroupHistoryFormMeta(),
                resultDisplay: resultDisplay,
                debugInfo: debugInfo,
                createdAt: createdAt,
                submittedAt: submittedAt,
              ),
              textAlign: TextAlign.right,
            );
          },
        );
      },
    );
  }

  String _resolvedText({
    required _GroupHistoryFormMeta meta,
    required _GroupResultDisplay resultDisplay,
    required _GroupResultDebugInfo debugInfo,
    required DateTime? createdAt,
    required DateTime? submittedAt,
  }) {
    if (item.kind == _FormsItemKind.groupSubmitted) {
      return _submittedText(
        submittedAt: submittedAt,
        meta: meta,
        resultDisplay: resultDisplay,
        debugInfo: debugInfo,
      );
    }
    if (item.kind == _FormsItemKind.groupCancelled) {
      return _cancelledText(meta: meta);
    }
    return _draftText(
      createdAt: createdAt,
      meta: meta,
    );
  }

  String _submittedText({
    required DateTime? submittedAt,
    required _GroupHistoryFormMeta meta,
    required _GroupResultDisplay resultDisplay,
    required _GroupResultDebugInfo debugInfo,
  }) {
    final SubmittedGroupHistoryItem group = item.submittedGroup!;

    final List<String> lines = <String>[
      'נוצר על ידי: ${group.creatorName}',
      'סטטוס: ${_submittedStatusLabel(group.dispatchStatus)}',
      'מס׳ הגרלה: ${meta.lotteryIdLabel ?? '—'}',
      'תאריך הגרלה: ${formatPresentationDateTime(meta.lotteryDate ?? submittedAt ?? group.submittedAt)}',
      'העלות שלי: ${group.myEffectiveShare} ש״ח',
      'נשלח: ${formatPresentationDateTime(submittedAt ?? group.submittedAt)}',
      'זכייה קבוצתית: ${resultDisplay.groupLabel}',
      'הזכייה שלי: ${resultDisplay.myLabel}',
    ];
    return lines.join('\n');
  }

  String _draftText({
    required DateTime? createdAt,
    required _GroupHistoryFormMeta meta,
  }) {
    if (item.kind == _FormsItemKind.groupDraft) {
      final UserGroupListItem group = item.activeGroup!;
      return [
        'נוצר על ידי: ${group.creatorName ?? group.creatorUserId}',
        'סטטוס: ${_groupStatusLabel(group.groupStatus)}',
        'מס׳ הגרלה: ${meta.lotteryIdLabel ?? '—'}',
        'תאריך הגרלה: ${formatPresentationDateTime(meta.lotteryDate ?? createdAt ?? group.updatedAt)}',
        'עלות שלי: ${_draftGroupCostLabel(group)}',
        'נוצר: ${formatPresentationDateTime(createdAt ?? group.updatedAt)}',
        'מצב תגובה: ${_responseStatusLabel(group.responseStatus)}',
      ].join('\n');
    }

    return _fallbackText();
  }

  String _cancelledText({
    required _GroupHistoryFormMeta meta,
  }) {
    final CancelledGroupHistoryItem group = item.cancelledGroup!;
    return [
      'נוצר על ידי: ${group.creatorName}',
      'סטטוס: בוטל',
      'מס׳ הגרלה: ${meta.lotteryIdLabel ?? '—'}',
      'תאריך הגרלה: ${formatPresentationDateTime(meta.lotteryDate ?? group.cancelledAt)}',
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
      return _cancelledText(meta: const _GroupHistoryFormMeta());
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

  _GroupHistoryFormMeta _extractGroupHistoryMeta(
      Map<String, dynamic> groupData) {
    final int? directLotteryId = (groupData['lotteryId'] as num?)?.toInt();
    final DateTime? directLotteryDate =
        presentationAsDateTime(groupData['salesCloseAt']);
    final Map<String, dynamic> snapshot = Map<String, dynamic>.from(
      groupData['formSnapshot'] as Map? ?? const <String, dynamic>{},
    );
    return _GroupHistoryFormMeta(
      lotteryIdLabel:
          (directLotteryId ?? (snapshot['lotteryId'] as num?)?.toInt())
              ?.toString(),
      lotteryDate:
          directLotteryDate ?? presentationAsDateTime(snapshot['salesCloseAt']),
    );
  }

  Future<_GroupHistoryFormMeta> _loadFormMetaFromSourceForm({
    required String creatorUserId,
    required String formId,
  }) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> formSnapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(creatorUserId)
              .collection('forms')
              .doc(formId)
              .get();
      final Map<String, dynamic> data =
          formSnapshot.data() ?? const <String, dynamic>{};
      final int? lotteryId = (data['lotteryId'] as num?)?.toInt();
      return _GroupHistoryFormMeta(
        lotteryIdLabel: lotteryId?.toString(),
        lotteryDate: presentationAsDateTime(data['salesCloseAt']),
      );
    } catch (_) {
      return const _GroupHistoryFormMeta();
    }
  }
}

class _GroupHistoryFormMeta {
  const _GroupHistoryFormMeta({
    this.lotteryIdLabel,
    this.lotteryDate,
  });

  final String? lotteryIdLabel;
  final DateTime? lotteryDate;

  bool get hasAnyValue => lotteryIdLabel != null || lotteryDate != null;
}

class _GroupResultDisplay {
  const _GroupResultDisplay({
    required this.isPublished,
    required this.groupWinningAmount,
    required this.myWinningAmount,
  });

  final bool isPublished;
  final num groupWinningAmount;
  final num myWinningAmount;

  String get groupLabel =>
      isPublished ? '$groupWinningAmount ש״ח' : 'טרם פורסם';
  String get myLabel => isPublished ? '$myWinningAmount ש״ח' : 'טרם פורסם';
}

class _GroupResultDebugInfo {
  const _GroupResultDebugInfo({
    required this.groupId,
    required this.childFormsCount,
    required this.loadedChildDocsCount,
    required this.childQueryExecuted,
    required this.childQueryError,
    required this.publishedFormsCount,
    required this.sumWinAmount,
    required this.resolvedHasPublishedResults,
    required this.sourceUsed,
  });

  final String groupId;
  final int childFormsCount;
  final int loadedChildDocsCount;
  final bool childQueryExecuted;
  final String? childQueryError;
  final int publishedFormsCount;
  final num sumWinAmount;
  final bool resolvedHasPublishedResults;
  final String sourceUsed;
}

_GroupResultDisplay _resolveGroupResultDisplay({
  required Map<String, dynamic> groupData,
  required SubmittedGroupHistoryItem? submittedGroup,
}) {
  final DateTime? resultPublishedAt =
      presentationAsDateTime(groupData['resultPublishedAt']) ??
          submittedGroup?.resultPublishedAt;
  final String resultStatus =
      (groupData['resultStatus'] as String?)?.trim() ?? '';
  final bool hasAmount = _hasFiniteNumericValue(
    <dynamic>[
      groupData['groupWinningAmount'],
      submittedGroup?.groupWinningAmount,
      groupData['winAmount'],
      groupData['winningAmount'],
      groupData['myWinningAmount'],
      submittedGroup?.myWinningAmount,
    ],
  );
  final bool isPublished = resultPublishedAt != null ||
      resultStatus == 'winner' ||
      resultStatus == 'loser' ||
      resultStatus == 'checked' ||
      (hasAmount && !_isPendingGroupResultStatus(resultStatus));

  final num groupWinningAmount = _firstNumericValue(
    <dynamic>[
      groupData['groupWinningAmount'],
      submittedGroup?.groupWinningAmount,
      groupData['winAmount'],
      groupData['winningAmount'],
    ],
  );

  num myWinningAmount = _firstNumericValue(
    <dynamic>[
      groupData['myWinningAmount'],
      submittedGroup?.myWinningAmount,
    ],
  );

  final int effectiveParticipantCount =
      (groupData['effectiveParticipantCount'] as num?)?.toInt() ??
          (groupData['finalizedParticipantCount'] as num?)?.toInt() ??
          ((groupData['paidParticipants'] as List<dynamic>?)?.length ?? 0);
  if (myWinningAmount == 0 &&
      groupWinningAmount >= 0 &&
      effectiveParticipantCount == 1) {
    myWinningAmount = groupWinningAmount;
  }

  return _GroupResultDisplay(
    isPublished: isPublished,
    groupWinningAmount: groupWinningAmount,
    myWinningAmount: myWinningAmount,
  );
}

_GroupResultDisplay _resolveEffectiveGroupResultDisplay({
  required Map<String, dynamic> groupData,
  required SubmittedGroupHistoryItem? submittedGroup,
  required List<Map<String, dynamic>> canonicalForms,
  required String viewerUserId,
  required _GroupResultDisplay fallbackDisplay,
  required bool hasLoadedCanonicalForms,
}) {
  final _GroupResultDisplay canonicalDisplay =
      _resolveGroupResultDisplayFromForms(
    canonicalForms: canonicalForms,
    viewerUserId: viewerUserId,
  );
  if (hasLoadedCanonicalForms) {
    return canonicalDisplay;
  }
  return fallbackDisplay;
}

_GroupResultDebugInfo _buildGroupResultDebugInfo({
  required String groupId,
  required _GroupResultDisplay summaryDisplay,
  required _GroupResultDisplay effectiveDisplay,
  required List<Map<String, dynamic>> canonicalForms,
  required int loadedChildDocsCount,
  required bool childQueryExecuted,
  required String? childQueryError,
}) {
  final int publishedFormsCount =
      canonicalForms.where(_isCanonicalGroupFormPublished).length;
  final num sumWinAmount = canonicalForms.fold<num>(
    0,
    (num total, Map<String, dynamic> form) => total + _groupFormAmount(form),
  );
  final String sourceUsed =
      loadedChildDocsCount > 0 ? 'canonical forms' : 'summary';
  return _GroupResultDebugInfo(
    groupId: groupId,
    childFormsCount: canonicalForms.length,
    loadedChildDocsCount: loadedChildDocsCount,
    childQueryExecuted: childQueryExecuted,
    childQueryError: childQueryError,
    publishedFormsCount: publishedFormsCount,
    sumWinAmount: sumWinAmount,
    resolvedHasPublishedResults: effectiveDisplay.isPublished,
    sourceUsed: sourceUsed,
  );
}

_GroupResultDisplay _resolveGroupResultDisplayFromForms({
  required List<Map<String, dynamic>> canonicalForms,
  required String viewerUserId,
}) {
  if (canonicalForms.isEmpty) {
    return const _GroupResultDisplay(
      isPublished: false,
      groupWinningAmount: 0,
      myWinningAmount: 0,
    );
  }

  final bool isPublished = canonicalForms.any(_isCanonicalGroupFormPublished);

  final num groupWinningAmount = canonicalForms.fold<num>(
    0,
    (num total, Map<String, dynamic> form) => total + _groupFormAmount(form),
  );

  final num myWinningAmount = canonicalForms.fold<num>(
    0,
    (num total, Map<String, dynamic> form) =>
        total + _resolveViewerWinningAmountFromGroupForm(form, viewerUserId),
  );

  return _GroupResultDisplay(
    isPublished: isPublished,
    groupWinningAmount: groupWinningAmount,
    myWinningAmount: myWinningAmount,
  );
}

bool _isCanonicalGroupFormPublished(Map<String, dynamic> form) {
  final String resultStatus = (form['resultStatus'] as String?)?.trim() ?? '';
  final bool hasAmount = _hasFiniteNumericValue(
    <dynamic>[
      form['groupWinningAmount'],
      form['winAmount'],
      form['winningAmount'],
    ],
  );
  final bool isWaitingStatus = _isPendingGroupResultStatus(resultStatus);
  return presentationAsDateTime(form['resultPublishedAt']) != null ||
      resultStatus == 'winner' ||
      resultStatus == 'loser' ||
      resultStatus == 'checked' ||
      (hasAmount && !isWaitingStatus);
}

bool _isPendingGroupResultStatus(String status) {
  final String normalized = status.trim().toLowerCase();
  return normalized.isEmpty ||
      normalized == 'waiting_for_results' ||
      normalized == 'waitingforresults' ||
      normalized == 'pending';
}

bool _hasFiniteNumericValue(List<dynamic> values) {
  for (final dynamic value in values) {
    if (value is num && value.isFinite) {
      return true;
    }
  }
  return false;
}

num _groupFormAmount(Map<String, dynamic> form) {
  if (form.containsKey('groupWinningAmount') &&
      form['groupWinningAmount'] is num) {
    return form['groupWinningAmount'] as num;
  }
  if (form.containsKey('winAmount') && form['winAmount'] is num) {
    return form['winAmount'] as num;
  }
  if (form.containsKey('winningAmount') && form['winningAmount'] is num) {
    return form['winningAmount'] as num;
  }
  return 0;
}

num _resolveViewerWinningAmountFromGroupForm(
  Map<String, dynamic> form,
  String viewerUserId,
) {
  final num explicit = _firstNumericValue(<dynamic>[form['myWinningAmount']]);
  if (explicit > 0) {
    return explicit;
  }

  final dynamic winAllocations = form['winAllocations'];
  if (winAllocations is List) {
    for (final dynamic entry in winAllocations) {
      if (entry is Map &&
          (entry['userId'] as String?)?.trim() == viewerUserId) {
        return _firstNumericValue(<dynamic>[entry['amount']]);
      }
    }
  } else if (winAllocations is Map) {
    final dynamic direct = winAllocations[viewerUserId];
    if (direct is num) {
      return direct;
    }
  }

  final int effectiveParticipantCount =
      (form['effectiveParticipantCount'] as num?)?.toInt() ??
          ((form['paidParticipants'] as List<dynamic>?)?.length ?? 0);
  if (effectiveParticipantCount == 1) {
    return _groupFormAmount(form);
  }
  return 0;
}

num _firstNumericValue(List<dynamic> candidates) {
  for (final dynamic candidate in candidates) {
    if (candidate is num) {
      return candidate;
    }
  }
  return 0;
}
