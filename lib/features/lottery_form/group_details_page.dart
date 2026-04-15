import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../form_presentation_utils.dart';
import '../payments/payment_options_page.dart';
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
  bool _isCancelling = false;
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
              if (myMembership != null &&
                  group.status != LotteryGroupStatus.cancelled) {
                final LotteryGroupMembership? creatorMembership =
                    memberships.cast<LotteryGroupMembership?>().firstWhere(
                          (m) => m?.userId == group.creatorUserId,
                          orElse: () => null,
                        );
                widget.repository.upsertActiveGroupSummary(
                  userId: widget.currentUserId,
                  group: group,
                  membership: myMembership,
                  creatorName: creatorMembership?.displayName,
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
                  group.status != LotteryGroupStatus.cancelled &&
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
                  group.status != LotteryGroupStatus.cancelled &&
                  group.status != LotteryGroupStatus.collectingResponses &&
                  validPaidMemberships.isNotEmpty;
              final String creatorDisplayName = _creatorDisplayName(
                memberships: memberships,
                creatorUserId: group.creatorUserId,
                currentUserDisplayName: currentUserDisplayName,
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
              final bool showInviteButton = isCreator &&
                  group.status == LotteryGroupStatus.collectingResponses;
              final bool showFinalizeButton = isCreator &&
                  group.status == LotteryGroupStatus.collectingResponses;
              final bool showSubmitButton = isCreator &&
                  group.status != LotteryGroupStatus.submitted &&
                  group.status != LotteryGroupStatus.cancelled &&
                  group.status != LotteryGroupStatus.collectingResponses;
              final bool showCancelButton = isCreator &&
                  group.status != LotteryGroupStatus.submitted &&
                  group.status != LotteryGroupStatus.cancelled;
              return _buildSubmittedFormAwareContent(
                group: group,
                creatorDisplayName: creatorDisplayName,
                paidParticipantSetIsValid: paidParticipantSetIsValid,
                currentCostIfSubmittedNowLabel: currentCostIfSubmittedNowLabel,
                showInviteButton: showInviteButton,
                showFinalizeButton: showFinalizeButton,
                canFinalize: canFinalize,
                showSubmitButton: showSubmitButton,
                canSubmit: canSubmit,
                showCancelButton: showCancelButton,
                currentUserCanSimulatePayment: currentUserCanSimulatePayment,
                myMembership: myMembership,
                memberships: memberships,
                canEditResponse: canEditResponse,
                interestedCount: interestedCount,
                finalizableCount: finalizableCount,
                estimatedPerParticipantCost: estimatedPerParticipantCost,
                paymentReadinessMessage: paymentReadinessMessage,
                yourShareLabel: yourShareLabel,
                paidCount: paidCount,
                currentUserDisplayName: currentUserDisplayName,
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

  Future<void> _openPaymentFlow({
    required LotteryGroup group,
    required LotteryGroupMembership membership,
  }) async {
    final num payableAmount = membership.costShare ?? group.currentPerParticipantCost;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PaymentOptionsPage(
          userId: widget.currentUserId,
          amount: payableAmount,
          title: 'תשלום לקבוצה',
          onWalletPayment: () async {
            setState(() => _isPaying = true);
            try {
              await widget.repository.chargeUserWalletForGroup(
                groupId: group.groupId,
                userId: widget.currentUserId,
                amount: payableAmount,
              );
            } finally {
              if (mounted) {
                setState(() => _isPaying = false);
              }
            }
          },
          onExternalPayment: () async {
            setState(() => _isPaying = true);
            try {
              await widget.repository.simulatePayment(
                groupId: group.groupId,
                userId: widget.currentUserId,
              );
            } finally {
              if (mounted) {
                setState(() => _isPaying = false);
              }
            }
          },
        ),
      ),
    );
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

  Future<void> _confirmAndCancelGroup(LotteryGroup group) async {
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('ביטול טופס קבוצתי'),
            content: const Text(
              'האם אתה בטוח? רק מי שכבר שילם על הטופס יזוכה בארנק שלו.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('חזרה'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('אשר ביטול'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) {
      return;
    }

    setState(() => _isCancelling = true);
    try {
      await widget.repository.cancelGroupDraft(
        groupId: group.groupId,
        cancelledByUserId: widget.currentUserId,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('הטופס הקבוצתי בוטל בהצלחה.')),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isCancelling = false);
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

  Widget _buildTicketPreviewCard(LotteryGroup group) {
    final String actionLabel =
        group.status == LotteryGroupStatus.submitted &&
                (group.printReadyUrl?.isNotEmpty ?? false)
            ? 'צפה בקובץ להדפסה'
            : 'צפה בטופס';

    final String? submittedFormId = group.submittedFormId;
    if (submittedFormId == null || submittedFormId.isEmpty) {
      return LotteryTicketPreviewCard(
        filledTablesCount: group.populatedTableCount,
        baseTicketCost: group.baseTicketCost,
        isFullTicket: group.isComplete,
        actionLabel: actionLabel,
        onOpenFullScreen: () => _openPrimaryTicketView(group),
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
        final Map<String, dynamic> rawData =
            snapshot.data?.data() ?? const <String, dynamic>{};
        final String? receiptUrl = extractReceiptUrl(rawData);
        final bool hasReceipt = receiptUrl != null;

        return LotteryTicketPreviewCard(
          filledTablesCount: group.populatedTableCount,
          baseTicketCost: group.baseTicketCost,
          isFullTicket: group.isComplete,
          actionLabel: actionLabel,
          onOpenFullScreen: () => _openPrimaryTicketView(group),
          onSecondaryAction: hasReceipt
              ? () => _openReceiptUrl(receiptUrl)
              : null,
          secondaryActionLabel: hasReceipt ? 'צפה בקבלה' : null,
        );
      },
    );
  }

  Widget _buildProgressTracker(LotteryGroup group) {
    final String? submittedFormId = group.submittedFormId;
    if (submittedFormId == null || submittedFormId.isEmpty) {
      return _GroupTicketTracker(
        group: group,
        trackerFormState: const _GroupTrackerSubmittedFormState.empty(),
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
        final Map<String, dynamic> rawData =
            snapshot.data?.data() ?? const <String, dynamic>{};
        return _GroupTicketTracker(
          group: group,
          trackerFormState: _GroupTrackerSubmittedFormState.fromRawData(rawData),
        );
      },
    );
  }

  Widget _buildSubmittedFormAwareContent({
    required LotteryGroup group,
    required String creatorDisplayName,
    required bool paidParticipantSetIsValid,
    required String currentCostIfSubmittedNowLabel,
    required bool showInviteButton,
    required bool showFinalizeButton,
    required bool canFinalize,
    required bool showSubmitButton,
    required bool canSubmit,
    required bool showCancelButton,
    required bool currentUserCanSimulatePayment,
    required LotteryGroupMembership? myMembership,
    required List<LotteryGroupMembership> memberships,
    required bool canEditResponse,
    required int interestedCount,
    required int finalizableCount,
    required num? estimatedPerParticipantCost,
    required String paymentReadinessMessage,
    required String yourShareLabel,
    required int paidCount,
    required String currentUserDisplayName,
  }) {
    final String? submittedFormId = group.submittedFormId;
    if (submittedFormId == null || submittedFormId.isEmpty) {
      return _buildDetailsContent(
        group: group,
        creatorDisplayName: creatorDisplayName,
        paidParticipantSetIsValid: paidParticipantSetIsValid,
        currentCostIfSubmittedNowLabel: currentCostIfSubmittedNowLabel,
        trackerFormState: const _GroupTrackerSubmittedFormState.empty(),
        showInviteButton: showInviteButton,
        showFinalizeButton: showFinalizeButton,
        canFinalize: canFinalize,
        showSubmitButton: showSubmitButton,
        canSubmit: canSubmit,
        showCancelButton: showCancelButton,
        currentUserCanSimulatePayment: currentUserCanSimulatePayment,
        myMembership: myMembership,
        memberships: memberships,
        canEditResponse: canEditResponse,
        interestedCount: interestedCount,
        finalizableCount: finalizableCount,
        estimatedPerParticipantCost: estimatedPerParticipantCost,
        paymentReadinessMessage: paymentReadinessMessage,
        yourShareLabel: yourShareLabel,
        paidCount: paidCount,
        currentUserDisplayName: currentUserDisplayName,
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
        final Map<String, dynamic> rawData =
            snapshot.data?.data() ?? const <String, dynamic>{};
        return _buildDetailsContent(
          group: group,
          creatorDisplayName: creatorDisplayName,
          paidParticipantSetIsValid: paidParticipantSetIsValid,
          currentCostIfSubmittedNowLabel: currentCostIfSubmittedNowLabel,
          trackerFormState: _GroupTrackerSubmittedFormState.fromRawData(rawData),
          showInviteButton: showInviteButton,
          showFinalizeButton: showFinalizeButton,
          canFinalize: canFinalize,
          showSubmitButton: showSubmitButton,
          canSubmit: canSubmit,
          showCancelButton: showCancelButton,
          currentUserCanSimulatePayment: currentUserCanSimulatePayment,
          myMembership: myMembership,
          memberships: memberships,
          canEditResponse: canEditResponse,
          interestedCount: interestedCount,
          finalizableCount: finalizableCount,
          estimatedPerParticipantCost: estimatedPerParticipantCost,
          paymentReadinessMessage: paymentReadinessMessage,
          yourShareLabel: yourShareLabel,
          paidCount: paidCount,
          currentUserDisplayName: currentUserDisplayName,
        );
      },
    );
  }

  Widget _buildDetailsContent({
    required LotteryGroup group,
    required String creatorDisplayName,
    required bool paidParticipantSetIsValid,
    required String currentCostIfSubmittedNowLabel,
    required _GroupTrackerSubmittedFormState trackerFormState,
    required bool showInviteButton,
    required bool showFinalizeButton,
    required bool canFinalize,
    required bool showSubmitButton,
    required bool canSubmit,
    required bool showCancelButton,
    required bool currentUserCanSimulatePayment,
    required LotteryGroupMembership? myMembership,
    required List<LotteryGroupMembership> memberships,
    required bool canEditResponse,
    required int interestedCount,
    required int finalizableCount,
    required num? estimatedPerParticipantCost,
    required String paymentReadinessMessage,
    required String yourShareLabel,
    required int paidCount,
    required String currentUserDisplayName,
  }) {
    final String groupStatusLabel = _groupStatusLabel(
      group: group,
      paidParticipantSetIsValid: paidParticipantSetIsValid,
      trackerFormState: trackerFormState,
    );
    final String submissionMessage;
    if (group.status == LotteryGroupStatus.submitted) {
      submissionMessage = _dispatchStatusDescription(
        trackerFormState: trackerFormState,
      );
    } else if (group.status == LotteryGroupStatus.cancelled) {
      submissionMessage =
          'הטופס הקבוצתי בוטל. רק מי שכבר שילם זוכה חזרה לארנק.';
    } else if (paidParticipantSetIsValid) {
      submissionMessage =
          'ניתן כבר לשלוח לפי המשלמים הנוכחיים. אם שולחים עכשיו, כל משלם ישלם $currentCostIfSubmittedNowLabel.';
    } else {
      submissionMessage =
          'ממתינים לתשלומים נוספים לפני שניתן יהיה לשלוח את הטופס.';
    }
    final bool showPrintedButton = group.creatorUserId == widget.currentUserId &&
        group.status == LotteryGroupStatus.submitted &&
        trackerFormState.effectiveDispatchStatus ==
            LotteryGroupRepository.dispatchStatusQueuedForPrint;
    final bool showSubmittedToStationButton =
        group.creatorUserId == widget.currentUserId &&
            group.status == LotteryGroupStatus.submitted &&
            trackerFormState.effectiveDispatchStatus ==
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
        _buildProgressTracker(group),
        const SizedBox(height: 12),
        _buildTicketPreviewCard(group),
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
          showCancelButton: showCancelButton,
          isCancelling: _isCancelling,
          onCancel: () => _confirmAndCancelGroup(group),
          showPrintedButton: showPrintedButton,
          showSubmittedToStationButton: showSubmittedToStationButton,
          isUpdatingDispatch: _isUpdatingDispatch,
          onMarkPrinted: () => _updateDispatchStatus(
            groupId: group.groupId,
            dispatchStatus: LotteryGroupRepository.dispatchStatusPrinted,
          ),
          onMarkSubmittedToStation: () => _updateDispatchStatus(
            groupId: group.groupId,
            dispatchStatus:
                LotteryGroupRepository.dispatchStatusSubmittedToStation,
          ),
          showPayButton: currentUserCanSimulatePayment,
          isPaying: _isPaying,
          onSimulatePayment: myMembership == null
              ? null
              : () => _openPaymentFlow(
                    group: group,
                    membership: myMembership,
                  ),
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
              _InfoRow(label: 'creatorUserId', value: group.creatorUserId),
              _InfoRow(label: 'status(raw)', value: group.status.value),
              _InfoRow(label: 'dispatchStatus(group)', value: '${group.dispatchStatus}'),
              _InfoRow(
                label: 'dispatchStatus(form)',
                value: '${trackerFormState.dispatchStatus}',
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
  }

  Future<void> _openReceiptUrl(String? receiptUrl) async {
    if (receiptUrl == null || receiptUrl.isEmpty) {
      return;
    }

    final Uri uri = Uri.parse(receiptUrl);
    final bool launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('פתיחת הקבלה נכשלה.')),
      );
    }
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
    required _GroupTrackerSubmittedFormState trackerFormState,
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
        return _dispatchStatusLabel(trackerFormState: trackerFormState);
      case LotteryGroupStatus.cancelled:
        return 'הקבוצה בוטלה';
    }
  }

  String _dispatchStatusLabel({
    required _GroupTrackerSubmittedFormState trackerFormState,
  }) {
    if (trackerFormState.hasReceipt) {
      return 'קבלה הועלתה';
    }

    switch (trackerFormState.effectiveDispatchStatus) {
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
    required _GroupTrackerSubmittedFormState trackerFormState,
  }) {
    if (trackerFormState.hasReceipt) {
      return 'הקבלה הועלתה ונקלטה במערכת.';
    }

    switch (trackerFormState.effectiveDispatchStatus) {
      case LotteryGroupRepository.dispatchStatusPrinted:
        return 'הטופס הודפס ומוכן למסירה לתחנה.';
      case LotteryGroupRepository.dispatchStatusSubmittedToStation:
        return 'הטופס נמסר לתחנה.';
      case LotteryGroupRepository.dispatchStatusQueuedForPrint:
      default:
        return (trackerFormState.printReadyUrl?.isNotEmpty ?? false)
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

class _GroupTrackerStepData {
  const _GroupTrackerStepData({
    required this.label,
    required this.icon,
    required this.isSystemOwned,
  });

  final String label;
  final IconData icon;
  final bool isSystemOwned;
}

class _GroupTrackerSubmittedFormState {
  const _GroupTrackerSubmittedFormState({
    required this.dispatchStatus,
    required this.hasReceipt,
    required this.printReadyUrl,
    required this.printedAt,
    required this.submittedToStationAt,
  });

  const _GroupTrackerSubmittedFormState.empty()
      : dispatchStatus = null,
        hasReceipt = false,
        printReadyUrl = null,
        printedAt = null,
        submittedToStationAt = null;

  factory _GroupTrackerSubmittedFormState.fromRawData(
    Map<String, dynamic> rawData,
  ) {
    return _GroupTrackerSubmittedFormState(
      dispatchStatus: rawData['dispatchStatus'] as String?,
      hasReceipt: extractReceiptUrl(rawData) != null,
      printReadyUrl: rawData['printReadyUrl'] as String?,
      printedAt: _asDateTime(rawData['printedAt']),
      submittedToStationAt: _asDateTime(rawData['submittedToStationAt']),
    );
  }

  final String? dispatchStatus;
  final bool hasReceipt;
  final String? printReadyUrl;
  final DateTime? printedAt;
  final DateTime? submittedToStationAt;

  String get effectiveDispatchStatus {
    if (submittedToStationAt != null ||
        dispatchStatus ==
            LotteryGroupRepository.dispatchStatusSubmittedToStation) {
      return LotteryGroupRepository.dispatchStatusSubmittedToStation;
    }
    if (printedAt != null ||
        dispatchStatus == LotteryGroupRepository.dispatchStatusPrinted) {
      return LotteryGroupRepository.dispatchStatusPrinted;
    }
    if ((printReadyUrl?.isNotEmpty ?? false) ||
        dispatchStatus ==
            LotteryGroupRepository.dispatchStatusQueuedForPrint) {
      return LotteryGroupRepository.dispatchStatusQueuedForPrint;
    }
    return LotteryGroupRepository.dispatchStatusQueuedForPrint;
  }

  static DateTime? _asDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }
}

class _GroupTicketTracker extends StatefulWidget {
  const _GroupTicketTracker({
    required this.group,
    required this.trackerFormState,
  });

  final LotteryGroup group;
  final _GroupTrackerSubmittedFormState trackerFormState;

  @override
  State<_GroupTicketTracker> createState() => _GroupTicketTrackerState();
}

class _GroupTicketTrackerState extends State<_GroupTicketTracker>
    with SingleTickerProviderStateMixin {
  static const List<_GroupTrackerStepData> _steps = <_GroupTrackerStepData>[
    _GroupTrackerStepData(
      label: 'איסוף משתתפים',
      icon: Icons.group_add_rounded,
      isSystemOwned: false,
    ),
    _GroupTrackerStepData(
      label: 'ממתין לתשלומים',
      icon: Icons.payments_outlined,
      isSystemOwned: false,
    ),
    _GroupTrackerStepData(
      label: 'הגשת הטופס',
      icon: Icons.send_rounded,
      isSystemOwned: false,
    ),
    _GroupTrackerStepData(
      label: 'הדפסת הטופס',
      icon: Icons.print_rounded,
      isSystemOwned: true,
    ),
    _GroupTrackerStepData(
      label: 'מסירה בתחנה',
      icon: Icons.storefront_rounded,
      isSystemOwned: true,
    ),
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
    final int? currentIndex = completedCount >= _steps.length
        ? null
        : completedCount;
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'מעקב התקדמות הטופס הקבוצתי',
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
                final _GroupTrackerStepData step = _steps[stepIndex];
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
                              color: _stepColor(context, step.isSystemOwned),
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
                            color: _stepColor(
                              context,
                              _steps[stepIndex + 1].isSystemOwned,
                            ),
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
    if (widget.trackerFormState.submittedToStationAt != null ||
        widget.trackerFormState.dispatchStatus ==
            LotteryGroupRepository.dispatchStatusSubmittedToStation) {
      return 5;
    }

    if (widget.trackerFormState.printedAt != null ||
        widget.trackerFormState.dispatchStatus ==
            LotteryGroupRepository.dispatchStatusPrinted) {
      return 4;
    }

    if (widget.group.submittedAt != null ||
        widget.group.status == LotteryGroupStatus.submitted ||
        widget.trackerFormState.dispatchStatus ==
            LotteryGroupRepository.dispatchStatusQueuedForPrint ||
        (widget.trackerFormState.printReadyUrl?.isNotEmpty ?? false)) {
      return 3;
    }

    if (widget.group.status == LotteryGroupStatus.readyForSubmission) {
      return 1;
    }

    if (widget.group.status == LotteryGroupStatus.awaitingPayments ||
        widget.group.finalizedAt != null ||
        widget.group.currentPerParticipantCost > 0) {
      return 1;
    }

    return 0;
  }

  Color _stepColor(BuildContext context, bool isSystemOwned) {
    return isSystemOwned
        ? Theme.of(context).colorScheme.secondary
        : Theme.of(context).colorScheme.primary;
  }
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

  final _GroupTrackerStepData step;
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
    if (group.status == LotteryGroupStatus.cancelled) {
      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(currentUserId)
            .collection('cancelled_groups')
            .doc(group.groupId)
            .snapshots(),
        builder: (context, snapshot) {
          final Map<String, dynamic> data =
              snapshot.data?.data() ?? const <String, dynamic>{};
          final num myRefundAmount = (data['myRefundAmount'] as num?) ?? 0;
          return _InfoCard(
            title: 'פרטי הקבוצה',
            rows: [
              _InfoRow(label: 'שם קבוצה', value: group.groupName),
              _InfoRow(label: 'יוצר הקבוצה', value: creatorDisplayName),
              _InfoRow(
                label: 'בוטל על ידי',
                value: group.cancelledByDisplayName ?? creatorDisplayName,
              ),
              _InfoRow(
                label: 'מועד ביטול',
                value: formatPresentationDateTime(group.cancelledAt),
              ),
              _InfoRow(
                label: 'סך הזיכויים',
                value: '${group.totalRefundedAmount} ש״ח',
              ),
              _InfoRow(
                label: 'הזיכוי שלי',
                value: '$myRefundAmount ש״ח',
              ),
            ],
          );
        },
      );
    }

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
    required this.showCancelButton,
    required this.isCancelling,
    required this.onCancel,
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
  final bool showCancelButton;
  final bool isCancelling;
  final VoidCallback onCancel;
  final bool showPrintedButton;
  final bool showSubmittedToStationButton;
  final bool isUpdatingDispatch;
  final VoidCallback onMarkPrinted;
  final VoidCallback onMarkSubmittedToStation;
  final bool showPayButton;
  final bool isPaying;
  final VoidCallback? onSimulatePayment;

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
                : const Text('לתשלום'),
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
        if (showCancelButton)
          OutlinedButton.icon(
            onPressed: isCancelling ? null : onCancel,
            icon: const Icon(Icons.cancel_outlined),
            label:
                isCancelling ? const Text('מבטל...') : const Text('בטל טיוטה'),
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
                    : const Text('לתשלום'),
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
