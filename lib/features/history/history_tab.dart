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

const Color _historyDarkCard = Color(0xFF4C2A35);
const Color _historyDarkCardEdge = Color(0xFF6A3D4C);
const Color _historyDarkTextPrimary = Color(0xFFFFF7F9);
const Color _historyDarkTextSecondary = Color(0xFFE6D7DD);
const Color _historyDarkTextMuted = Color(0xFFCFBCC4);
const Color _historyLightCard = Color(0xFFFFFBFC);
const Color _historyLightCardEdge = Color(0xFFE7D6DC);
const Color _historyLightTextPrimary = Color(0xFF2E1D24);
const Color _historyLightTextSecondary = Color(0xFF5B474F);
const Color _historyLightTextMuted = Color(0xFF7A656D);

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

                            final List<_FormsListItem> waitingItems =
                                submittedItems
                                    .where(_isWaitingTabItem)
                                    .toList()
                                  ..sort(
                                    (a, b) =>
                                        b.sortDate.compareTo(a.sortDate),
                                  );

                            final List<_FormsListItem> historyItems = [
                              ...submittedItems.where(_isHistoryTabItem),
                              ...cancelledItems,
                            ]..sort(
                                (a, b) => b.sortDate.compareTo(a.sortDate),
                              );

                            return Directionality(
                              textDirection: TextDirection.rtl,
                              child: Column(
                                children: [
                                  Material(
                                    color: Colors.transparent,
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        final double textScale =
                                            MediaQuery.textScalerOf(context)
                                                    .scale(14) /
                                                14;
                                        final bool useScrollableTabs =
                                            textScale > 1.25 ||
                                                constraints.maxWidth < 360;

                                        return Container(
                                          margin: const EdgeInsets.fromLTRB(
                                            12,
                                            8,
                                            12,
                                            0,
                                          ),
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: _historyTabShellColor(
                                              context,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(22),
                                            border: Border.all(
                                              color:
                                                  _historyTabShellBorderColor(
                                                context,
                                              ),
                                            ),
                                          ),
                                          child: TabBar(
                                            controller: _tabController,
                                            isScrollable: useScrollableTabs,
                                            tabAlignment: useScrollableTabs
                                                ? TabAlignment.start
                                                : TabAlignment.fill,
                                            indicatorSize:
                                                TabBarIndicatorSize.tab,
                                            dividerColor: Colors.transparent,
                                            indicator: BoxDecoration(
                                              color:
                                                  _historyTabIndicatorColor(
                                                context,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              border: Border.all(
                                                color:
                                                    _historyTabIndicatorBorderColor(
                                                  context,
                                                ),
                                              ),
                                            ),
                                            labelColor:
                                                _historyCardTitleColor(context),
                                            unselectedLabelColor:
                                                _historyCardMutedTextColor(
                                              context,
                                            ),
                                            labelStyle: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 14,
                                            ),
                                            unselectedLabelStyle:
                                                const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                            ),
                                            labelPadding: useScrollableTabs
                                                ? const EdgeInsetsDirectional
                                                    .symmetric(
                                                    horizontal: 14,
                                                    vertical: 12,
                                                  )
                                                : EdgeInsets.zero,
                                            tabs: const [
                                              Tab(text: 'ממתינים להגרלה'),
                                              Tab(text: 'היסטוריה'),
                                              Tab(text: 'טיוטות'),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  Expanded(
                                    child: TabBarView(
                                      controller: _tabController,
                                      children: [
                                        _FormsTabContent(
                                          viewerUserId: widget.userId,
                                          title: 'ממתינים להגרלה',
                                          subtitle:
                                              'טפסים שנשלחו ומחכים להגרלה הקרובה',
                                          infoTooltip:
                                              'טפסים שנשלחו ומחכים להגרלה הקרובה',
                                          sectionKind:
                                              _HistorySectionKind.waiting,
                                          items: waitingItems,
                                          emptyText:
                                              'אין כרגע טפסים שממתינים להגרלה',
                                          onItemTap: (item) => _handleItemTap(
                                            context: context,
                                            item: item,
                                          ),
                                          onCancelDraft: null,
                                          dismissGeneration: 0,
                                          hideStatusChip: true,
                                        ),
                                        _FormsTabContent(
                                          viewerUserId: widget.userId,
                                          title: 'היסטוריה',
                                          subtitle:
                                              'טפסים שההגרלה שלהם הסתיימה או בוטלו',
                                          infoTooltip:
                                              'טפסים שההגרלה שלהם הסתיימה או בוטלו',
                                          sectionKind:
                                              _HistorySectionKind.history,
                                          items: historyItems,
                                          emptyText: 'אין עדיין פריטי היסטוריה להצגה',
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
                                              'טפסים שלא הוגשו עדיין, כולל קבוצות בהקמה',
                                          infoTooltip:
                                              'טפסים שלא הוגשו עדיין, כולל קבוצות בהקמה',
                                          sectionKind:
                                              _HistorySectionKind.drafts,
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
                                          hideStatusChip: true,
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

bool _isWaitingTabItem(_FormsListItem item) {
  switch (item.kind) {
    case _FormsItemKind.personalSubmitted:
      final LotteryForm form = item.personalForm!;
      return !_isPersonalFormResultPublished(form) &&
          !_isCancelledPersonalStatus(form.status);
    case _FormsItemKind.personalSubmissionBundle:
      final PersonalSubmittedBundle bundle = item.personalSubmissionBundle!;
      return !bundle.forms.any(_isPersonalBundleFormResultPublished);
    case _FormsItemKind.groupSubmitted:
      final SubmittedGroupHistoryItem group = item.submittedGroup!;
      return group.resultPublishedAt == null;
    case _FormsItemKind.personalDraft:
    case _FormsItemKind.groupDraft:
    case _FormsItemKind.groupCancelled:
      return false;
  }
}

bool _isHistoryTabItem(_FormsListItem item) {
  switch (item.kind) {
    case _FormsItemKind.personalSubmitted:
      final LotteryForm form = item.personalForm!;
      return _isPersonalFormResultPublished(form) ||
          _isCancelledPersonalStatus(form.status);
    case _FormsItemKind.personalSubmissionBundle:
      final PersonalSubmittedBundle bundle = item.personalSubmissionBundle!;
      return bundle.forms.any(_isPersonalBundleFormResultPublished);
    case _FormsItemKind.groupSubmitted:
      final SubmittedGroupHistoryItem group = item.submittedGroup!;
      return group.resultPublishedAt != null;
    case _FormsItemKind.groupCancelled:
      return true;
    case _FormsItemKind.personalDraft:
    case _FormsItemKind.groupDraft:
      return false;
  }
}

bool _isCancelledPersonalStatus(LotteryFormStatus status) {
  return status == LotteryFormStatus.cancelled;
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
    required this.infoTooltip,
    required this.sectionKind,
    required this.items,
    required this.emptyText,
    required this.onItemTap,
    required this.onCancelDraft,
    required this.dismissGeneration,
    this.hideStatusChip = false,
  });

  final String viewerUserId;
  final String title;
  final String subtitle;
  final String infoTooltip;
  final _HistorySectionKind sectionKind;
  final List<_FormsListItem> items;
  final String emptyText;
  final ValueChanged<_FormsListItem> onItemTap;
  final Future<bool> Function(_FormsListItem item)? onCancelDraft;
  final int dismissGeneration;
  final bool hideStatusChip;

  @override
  Widget build(BuildContext context) {
    final Color titleColor = _historyCardTitleColor(context);
    final Color secondaryColor = _historyCardSecondaryTextColor(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Directionality(
          textDirection: TextDirection.rtl,
          child: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.max,
                    textDirection: TextDirection.rtl,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Tooltip(
                        message: infoTooltip,
                        child: Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: secondaryColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          subtitle,
                          textAlign: TextAlign.right,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: titleColor,
                                height: 1.25,
                              ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              emptyText,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: secondaryColor,
                  ),
            ),
          )
        else
          ...items.map(
            (item) => Padding(
              key: ValueKey<String>(item.stableKey),
              padding: const EdgeInsets.only(bottom: 10),
              child: _SubmittedGroupVisibilityGate(
                viewerUserId: viewerUserId,
                item: item,
                sectionKind: sectionKind,
                child: _FormsSummaryTile(
                  viewerUserId: viewerUserId,
                  item: item,
                  dismissGeneration: dismissGeneration,
                  hideStatusChip: hideStatusChip,
                  onTap: () => onItemTap(item),
                  onDelete:
                      onCancelDraft == null ? null : () => onCancelDraft!(item),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

enum _HistorySectionKind {
  waiting,
  history,
  drafts,
}

class _SubmittedGroupVisibilityGate extends StatelessWidget {
  const _SubmittedGroupVisibilityGate({
    required this.viewerUserId,
    required this.item,
    required this.sectionKind,
    required this.child,
  });

  final String viewerUserId;
  final _FormsListItem item;
  final _HistorySectionKind sectionKind;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (item.kind != _FormsItemKind.groupSubmitted ||
        (sectionKind != _HistorySectionKind.waiting &&
            sectionKind != _HistorySectionKind.history) ||
        item.groupId == null) {
      return child;
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('lottery_groups')
          .doc(item.groupId)
          .collection('forms')
          .snapshots(),
      builder: (context, snapshot) {
        final List<Map<String, dynamic>> canonicalForms = snapshot.data?.docs
                .map((doc) => doc.data())
                .toList() ??
            const <Map<String, dynamic>>[];
        final bool resolvedPublished = canonicalForms.isNotEmpty
            ? _resolveGroupResultDisplayFromForms(
                canonicalForms: canonicalForms,
                viewerUserId: viewerUserId,
              ).isPublished
            : (item.submittedGroup?.resultPublishedAt != null);

        if (sectionKind == _HistorySectionKind.waiting && resolvedPublished) {
          return const SizedBox.shrink();
        }
        if (sectionKind == _HistorySectionKind.history && !resolvedPublished) {
          return const SizedBox.shrink();
        }
        return child;
      },
    );
  }
}

class _FormsSummaryTile extends StatefulWidget {
  const _FormsSummaryTile({
    required this.viewerUserId,
    required this.item,
    required this.dismissGeneration,
    required this.hideStatusChip,
    required this.onTap,
    required this.onDelete,
  });

  final String viewerUserId;
  final _FormsListItem item;
  final int dismissGeneration;
  final bool hideStatusChip;
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
    final Color baseCardColor = _historyCardBackgroundColor(context);
    final Color titleColor = _historyCardTitleColor(context);
    final Color secondaryColor = _historyCardSecondaryTextColor(context);
    final Color mutedColor = _historyCardMutedTextColor(context);

    final Widget tile = Material(
      color: baseCardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: visualState.accentColor.withValues(alpha: 0.28),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 14),
          child: Stack(
            children: [
              PositionedDirectional(
                top: -14,
                bottom: -14,
                end: -16,
                child: Container(
                  width: 7,
                  decoration: BoxDecoration(
                    color: visualState.accentColor.withValues(alpha: 0.92),
                    borderRadius: const BorderRadiusDirectional.only(
                      topEnd: Radius.circular(18),
                      bottomEnd: Radius.circular(18),
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
                              if (!widget.hideStatusChip) ...[
                                _HistoryResultChip(
                                  label: visualState.chipLabel,
                                  color: visualState.accentColor,
                                ),
                                const SizedBox(width: 10),
                              ],
                              Expanded(
                                child: Text(
                                  _titleText(),
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: titleColor,
                                    fontSize: 18,
                                    height: 1.15,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
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
                          color: mutedColor,
                          tooltip: 'ביטול טיוטה קבוצתית',
                          visualDensity: VisualDensity.compact,
                        ),
                      Padding(
                        padding: const EdgeInsetsDirectional.only(top: 2),
                        child: Icon(
                          Icons.chevron_left,
                          color: secondaryColor,
                        ),
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
      child: _HistoryCompactDetails(
        rows: _subtitleRows(),
      ),
    );
  }

  String _titleText() {
    switch (widget.item.kind) {
      case _FormsItemKind.personalSubmitted:
        return 'טופס אישי';
      case _FormsItemKind.personalDraft:
        return 'טופס אישי · טיוטה';
      case _FormsItemKind.personalSubmissionBundle:
        return 'שליחת טפסים אישיים';
      case _FormsItemKind.groupSubmitted:
        return widget.item.submittedGroup!.groupName;
      case _FormsItemKind.groupDraft:
        return '${widget.item.activeGroup!.groupName} · בהקמה';
      case _FormsItemKind.groupCancelled:
        return widget.item.cancelledGroup!.groupName;
    }
  }

  List<_HistoryRowData> _subtitleRows() {
    switch (widget.item.kind) {
      case _FormsItemKind.personalSubmitted:
        final LotteryForm form = widget.item.personalForm!;
        final DateTime? safeDrawDate =
            _coerceSafeDrawDate(form.salesCloseAt, form.submittedAt);
        return <_HistoryRowData>[
          _HistoryRowData(
            label: 'מס׳ הגרלה',
            value: form.lotteryId?.toString() ?? '—',
          ),
          _HistoryRowData(
            label: 'תאריך הגרלה',
            value: _formatDate(safeDrawDate),
          ),
          _HistoryRowData(
            label: 'עלות',
            value: '${_ticketCost(form)} ש״ח',
            emphasize: true,
          ),
          _HistoryRowData(
            label: 'זכייה',
            value: _personalWinningStatusLabel(form),
            emphasize: true,
          ),
          _HistoryRowData(
            label: 'נשלח',
            value: _formatDate(form.submittedAt ?? form.updatedAt),
          ),
        ];
      case _FormsItemKind.personalDraft:
        final LotteryForm form = widget.item.personalForm!;
        return <_HistoryRowData>[
          _HistoryRowData(
            label: 'עלות',
            value: '${_ticketCost(form)} ש״ח',
            emphasize: true,
          ),
          _HistoryRowData(
            label: 'נוצר',
            value: _formatDate(
              form.createdAt ?? form.savedAt ?? form.updatedAt,
            ),
          ),
        ];
      case _FormsItemKind.personalSubmissionBundle:
        final PersonalSubmittedBundle bundle =
            widget.item.personalSubmissionBundle!;
        return <_HistoryRowData>[
          _HistoryRowData(
            label: 'מס׳ הגרלה',
            value: _bundleLotteryIdLabel(bundle),
          ),
          _HistoryRowData(
            label: 'תאריך הגרלה',
            value: _formatDate(_bundleLotteryDate(bundle)),
          ),
          _HistoryRowData(
            label: 'מספר טפסים',
            value: '${bundle.formCount}',
          ),
          _HistoryRowData(
            label: 'עלות כוללת',
            value: '${bundle.totalCost} ש״ח',
            emphasize: true,
          ),
          _HistoryRowData(
            label: 'זכייה',
            value: _bundleWinningStatusLabel(bundle),
            emphasize: true,
          ),
          _HistoryRowData(
            label: 'נשלח',
            value: _formatDate(bundle.submittedAt),
          ),
        ];
      case _FormsItemKind.groupSubmitted:
      case _FormsItemKind.groupDraft:
      case _FormsItemKind.groupCancelled:
        return const <_HistoryRowData>[];
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _historyChipBackgroundColor(context),
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

class _HistoryRowData {
  const _HistoryRowData({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;
}

class _HistoryCompactDetails extends StatelessWidget {
  const _HistoryCompactDetails({
    required this.rows,
  });

  final List<_HistoryRowData> rows;

  @override
  Widget build(BuildContext context) {
    final List<_HistoryRowData> visibleRows = rows
        .where((row) => row.value.trim().isNotEmpty)
        .toList();
    final Color dividerColor = _historyCardDividerColor(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List<Widget>.generate(visibleRows.length, (int index) {
        final _HistoryRowData row = visibleRows[index];
        return Padding(
          padding: EdgeInsets.only(bottom: index == visibleRows.length - 1 ? 0 : 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _HistoryDetailRow(row: row),
              if (index != visibleRows.length - 1) ...<Widget>[
                const SizedBox(height: 8),
                Divider(height: 1, thickness: 1, color: dividerColor),
              ],
            ],
          ),
        );
      }),
    );
  }
}

class _HistoryDetailRow extends StatelessWidget {
  const _HistoryDetailRow({
    required this.row,
  });

  final _HistoryRowData row;

  @override
  Widget build(BuildContext context) {
    final TextStyle? labelStyle = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(
          color: _historyCardMutedTextColor(context),
          fontWeight: FontWeight.w700,
          height: 1.28,
        );
    final TextStyle? valueStyle = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(
          color: row.emphasize
              ? _historyCardTitleColor(context)
              : _historyCardSecondaryTextColor(context),
          fontWeight: row.emphasize ? FontWeight.w800 : FontWeight.w600,
          height: 1.28,
        );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        textDirection: TextDirection.rtl,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Flexible(
            flex: 8,
            child: Text(
              '${row.label}:',
              textAlign: TextAlign.right,
              softWrap: true,
              textDirection: TextDirection.rtl,
              style: labelStyle,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 11,
            child: Text(
              row.value,
              textAlign: TextAlign.right,
              softWrap: true,
              textDirection: TextDirection.rtl,
              style: valueStyle,
            ),
          ),
        ],
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
      return const _HistoryCardVisualState(
        accentColor: Color(0xFFBDBDBD),
        chipLabel: 'טיוטה',
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
      final bool isPublished = group.resultPublishedAt != null;
      return _buildHistoryCardVisualState(
        isPublished: isPublished,
        winAmount: _firstNumericValue(
          <dynamic>[
            group.myWinningAmount,
            group.groupWinningAmount,
          ],
        ),
        explicitChipLabel: isPublished ? null : 'מעבד תוצאות',
      );
    case _FormsItemKind.groupDraft:
      return const _HistoryCardVisualState(
        accentColor: Color(0xFFBDBDBD),
        chipLabel: 'בהקמה',
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
  String? explicitChipLabel,
}) {
  return _HistoryCardVisualState(
    accentColor: getCardBorderColor(isPublished, winAmount),
    chipLabel: explicitChipLabel ?? getResultChipLabel(isPublished, winAmount),
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

bool _isHistoryDark(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark;
}

Color _historyCardBackgroundColor(BuildContext context) {
  return _isHistoryDark(context) ? _historyDarkCard : _historyLightCard;
}

Color _historyCardTitleColor(BuildContext context) {
  return _isHistoryDark(context)
      ? _historyDarkTextPrimary
      : _historyLightTextPrimary;
}

Color _historyCardSecondaryTextColor(BuildContext context) {
  return _isHistoryDark(context)
      ? _historyDarkTextSecondary
      : _historyLightTextSecondary;
}

Color _historyCardMutedTextColor(BuildContext context) {
  return _isHistoryDark(context)
      ? _historyDarkTextMuted
      : _historyLightTextMuted;
}

Color _historyCardDividerColor(BuildContext context) {
  return _isHistoryDark(context)
      ? Colors.white.withValues(alpha: 0.08)
      : _historyLightCardEdge;
}

Color _historyChipBackgroundColor(BuildContext context) {
  return _isHistoryDark(context)
      ? Colors.black.withValues(alpha: 0.18)
      : Colors.white.withValues(alpha: 0.9);
}

Color _historyTabShellColor(BuildContext context) {
  return _isHistoryDark(context)
      ? _historyDarkCard.withValues(alpha: 0.94)
      : const Color(0xFFF4E8EC);
}

Color _historyTabShellBorderColor(BuildContext context) {
  return _isHistoryDark(context)
      ? Colors.white.withValues(alpha: 0.08)
      : _historyLightCardEdge;
}

Color _historyTabIndicatorColor(BuildContext context) {
  return _isHistoryDark(context)
      ? _historyDarkCardEdge.withValues(alpha: 0.9)
      : Colors.white;
}

Color _historyTabIndicatorBorderColor(BuildContext context) {
  return _isHistoryDark(context)
      ? Colors.white.withValues(alpha: 0.08)
      : _historyLightCardEdge;
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
      return _HistoryCompactDetails(
        rows: _fallbackRows(),
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
              return _HistoryCompactDetails(
                rows: _resolvedRows(
                  meta: directMeta,
                  resultDisplay: resultDisplay,
                  createdAt: createdAt,
                  submittedAt: submittedAt,
                ),
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
                  return _HistoryCompactDetails(
                    rows: _resolvedRows(
                      meta: metaSnapshot.data ?? const _GroupHistoryFormMeta(),
                      resultDisplay: resultDisplay,
                      createdAt: createdAt,
                      submittedAt: submittedAt,
                    ),
                  );
                },
              );
            }

            return _HistoryCompactDetails(
              rows: _resolvedRows(
                meta: const _GroupHistoryFormMeta(),
                resultDisplay: resultDisplay,
                createdAt: createdAt,
                submittedAt: submittedAt,
              ),
            );
          },
        );
      },
    );
  }

  List<_HistoryRowData> _resolvedRows({
    required _GroupHistoryFormMeta meta,
    required _GroupResultDisplay resultDisplay,
    required DateTime? createdAt,
    required DateTime? submittedAt,
  }) {
    if (item.kind == _FormsItemKind.groupSubmitted) {
      return _submittedRows(
        submittedAt: submittedAt,
        meta: meta,
        resultDisplay: resultDisplay,
      );
    }
    if (item.kind == _FormsItemKind.groupCancelled) {
      return _cancelledRows(meta: meta);
    }
    return _draftRows(
      createdAt: createdAt,
      meta: meta,
    );
  }

  List<_HistoryRowData> _submittedRows({
    required DateTime? submittedAt,
    required _GroupHistoryFormMeta meta,
    required _GroupResultDisplay resultDisplay,
  }) {
    final SubmittedGroupHistoryItem group = item.submittedGroup!;

    return <_HistoryRowData>[
      _HistoryRowData(label: 'מס׳ הגרלה', value: meta.lotteryIdLabel ?? '—'),
      _HistoryRowData(
        label: 'תאריך הגרלה',
        value: formatPresentationDateTime(meta.lotteryDate),
      ),
      _HistoryRowData(label: 'נוצר על ידי', value: group.creatorName),
      _HistoryRowData(
        label: 'העלות שלי',
        value: '${group.myEffectiveShare} ש״ח',
        emphasize: true,
      ),
      _HistoryRowData(
        label: 'זכייה קבוצתית',
        value: resultDisplay.groupLabel,
        emphasize: true,
      ),
      _HistoryRowData(
        label: 'הזכייה שלי',
        value: resultDisplay.myLabel,
        emphasize: true,
      ),
      _HistoryRowData(
        label: 'נשלח',
        value: formatPresentationDateTime(submittedAt ?? group.submittedAt),
      ),
    ];
  }

  List<_HistoryRowData> _draftRows({
    required DateTime? createdAt,
    required _GroupHistoryFormMeta meta,
  }) {
    if (item.kind == _FormsItemKind.groupDraft) {
      final UserGroupListItem group = item.activeGroup!;
      return <_HistoryRowData>[
        _HistoryRowData(label: 'מס׳ הגרלה', value: meta.lotteryIdLabel ?? '—'),
        _HistoryRowData(
          label: 'תאריך הגרלה',
          value: formatPresentationDateTime(meta.lotteryDate),
        ),
        _HistoryRowData(
          label: 'נוצר על ידי',
          value: group.creatorName ?? group.creatorUserId,
        ),
        _HistoryRowData(
          label: 'עלות שלי',
          value: _draftGroupCostLabel(group),
          emphasize: true,
        ),
        _HistoryRowData(
          label: 'מצב תגובה',
          value: _responseStatusLabel(group.responseStatus),
        ),
        _HistoryRowData(
          label: 'נוצר',
          value: formatPresentationDateTime(createdAt ?? group.updatedAt),
        ),
      ];
    }

    return _fallbackRows();
  }

  List<_HistoryRowData> _cancelledRows({
    required _GroupHistoryFormMeta meta,
  }) {
    final CancelledGroupHistoryItem group = item.cancelledGroup!;
    return <_HistoryRowData>[
      _HistoryRowData(label: 'מס׳ הגרלה', value: meta.lotteryIdLabel ?? '—'),
      _HistoryRowData(
        label: 'תאריך הגרלה',
        value: formatPresentationDateTime(meta.lotteryDate),
      ),
      _HistoryRowData(label: 'נוצר על ידי', value: group.creatorName),
      _HistoryRowData(
        label: 'בוטל על ידי',
        value: group.cancelledByDisplayName,
      ),
      _HistoryRowData(
        label: 'מועד ביטול',
        value: formatPresentationDateTime(group.cancelledAt),
      ),
      _HistoryRowData(
        label: 'זיכוי לארנק',
        value: '${group.myRefundAmount} ש״ח',
        emphasize: true,
      ),
    ];
  }

  List<_HistoryRowData> _fallbackRows() {
    if (item.kind == _FormsItemKind.groupSubmitted) {
      final SubmittedGroupHistoryItem group = item.submittedGroup!;
      return <_HistoryRowData>[
        _HistoryRowData(label: 'מס׳ הגרלה', value: '—'),
        const _HistoryRowData(label: 'תאריך הגרלה', value: 'ללא תאריך'),
        _HistoryRowData(label: 'נוצר על ידי', value: group.creatorName),
        _HistoryRowData(
          label: 'העלות שלי',
          value: '${group.myEffectiveShare} ש״ח',
          emphasize: true,
        ),
        const _HistoryRowData(
          label: 'הזכייה שלי',
          value: 'טרם פורסם',
          emphasize: true,
        ),
        _HistoryRowData(
          label: 'נשלח',
          value: formatPresentationDateTime(group.submittedAt),
        ),
      ];
    }

    if (item.kind == _FormsItemKind.groupCancelled) {
      return _cancelledRows(meta: const _GroupHistoryFormMeta());
    }

    final UserGroupListItem group = item.activeGroup!;
    return <_HistoryRowData>[
      _HistoryRowData(label: 'מס׳ הגרלה', value: '—'),
      const _HistoryRowData(label: 'תאריך הגרלה', value: 'ללא תאריך'),
      _HistoryRowData(
        label: 'נוצר על ידי',
        value: group.creatorName ?? group.creatorUserId,
      ),
      _HistoryRowData(
        label: 'עלות שלי',
        value: _draftGroupCostLabel(group),
        emphasize: true,
      ),
      _HistoryRowData(
        label: 'מצב תגובה',
        value: _responseStatusLabel(group.responseStatus),
      ),
      _HistoryRowData(
        label: 'נוצר',
        value: formatPresentationDateTime(group.updatedAt),
      ),
    ];
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
