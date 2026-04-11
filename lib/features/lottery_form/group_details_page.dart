import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../form_presentation_utils.dart';
import '../../models/lottery_group.dart';
import '../../models/lottery_group_membership.dart';
import '../../repositories/lottery_group_repository.dart';
import '../../services/group_invite_link_service.dart';
import 'lottery_ticket_preview.dart';

class GroupDetailsPage extends StatefulWidget {
  const GroupDetailsPage({
    super.key,
    required this.groupId,
    required this.currentUserId,
    required this.inviteLinkService,
    required this.repository,
  });

  final String groupId;
  final String currentUserId;
  final GroupInviteLinkService inviteLinkService;
  final LotteryGroupRepository repository;

  @override
  State<GroupDetailsPage> createState() => _GroupDetailsPageState();
}

class _GroupDetailsPageState extends State<GroupDetailsPage> {
  final TextEditingController _minimumController = TextEditingController();
  LotteryGroupResponseStatus _selectedStatus =
      LotteryGroupResponseStatus.undecided;
  String? _editingMembershipUserId;
  bool _isSaving = false;
  bool _isFinalizing = false;
  bool _isPaying = false;
  bool _isSubmitting = false;
  bool _isUpdatingDispatch = false;
  bool _showDebug = false;

  @override
  void dispose() {
    _minimumController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('קבוצת לוטו'),
        actions: [
          IconButton(
            onPressed: () {
              setState(() => _showDebug = !_showDebug);
            },
            icon:
                Icon(_showDebug ? Icons.bug_report : Icons.bug_report_outlined),
            tooltip: 'מצב דיבאג',
          ),
        ],
      ),
      body: StreamBuilder<LotteryGroup>(
        stream: widget.repository.watchGroup(
          groupId: widget.groupId,
          userId: widget.currentUserId,
        ),
        builder: (context, groupSnapshot) {
          if (groupSnapshot.hasError) {
            return _CenteredMessage(message: '${groupSnapshot.error}');
          }
          if (!groupSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final LotteryGroup group = groupSnapshot.data!;
          final bool isCreator = group.creatorUserId == widget.currentUserId;

          return StreamBuilder<List<LotteryGroupMembership>>(
            stream: widget.repository.watchMemberships(
              groupId: group.groupId,
              userId: widget.currentUserId,
            ),
            builder: (context, membershipsSnapshot) {
              if (membershipsSnapshot.hasError) {
                return _CenteredMessage(
                    message: '${membershipsSnapshot.error}');
              }
              if (!membershipsSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final List<LotteryGroupMembership> memberships =
                  membershipsSnapshot.data!;
              final String currentUserDisplayName = _currentUserDisplayName();
              final LotteryGroupMembership? myMembership =
                  _findMyMembership(memberships);
              _syncEditorFromMembership(myMembership);
              if (myMembership != null) {
                widget.repository.upsertActiveGroupSummary(
                  userId: widget.currentUserId,
                  group: group,
                  membership: myMembership,
                );
              }

              final int interestedCount = memberships
                  .where(
                    (membership) =>
                        membership.responseStatus ==
                        LotteryGroupResponseStatus.interested,
                  )
                  .length;
              final int finalizableCount = memberships
                  .where(
                    (membership) =>
                        membership.responseStatus ==
                            LotteryGroupResponseStatus.interested &&
                        interestedCount >=
                            membership.minimumParticipantsRequired,
                  )
                  .length;
              final List<LotteryGroupMembership> lockedInMemberships =
                  memberships
                      .where((membership) => membership.lockedIn)
                      .toList();
              final List<LotteryGroupMembership> paidLockedInMemberships =
                  lockedInMemberships
                      .where(
                        (membership) =>
                            membership.paymentStatus ==
                            LotteryGroupPaymentStatus.paid,
                      )
                      .toList();
              final int paidCount = paidLockedInMemberships.length;
              final List<LotteryGroupMembership> validPaidMemberships =
                  _computeStableValidMemberships(paidLockedInMemberships);
              final bool paidParticipantSetIsValid =
                  validPaidMemberships.isNotEmpty;
              final num? paidSetPerParticipantCost = paidParticipantSetIsValid
                  ? group.baseTicketCost / validPaidMemberships.length
                  : null;
              final String paymentReadinessMessage = paidParticipantSetIsValid
                  ? 'אפשר כבר להגיש לפי המשתתפים ששילמו כרגע'
                  : 'ממתין לתשלומים נוספים כדי לאפשר הגשה';
              final bool currentUserCanSimulatePayment = myMembership != null &&
                  myMembership.lockedIn &&
                  group.status != LotteryGroupStatus.submitted &&
                  myMembership.paymentStatus ==
                      LotteryGroupPaymentStatus.unpaid;
              final num? estimatedPerParticipantCost = interestedCount > 0
                  ? group.baseTicketCost / interestedCount
                  : null;
              final bool canEditResponse =
                  group.status == LotteryGroupStatus.collectingResponses;
              final bool canFinalize = isCreator &&
                  !_isFinalizing &&
                  group.status == LotteryGroupStatus.collectingResponses &&
                  finalizableCount > 0;
              final bool canSubmit = isCreator &&
                  !_isSubmitting &&
                  group.status != LotteryGroupStatus.submitted &&
                  group.status != LotteryGroupStatus.collectingResponses &&
                  validPaidMemberships.isNotEmpty;
              final String creatorDisplayName = _creatorDisplayName(
                memberships: memberships,
                creatorUserId: group.creatorUserId,
                currentUserDisplayName: currentUserDisplayName,
              );
              final String groupStatusLabel = _groupStatusLabel(
                group: group,
                paidParticipantSetIsValid: paidParticipantSetIsValid,
              );
              final String yourShareLabel = myMembership == null
                  ? 'עדיין לא הצטרפת לקבוצה'
                  : _displayShareForMembership(
                            group: group,
                            membership: myMembership,
                          ) !=
                          null
                      ? '${_displayShareForMembership(group: group, membership: myMembership)} ש״ח'
                      : (group.status == LotteryGroupStatus.submitted
                          ? 'לא השתתפת בהגשה הסופית'
                          : 'לא נקבע חלק לתשלום כרגע');
              final String currentCostIfSubmittedNowLabel =
                  paidSetPerParticipantCost == null
                      ? 'עדיין אין קבוצת משלמים תקפה'
                      : '$paidSetPerParticipantCost ש״ח';
              final String submissionMessage;
              if (group.status == LotteryGroupStatus.submitted) {
                submissionMessage = _dispatchStatusDescription(
                  dispatchStatus: group.dispatchStatus,
                  printReadyUrl: group.printReadyUrl,
                );
              } else if (paidParticipantSetIsValid) {
                submissionMessage =
                    'ניתן כבר לשלוח לפי המשלמים הנוכחיים. אם שולחים עכשיו, כל משלם ישלם $currentCostIfSubmittedNowLabel.';
              } else {
                submissionMessage =
                    'ממתינים לתשלומים נוספים לפני שניתן יהיה לשלוח את הטופס.';
              }
              final bool showInviteButton = isCreator &&
                  group.status == LotteryGroupStatus.collectingResponses;
              final bool showFinalizeButton = isCreator &&
                  group.status == LotteryGroupStatus.collectingResponses;
              final bool showSubmitButton = isCreator &&
                  group.status != LotteryGroupStatus.submitted &&
                  group.status != LotteryGroupStatus.collectingResponses;
              final bool showPrintedButton = isCreator &&
                  group.status == LotteryGroupStatus.submitted &&
                  group.dispatchStatus ==
                      LotteryGroupRepository.dispatchStatusQueuedForPrint;
              final bool showSubmittedToStationButton = isCreator &&
                  group.status == LotteryGroupStatus.submitted &&
                  group.dispatchStatus ==
                      LotteryGroupRepository.dispatchStatusPrinted;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _GroupHeaderCard(
                    groupName: group.groupName,
                    creatorDisplayName: creatorDisplayName,
                    statusLabel: groupStatusLabel,
                  ),
                  const SizedBox(height: 12),
                  LotteryTicketPreviewCard(
                    filledTablesCount: group.populatedTableCount,
                    baseTicketCost: group.baseTicketCost,
                    isFullTicket: group.isComplete,
                    actionLabel: group.status == LotteryGroupStatus.submitted &&
                            (group.printReadyUrl?.isNotEmpty ?? false)
                        ? 'צפה בקובץ להדפסה'
                        : 'צפה בטופס',
                    onOpenFullScreen: () => _openPrimaryTicketView(group),
                  ),
                  const SizedBox(height: 12),
                  _GroupOutcomeCard(
                    group: group,
                    currentUserId: widget.currentUserId,
                    creatorDisplayName: creatorDisplayName,
                  ),
                  const SizedBox(height: 12),
                  _CompactSummaryCard(
                    filledTablesCount: group.populatedTableCount,
                    paidCount: paidCount,
                    yourShareLabel: yourShareLabel,
                  ),
                  const SizedBox(height: 12),
                  _StatusBanner(message: submissionMessage),
                  const SizedBox(height: 12),
                  _ActionBarCard(
                    showInviteButton: showInviteButton,
                    onInvite: showInviteButton
                        ? (buttonContext) => _shareInvite(
                              buttonContext: buttonContext,
                              group: group,
                            )
                        : null,
                    showFinalizeButton: showFinalizeButton,
                    canFinalize: canFinalize,
                    isFinalizing: _isFinalizing,
                    onFinalize: () => _finalizeGroup(group.groupId),
                    showSubmitButton: showSubmitButton,
                    canSubmit: canSubmit,
                    isSubmitting: _isSubmitting,
                    onSubmit: () => _submitGroup(groupId: group.groupId),
                    showPrintedButton: showPrintedButton,
                    showSubmittedToStationButton: showSubmittedToStationButton,
                    isUpdatingDispatch: _isUpdatingDispatch,
                    onMarkPrinted: () => _updateDispatchStatus(
                      groupId: group.groupId,
                      dispatchStatus:
                          LotteryGroupRepository.dispatchStatusPrinted,
                    ),
                    onMarkSubmittedToStation: () => _updateDispatchStatus(
                      groupId: group.groupId,
                      dispatchStatus: LotteryGroupRepository
                          .dispatchStatusSubmittedToStation,
                    ),
                    showPayButton: currentUserCanSimulatePayment,
                    isPaying: _isPaying,
                    onSimulatePayment: () =>
                        _simulatePayment(groupId: group.groupId),
                  ),
                  const SizedBox(height: 12),
                  _ParticipantsCard(
                    memberships: memberships,
                    group: group,
                    currentUserId: widget.currentUserId,
                    currentUserDisplayName: currentUserDisplayName,
                    creatorUserId: group.creatorUserId,
                    showDebug: _showDebug,
                  ),
                  if (canEditResponse) ...[
                    const SizedBox(height: 12),
                    _MyResponseCard(
                      membership: myMembership,
                      group: group,
                      canEdit: canEditResponse,
                      selectedStatus: _selectedStatus,
                      minimumController: _minimumController,
                      isSaving: _isSaving,
                      onStatusChanged: (status) {
                        setState(() => _selectedStatus = status);
                      },
                      onSave: myMembership == null
                          ? null
                          : () => _saveMyResponse(groupId: group.groupId),
                      onSimulatePayment: null,
                      isPaying: _isPaying,
                      showDebug: _showDebug,
                    ),
                  ],
                  if (_showDebug) ...[
                    const SizedBox(height: 12),
                    _InfoCard(
                      title: 'Debug',
                      rows: [
                        _InfoRow(label: 'groupId', value: group.groupId),
                        _InfoRow(
                          label: 'creatorUserId',
                          value: group.creatorUserId,
                        ),
                        _InfoRow(
                          label: 'status(raw)',
                          value: group.status.value,
                        ),
                        _InfoRow(
                          label: 'מעוניינים(raw)',
                          value: '$interestedCount',
                        ),
                        _InfoRow(
                          label: 'יעברו finalize(raw)',
                          value: '$finalizableCount',
                        ),
                        _InfoRow(
                          label: 'estimatedPerParticipantCost(raw)',
                          value: '${estimatedPerParticipantCost ?? 'null'}',
                        ),
                        _InfoRow(
                          label: 'paymentReadiness(raw)',
                          value: paymentReadinessMessage,
                        ),
                      ],
                    ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  LotteryGroupMembership? _findMyMembership(
    List<LotteryGroupMembership> memberships,
  ) {
    for (final LotteryGroupMembership membership in memberships) {
      if (membership.userId == widget.currentUserId) {
        return membership;
      }
    }
    return null;
  }

  void _syncEditorFromMembership(LotteryGroupMembership? membership) {
    if (membership == null) {
      return;
    }
    if (_editingMembershipUserId == membership.userId) {
      return;
    }

    _editingMembershipUserId = membership.userId;
    _selectedStatus = membership.responseStatus;
    _minimumController.text = membership.minimumParticipantsRequired.toString();
  }

  Future<void> _shareInvite({
    required BuildContext buttonContext,
    required LotteryGroup group,
  }) async {
    final Uri inviteUri = widget.inviteLinkService.buildInviteUri(
      groupId: group.groupId,
      inviteToken: group.inviteToken,
    );
    final RenderBox? box = buttonContext.findRenderObject() as RenderBox?;
    final Rect? origin =
        box == null ? null : box.localToGlobal(Offset.zero) & box.size;

    final String text = [
      'הצטרפו לקבוצת הלוטו שלי: ${group.groupName}',
      inviteUri.toString(),
    ].join('\n');

    await SharePlus.instance.share(
      ShareParams(
        text: text,
        sharePositionOrigin: origin,
      ),
    );
  }

  Future<void> _saveMyResponse({
    required String groupId,
  }) async {
    final int? minimumParticipants =
        int.tryParse(_minimumController.text.trim());
    if (minimumParticipants == null || minimumParticipants < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('יש להזין מספר משתתפים מינימלי חוקי.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await widget.repository.updateMembershipResponse(
        groupId: groupId,
        userId: widget.currentUserId,
        responseStatus: _selectedStatus,
        minimumParticipantsRequired: minimumParticipants,
      );

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('התגובה עודכנה בהצלחה.')),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('עדכון התגובה נכשל.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _finalizeGroup(String groupId) async {
    setState(() => _isFinalizing = true);
    try {
      await widget.repository.finalizeGroup(
        groupId: groupId,
        creatorUserId: widget.currentUserId,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('הקבוצה עברה finalize בהצלחה.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _isFinalizing = false);
      }
    }
  }

  Future<void> _simulatePayment({
    required String groupId,
  }) async {
    setState(() => _isPaying = true);
    try {
      await widget.repository.simulatePayment(
        groupId: groupId,
        userId: widget.currentUserId,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('התשלום סומן כהושלם.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isPaying = false);
      }
    }
  }

  Future<void> _submitGroup({
    required String groupId,
  }) async {
    setState(() => _isSubmitting = true);
    try {
      final String submittedFormId = await widget.repository.submitGroupTicket(
        groupId: groupId,
        creatorUserId: widget.currentUserId,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('הטופס אושר ונכנס לתור שליחה. מזהה: $submittedFormId'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _updateDispatchStatus({
    required String groupId,
    required String dispatchStatus,
  }) async {
    setState(() => _isUpdatingDispatch = true);
    try {
      await widget.repository.updateSubmittedGroupDispatchStatus(
        groupId: groupId,
        creatorUserId: widget.currentUserId,
        dispatchStatus: dispatchStatus,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_dispatchStatusSnackMessage(dispatchStatus))),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingDispatch = false);
      }
    }
  }

  void _openGroupSnapshotPreview(LotteryGroup group) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LotteryTicketPreviewPage(
          title: 'תצוגת טופס: ${group.groupName}',
          subtitle: 'תצוגה לקריאה בלבד מתוך הטופס הקבוצתי הקפוא',
          tables: group.tables,
          showDebug: _showDebug,
        ),
      ),
    );
  }

  Future<void> _openPrimaryTicketView(LotteryGroup group) async {
    final String? printReadyUrl = group.printReadyUrl;
    if (group.status == LotteryGroupStatus.submitted &&
        printReadyUrl != null &&
        printReadyUrl.isNotEmpty) {
      final Uri uri = Uri.parse(printReadyUrl);
      final bool launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('פתיחת קובץ ההדפסה נכשלה.')),
        );
      }
      return;
    }
    _openGroupSnapshotPreview(group);
  }

  String _currentUserDisplayName() {
    final String? displayName = FirebaseAuth.instance.currentUser?.displayName;
    if (displayName != null && displayName.trim().isNotEmpty) {
      return displayName.trim();
    }
    return 'אני';
  }

  String _creatorDisplayName({
    required List<LotteryGroupMembership> memberships,
    required String creatorUserId,
    required String currentUserDisplayName,
  }) {
    for (final LotteryGroupMembership membership in memberships) {
      if (membership.userId == creatorUserId) {
        if (membership.displayName.trim().isNotEmpty) {
          return membership.userId == widget.currentUserId
              ? currentUserDisplayName
              : membership.displayName;
        }
      }
    }
    return creatorUserId == widget.currentUserId
        ? currentUserDisplayName
        : 'מנהל הקבוצה';
  }

  String _groupStatusLabel({
    required LotteryGroup group,
    required bool paidParticipantSetIsValid,
  }) {
    switch (group.status) {
      case LotteryGroupStatus.collectingResponses:
        return 'ממתינים לתגובות המשתתפים';
      case LotteryGroupStatus.awaitingPayments:
        return paidParticipantSetIsValid
            ? 'ממתינים לתשלומים נוספים, אבל כבר אפשר להגיש'
            : 'ממתינים לתשלומים';
      case LotteryGroupStatus.readyForSubmission:
        return 'מוכן להגשה';
      case LotteryGroupStatus.submitted:
        return _dispatchStatusLabel(group.dispatchStatus);
      case LotteryGroupStatus.cancelled:
        return 'הקבוצה בוטלה';
    }
  }

  String _dispatchStatusLabel(String? dispatchStatus) {
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

  String _dispatchStatusDescription({
    required String? dispatchStatus,
    required String? printReadyUrl,
  }) {
    switch (dispatchStatus) {
      case LotteryGroupRepository.dispatchStatusPrinted:
        return 'הטופס הודפס ומוכן למסירה לתחנה.';
      case LotteryGroupRepository.dispatchStatusSubmittedToStation:
        return 'הטופס נמסר לתחנה.';
      case LotteryGroupRepository.dispatchStatusQueuedForPrint:
      default:
        return (printReadyUrl?.isNotEmpty ?? false)
            ? 'קובץ ההדפסה מוכן. ממתין להדפסה.'
            : 'הטופס אושר ונכנס לתור שליחה. קובץ ההדפסה נוצר ויופיע כאן בקרוב.';
    }
  }

  String _dispatchStatusSnackMessage(String dispatchStatus) {
    switch (dispatchStatus) {
      case LotteryGroupRepository.dispatchStatusPrinted:
        return 'הטופס סומן כהודפס.';
      case LotteryGroupRepository.dispatchStatusSubmittedToStation:
        return 'הטופס סומן כנמסר לתחנה.';
      default:
        return 'מצב השליחה עודכן.';
    }
  }

  num? _displayShareForMembership({
    required LotteryGroup group,
    required LotteryGroupMembership membership,
  }) {
    if (group.status == LotteryGroupStatus.submitted) {
      if (membership.lockedIn &&
          membership.paymentStatus == LotteryGroupPaymentStatus.paid) {
        return group.currentPerParticipantCost;
      }
      return null;
    }
    return membership.costShare;
  }
}

List<LotteryGroupMembership> _computeStableValidMemberships(
  List<LotteryGroupMembership> memberships,
) {
  List<LotteryGroupMembership> current = List<LotteryGroupMembership>.from(
    memberships,
  );

  while (true) {
    final int participantCount = current.length;
    final List<LotteryGroupMembership> next = current
        .where(
          (membership) =>
              participantCount >= membership.minimumParticipantsRequired,
        )
        .toList();
    if (next.length == current.length) {
      return next;
    }
    current = next;
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.rows,
  });

  final String title;
  final List<_InfoRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 132,
                    child: Text(
                      row.label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(child: Text(row.value)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupHeaderCard extends StatelessWidget {
  const _GroupHeaderCard({
    required this.groupName,
    required this.creatorDisplayName,
    required this.statusLabel,
  });

  final String groupName;
  final String creatorDisplayName;
  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            groupName,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            'נוצר על ידי: $creatorDisplayName',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(statusLabel),
        ],
      ),
    );
  }
}

class _CompactSummaryCard extends StatelessWidget {
  const _CompactSummaryCard({
    required this.filledTablesCount,
    required this.paidCount,
    required this.yourShareLabel,
  });

  final int filledTablesCount;
  final int paidCount;
  final String yourShareLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: _CompactStat(
              label: 'טבלאות שמולאו',
              value: '$filledTablesCount',
            ),
          ),
          Expanded(
            child: _CompactStat(
              label: 'שילמו',
              value: '$paidCount',
            ),
          ),
          Expanded(
            child: _CompactStat(
              label: 'החלק שלך',
              value: yourShareLabel,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactStat extends StatelessWidget {
  const _CompactStat({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _GroupOutcomeCard extends StatelessWidget {
  const _GroupOutcomeCard({
    required this.group,
    required this.currentUserId,
    required this.creatorDisplayName,
  });

  final LotteryGroup group;
  final String currentUserId;
  final String creatorDisplayName;

  @override
  Widget build(BuildContext context) {
    final String? submittedFormId = group.submittedFormId;
    if (submittedFormId == null || submittedFormId.isEmpty) {
      return _InfoCard(
        title: 'פרטי הקבוצה',
        rows: [
          _InfoRow(label: 'שם קבוצה', value: group.groupName),
          _InfoRow(label: 'יוצר הקבוצה', value: creatorDisplayName),
          _InfoRow(
            label: 'עלות למשתתף',
            value: group.currentPerParticipantCost > 0
                ? '${group.currentPerParticipantCost} ש״ח'
                : 'ייקבע לאחר סגירת הקבוצה',
          ),
          _InfoRow(
            label: 'מועד יצירה',
            value: formatPresentationDateTime(group.createdAt),
          ),
          _InfoRow(
            label: 'מועד שליחה',
            value: formatPresentationDateTime(group.submittedAt),
          ),
        ],
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(group.creatorUserId)
          .collection('forms')
          .doc(submittedFormId)
          .snapshots(),
      builder: (context, snapshot) {
        final Map<String, dynamic> formData =
            snapshot.data?.data() ?? const <String, dynamic>{};
        final num totalWinnings = (formData['winAmount'] as num?) ?? 0;
        final num? myWinnings = extractMyWinningShare(
          winAllocations: formData['winAllocations'],
          userId: currentUserId,
        );

        return _InfoCard(
          title: 'פרטי הקבוצה',
          rows: [
            _InfoRow(label: 'שם קבוצה', value: group.groupName),
            _InfoRow(label: 'יוצר הקבוצה', value: creatorDisplayName),
            _InfoRow(
              label: 'עלות למשתתף',
              value: group.currentPerParticipantCost > 0
                  ? '${group.currentPerParticipantCost} ש״ח'
                  : 'לא זמין',
            ),
            _InfoRow(
              label: 'מועד שליחה',
              value: formatPresentationDateTime(
                group.submittedAt ??
                    presentationAsDateTime(formData['submittedAt']),
              ),
            ),
            _InfoRow(
              label: 'זכייה כוללת',
              value: totalWinnings > 0 ? '$totalWinnings ש״ח' : 'טרם פורסם',
            ),
            _InfoRow(
              label: 'הזכייה שלי',
              value: myWinnings != null ? '$myWinnings ש״ח' : 'טרם פורסם',
            ),
          ],
        );
      },
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _ActionBarCard extends StatelessWidget {
  const _ActionBarCard({
    required this.showInviteButton,
    required this.onInvite,
    required this.showFinalizeButton,
    required this.canFinalize,
    required this.isFinalizing,
    required this.onFinalize,
    required this.showSubmitButton,
    required this.canSubmit,
    required this.isSubmitting,
    required this.onSubmit,
    required this.showPrintedButton,
    required this.showSubmittedToStationButton,
    required this.isUpdatingDispatch,
    required this.onMarkPrinted,
    required this.onMarkSubmittedToStation,
    required this.showPayButton,
    required this.isPaying,
    required this.onSimulatePayment,
  });

  final bool showInviteButton;
  final void Function(BuildContext buttonContext)? onInvite;
  final bool showFinalizeButton;
  final bool canFinalize;
  final bool isFinalizing;
  final VoidCallback onFinalize;
  final bool showSubmitButton;
  final bool canSubmit;
  final bool isSubmitting;
  final VoidCallback onSubmit;
  final bool showPrintedButton;
  final bool showSubmittedToStationButton;
  final bool isUpdatingDispatch;
  final VoidCallback onMarkPrinted;
  final VoidCallback onMarkSubmittedToStation;
  final bool showPayButton;
  final bool isPaying;
  final VoidCallback onSimulatePayment;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        if (showPayButton)
          FilledButton(
            onPressed: isPaying ? null : onSimulatePayment,
            child: isPaying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('סימון תשלום'),
          ),
        if (showFinalizeButton)
          FilledButton.icon(
            onPressed: canFinalize ? onFinalize : null,
            icon: const Icon(Icons.lock_clock_outlined),
            label: isFinalizing
                ? const Text('מבצע finalize...')
                : const Text('סיום בחירת משתתפים'),
          ),
        if (showSubmitButton)
          FilledButton.icon(
            onPressed: canSubmit ? onSubmit : null,
            icon: const Icon(Icons.send_outlined),
            label: isSubmitting
                ? const Text('מגיש טופס...')
                : const Text('הגש טופס קבוצתי'),
          ),
        if (showPrintedButton)
          OutlinedButton.icon(
            onPressed: isUpdatingDispatch ? null : onMarkPrinted,
            icon: const Icon(Icons.print_outlined),
            label: isUpdatingDispatch
                ? const Text('מעדכן...')
                : const Text('סמן כהודפס'),
          ),
        if (showSubmittedToStationButton)
          OutlinedButton.icon(
            onPressed: isUpdatingDispatch ? null : onMarkSubmittedToStation,
            icon: const Icon(Icons.store_outlined),
            label: isUpdatingDispatch
                ? const Text('מעדכן...')
                : const Text('סמן כנמסר לתחנה'),
          ),
        if (showInviteButton && onInvite != null)
          Builder(
            builder: (buttonContext) => OutlinedButton.icon(
              onPressed: () => onInvite!(buttonContext),
              icon: const Icon(Icons.share_outlined),
              label: const Text('הזמנה דרך WhatsApp'),
            ),
          ),
      ],
    );
  }
}

class _InfoRow {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _MyResponseCard extends StatelessWidget {
  const _MyResponseCard({
    required this.membership,
    required this.group,
    required this.canEdit,
    required this.selectedStatus,
    required this.minimumController,
    required this.isSaving,
    required this.isPaying,
    required this.onStatusChanged,
    required this.onSave,
    required this.onSimulatePayment,
    required this.showDebug,
  });

  final LotteryGroupMembership? membership;
  final LotteryGroup group;
  final bool canEdit;
  final LotteryGroupResponseStatus selectedStatus;
  final TextEditingController minimumController;
  final bool isSaving;
  final bool isPaying;
  final ValueChanged<LotteryGroupResponseStatus> onStatusChanged;
  final VoidCallback? onSave;
  final VoidCallback? onSimulatePayment;
  final bool showDebug;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'התגובה שלי',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          if (membership == null)
            const Text('אין membership פעיל למשתמש זה.')
          else ...[
            Text(_myMembershipHeadline(membership!)),
            if (_displayShareForMembership(group, membership!) != null)
              Text(
                'החלק שלך: ${_displayShareForMembership(group, membership!)} ש״ח',
              ),
            if (showDebug) ...[
              const SizedBox(height: 8),
              Text('lockedIn: ${membership!.lockedIn}'),
              Text('paymentStatus: ${membership!.paymentStatus.value}'),
              Text('costShare: ${membership!.costShare ?? 0}'),
            ],
            const SizedBox(height: 12),
            if (membership!.lockedIn &&
                membership!.paymentStatus ==
                    LotteryGroupPaymentStatus.unpaid) ...[
              FilledButton(
                onPressed: isPaying ? null : onSimulatePayment,
                child: isPaying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('סימון תשלום'),
              ),
              const SizedBox(height: 12),
            ] else if (membership!.paymentStatus ==
                LotteryGroupPaymentStatus.paid) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'שולם',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (!canEdit) ...[
              Text(
                'הקבוצה עברה finalize ולכן התגובה נעולה לעריכה.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
            ],
            SegmentedButton<LotteryGroupResponseStatus>(
              segments: const [
                ButtonSegment(
                  value: LotteryGroupResponseStatus.interested,
                  label: Text('מעוניין'),
                ),
                ButtonSegment(
                  value: LotteryGroupResponseStatus.notInterested,
                  label: Text('לא מעוניין'),
                ),
                ButtonSegment(
                  value: LotteryGroupResponseStatus.undecided,
                  label: Text('לא החלטתי'),
                ),
              ],
              selected: <LotteryGroupResponseStatus>{selectedStatus},
              onSelectionChanged: canEdit
                  ? (selection) {
                      onStatusChanged(selection.first);
                    }
                  : null,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: minimumController,
              enabled: canEdit,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'מינימום משתתפים נדרש',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: (!canEdit || isSaving) ? null : onSave,
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('עדכון תגובה'),
            ),
          ],
        ],
      ),
    );
  }

  String _myMembershipHeadline(LotteryGroupMembership membership) {
    if (group.status == LotteryGroupStatus.submitted &&
        (!membership.lockedIn ||
            membership.paymentStatus != LotteryGroupPaymentStatus.paid)) {
      return 'לא השתתפת בהגשה הסופית של הטופס.';
    }
    if (membership.paymentStatus == LotteryGroupPaymentStatus.paid) {
      return 'שילמת את חלקך בקבוצה.';
    }
    if (membership.lockedIn &&
        membership.paymentStatus == LotteryGroupPaymentStatus.unpaid) {
      return 'נבחרת להשתתף וממתינים לתשלום שלך.';
    }
    if (membership.responseStatus == LotteryGroupResponseStatus.interested) {
      return 'הבעת עניין, וממתינים לאישור הסופי של הקבוצה.';
    }
    return 'כרגע אינך משתתף בתשלום בקבוצה.';
  }

  num? _displayShareForMembership(
    LotteryGroup group,
    LotteryGroupMembership membership,
  ) {
    if (group.status == LotteryGroupStatus.submitted) {
      if (membership.lockedIn &&
          membership.paymentStatus == LotteryGroupPaymentStatus.paid) {
        return group.currentPerParticipantCost;
      }
      return null;
    }
    return membership.costShare;
  }
}

class _ParticipantsCard extends StatelessWidget {
  const _ParticipantsCard({
    required this.memberships,
    required this.group,
    required this.currentUserId,
    required this.currentUserDisplayName,
    required this.creatorUserId,
    required this.showDebug,
  });

  final List<LotteryGroupMembership> memberships;
  final LotteryGroup group;
  final String currentUserId;
  final String currentUserDisplayName;
  final String creatorUserId;
  final bool showDebug;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'משתתפים',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          ...memberships.map(
            (membership) {
              final int index = memberships.indexOf(membership);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _participantDisplayName(membership, index),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(_participantStatusLabel(membership)),
                      Text(
                        'נכנס במינימום משתתפים: ${membership.minimumParticipantsRequired}',
                      ),
                      if (_displayShareForMembership(membership) != null)
                        Text(
                          group.status == LotteryGroupStatus.submitted
                              ? 'חלק סופי בהגשה: ${_displayShareForMembership(membership)} ש״ח'
                              : 'חלק מתוכנן: ${_displayShareForMembership(membership)} ש״ח',
                        ),
                      if (showDebug) ...[
                        const SizedBox(height: 8),
                        Text('userId: ${membership.userId}'),
                        Text('displayName: ${membership.displayName}'),
                        Text(
                            'responseStatus: ${membership.responseStatus.value}'),
                        Text('lockedIn: ${membership.lockedIn}'),
                        Text(
                            'paymentStatus: ${membership.paymentStatus.value}'),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _participantDisplayName(LotteryGroupMembership membership, int index) {
    if (membership.displayName.trim().isNotEmpty) {
      return membership.displayName;
    }
    if (membership.userId == currentUserId) {
      return currentUserDisplayName;
    }
    if (membership.userId == creatorUserId) {
      return 'מנהל הקבוצה';
    }
    return 'משתתף ${index + 1}';
  }

  String _participantStatusLabel(LotteryGroupMembership membership) {
    if (group.status == LotteryGroupStatus.submitted) {
      if (membership.lockedIn &&
          membership.paymentStatus == LotteryGroupPaymentStatus.paid) {
        return 'השתתף בהגשה';
      }
      return 'לא השתתף בהגשה';
    }
    if (membership.paymentStatus == LotteryGroupPaymentStatus.paid) {
      return 'שילם';
    }
    if (membership.lockedIn &&
        membership.paymentStatus == LotteryGroupPaymentStatus.unpaid) {
      return 'ממתין לתשלום';
    }
    if (membership.responseStatus == LotteryGroupResponseStatus.interested) {
      return 'ממתין לאישור סופי';
    }
    return 'לא משתתף';
  }

  num? _displayShareForMembership(LotteryGroupMembership membership) {
    if (group.status == LotteryGroupStatus.submitted) {
      if (membership.lockedIn &&
          membership.paymentStatus == LotteryGroupPaymentStatus.paid) {
        return group.currentPerParticipantCost;
      }
      return null;
    }
    return membership.costShare;
  }
}
