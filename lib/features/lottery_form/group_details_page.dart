import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../form_presentation_utils.dart';
import '../../models/lottery_form.dart';
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
  late final Stopwatch _openStopwatch;
  LotteryGroupResponseStatus _selectedStatus =
      LotteryGroupResponseStatus.undecided;
  String? _editingMembershipUserId;
  bool _isSaving = false;
  bool _isFinalizing = false;
  bool _isPaying = false;
  bool _isSubmitting = false;
  bool _isUpdatingDispatch = false;
  String? _updatingGroupFormId;
  String? _updatingGroupFormAction;
  bool _isCancelling = false;
  bool _showDebug = false;
  String? _receiptLookupCacheKey;
  Future<_ResolvedReceiptOpenTarget?>? _receiptLookupFuture;
  String? _formDataCacheKey;
  Future<Map<String, dynamic>>? _formDataFuture;
  bool _didLogFirstGroupData = false;
  bool _didLogFirstMembershipsData = false;
  bool _didLogFirstFormData = false;
  bool _didLogFirstGroupFormsData = false;

  @override
  void initState() {
    super.initState();
    _openStopwatch = Stopwatch()..start();
    debugPrint(
      '[CreateGroupFlow] GroupDetailsPage init +0ms groupId=${widget.groupId}',
    );
  }

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
            debugPrint(
              '[CreateGroupFlow] GroupDetailsPage group stream error +${_openStopwatch.elapsedMilliseconds}ms error=${groupSnapshot.error}',
            );
            return _CenteredMessage(message: '${groupSnapshot.error}');
          }
          if (!groupSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!_didLogFirstGroupData) {
            _didLogFirstGroupData = true;
            debugPrint(
              '[CreateGroupFlow] GroupDetailsPage group stream first data +${_openStopwatch.elapsedMilliseconds}ms',
            );
          }

          final LotteryGroup group = groupSnapshot.data!;
          final bool isCreator = group.creatorUserId == widget.currentUserId;

          return StreamBuilder<List<LotteryGroupMembership>>(
            stream: widget.repository.watchMemberships(
              groupId: group.groupId,
              userId: widget.currentUserId,
            ),
            initialData: const <LotteryGroupMembership>[],
            builder: (context, membershipsSnapshot) {
              if (membershipsSnapshot.hasError) {
                debugPrint(
                  '[CreateGroupFlow] GroupDetailsPage memberships stream error +${_openStopwatch.elapsedMilliseconds}ms error=${membershipsSnapshot.error}',
                );
              }
              if (membershipsSnapshot.connectionState != ConnectionState.waiting &&
                  membershipsSnapshot.hasData &&
                  !_didLogFirstMembershipsData &&
                  membershipsSnapshot.data != null) {
                _didLogFirstMembershipsData = true;
                debugPrint(
                  '[CreateGroupFlow] GroupDetailsPage memberships stream first data +${_openStopwatch.elapsedMilliseconds}ms count=${membershipsSnapshot.data?.length ?? 0}',
                );
              }

              final List<LotteryGroupMembership> memberships =
                  membershipsSnapshot.data ?? const <LotteryGroupMembership>[];
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

  Future<void> _confirmAndFinalizeGroup(String groupId) async {
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('סיום בחירת משתתפים'),
            content: const Text(
              'האם אתה בטוח שברצונך לסיים את בחירת המשתתפים? לא ניתן יהיה לשנות לאחר מכן.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('ביטול'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('אישור'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) {
      return;
    }

    await _finalizeGroup(groupId);
  }

  Future<void> _payGroupViaWallet({
    required LotteryGroup group,
    required LotteryGroupMembership membership,
  }) async {
    final num payableAmount = membership.costShare ?? group.currentPerParticipantCost;
    setState(() => _isPaying = true);
    try {
      await widget.repository.chargeUserWalletForGroup(
        groupId: group.groupId,
        userId: widget.currentUserId,
        amount: payableAmount,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('התשלום בוצע מהיתרה.')),
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

  Future<void> _payGroupExternally({
    required LotteryGroup group,
  }) async {
    setState(() => _isPaying = true);
    try {
      await widget.repository.simulatePayment(
        groupId: group.groupId,
        userId: widget.currentUserId,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('התשלום החיצוני נקלט בהצלחה.')),
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

  Future<void> _markGroupFormPrinted({
    required LotteryGroup group,
    required LotteryGroupForm form,
  }) async {
    setState(() {
      _updatingGroupFormId = form.formId;
      _updatingGroupFormAction = 'printed';
    });
    try {
      await widget.repository.markGroupFormPrinted(
        groupId: group.groupId,
        formId: form.formId,
        creatorUserId: widget.currentUserId,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('טופס ${form.displayOrder} סומן כהודפס.')),
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
        setState(() {
          _updatingGroupFormId = null;
          _updatingGroupFormAction = null;
        });
      }
    }
  }

  Future<void> _markGroupFormSubmittedToStation({
    required LotteryGroup group,
    required LotteryGroupForm form,
  }) async {
    setState(() {
      _updatingGroupFormId = form.formId;
      _updatingGroupFormAction = 'submitted_to_station';
    });
    try {
      await widget.repository.markGroupFormSubmittedToStation(
        groupId: group.groupId,
        formId: form.formId,
        creatorUserId: widget.currentUserId,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('טופס ${form.displayOrder} סומן כנמסר לתחנה.')),
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
        setState(() {
          _updatingGroupFormId = null;
          _updatingGroupFormAction = null;
        });
      }
    }
  }

  void _openGroupSnapshotPreview(LotteryGroup group) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LotteryTicketPreviewPage(
          title: 'תצוגת טופס: ${group.groupName}',
          subtitle: 'תצוגה לקריאה בלבד מתוך הטופס הקבוצתי הקפוא',
          lotteryId: group.lotteryId,
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
    if (group.isMultiFormBundle) {
      return StreamBuilder<List<LotteryGroupForm>>(
        stream: widget.repository.watchGroupForms(
          groupId: group.groupId,
          userId: widget.currentUserId,
        ),
        builder: (context, groupFormsSnapshot) {
          if (groupFormsSnapshot.hasError) {
            debugPrint(
              '[GroupDetails] group forms stream error: ${groupFormsSnapshot.error}',
            );
          }
          if (groupFormsSnapshot.hasData &&
              !_didLogFirstGroupFormsData &&
              groupFormsSnapshot.data != null) {
            _didLogFirstGroupFormsData = true;
            debugPrint(
              '[CreateGroupFlow] GroupDetailsPage group forms first data +${_openStopwatch.elapsedMilliseconds}ms count=${groupFormsSnapshot.data?.length ?? 0}',
            );
          }
          return _buildDetailsContent(
            group: group,
            creatorDisplayName: creatorDisplayName,
            paidParticipantSetIsValid: paidParticipantSetIsValid,
            currentCostIfSubmittedNowLabel: currentCostIfSubmittedNowLabel,
            trackerFormState: const _GroupTrackerSubmittedFormState.empty(),
            formData: const <String, dynamic>{},
            receiptTarget: null,
            groupForms: groupFormsSnapshot.data ?? const <LotteryGroupForm>[],
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

    final String formDocumentId = (group.submittedFormId?.isNotEmpty ?? false)
        ? group.submittedFormId!
        : group.sourceFormId;
    if (formDocumentId.isEmpty) {
      return _buildDetailsContent(
        group: group,
        creatorDisplayName: creatorDisplayName,
        paidParticipantSetIsValid: paidParticipantSetIsValid,
        currentCostIfSubmittedNowLabel: currentCostIfSubmittedNowLabel,
        trackerFormState: const _GroupTrackerSubmittedFormState.empty(),
        formData: const <String, dynamic>{},
        receiptTarget: null,
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

    if (group.status != LotteryGroupStatus.submitted) {
      return FutureBuilder<Map<String, dynamic>>(
        future: _loadFormData(
          ownerUserId: group.creatorUserId,
          formId: formDocumentId,
        ),
        builder: (context, snapshot) {
          final Map<String, dynamic> rawData =
              snapshot.data ?? const <String, dynamic>{};
          if (snapshot.hasData && !_didLogFirstFormData) {
            _didLogFirstFormData = true;
            debugPrint(
              '[CreateGroupFlow] GroupDetailsPage source form read ready +${_openStopwatch.elapsedMilliseconds}ms formId=$formDocumentId',
            );
          }
          final _ResolvedReceiptOpenTarget? directReceiptTarget =
              _resolvedReceiptTargetFromRawData(rawData);
          final bool requiresReceiptLookup =
              _hasMatchedReceipt(rawData) && directReceiptTarget == null;

          if (!requiresReceiptLookup) {
            return _buildDetailsContent(
              group: group,
              creatorDisplayName: creatorDisplayName,
              paidParticipantSetIsValid: paidParticipantSetIsValid,
              currentCostIfSubmittedNowLabel: currentCostIfSubmittedNowLabel,
              trackerFormState: _GroupTrackerSubmittedFormState.fromRawData(rawData),
              formData: rawData,
              receiptTarget: directReceiptTarget,
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

          return FutureBuilder<_ResolvedReceiptOpenTarget?>(
            future: _lookupReceiptOpenTarget(
              ownerUserId: group.creatorUserId,
              formId: formDocumentId,
              formData: rawData,
            ),
            builder: (context, receiptSnapshot) {
              return _buildDetailsContent(
                group: group,
                creatorDisplayName: creatorDisplayName,
                paidParticipantSetIsValid: paidParticipantSetIsValid,
                currentCostIfSubmittedNowLabel: currentCostIfSubmittedNowLabel,
                trackerFormState: _GroupTrackerSubmittedFormState.fromRawData(rawData),
                formData: rawData,
                receiptTarget: receiptSnapshot.data,
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
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(group.creatorUserId)
          .collection('forms')
          .doc(formDocumentId)
          .snapshots(),
      builder: (context, snapshot) {
        final Map<String, dynamic> rawData =
            snapshot.data?.data() ?? const <String, dynamic>{};
        final _ResolvedReceiptOpenTarget? directReceiptTarget =
            _resolvedReceiptTargetFromRawData(rawData);
        final bool requiresReceiptLookup =
            _hasMatchedReceipt(rawData) && directReceiptTarget == null;

        if (!requiresReceiptLookup) {
          return _buildDetailsContent(
            group: group,
            creatorDisplayName: creatorDisplayName,
            paidParticipantSetIsValid: paidParticipantSetIsValid,
            currentCostIfSubmittedNowLabel: currentCostIfSubmittedNowLabel,
            trackerFormState: _GroupTrackerSubmittedFormState.fromRawData(rawData),
            formData: rawData,
            receiptTarget: directReceiptTarget,
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

        return FutureBuilder<_ResolvedReceiptOpenTarget?>(
          future: _lookupReceiptOpenTarget(
            ownerUserId: group.creatorUserId,
            formId: formDocumentId,
            formData: rawData,
          ),
          builder: (context, receiptSnapshot) {
            return _buildDetailsContent(
              group: group,
              creatorDisplayName: creatorDisplayName,
              paidParticipantSetIsValid: paidParticipantSetIsValid,
              currentCostIfSubmittedNowLabel: currentCostIfSubmittedNowLabel,
              trackerFormState: _GroupTrackerSubmittedFormState.fromRawData(rawData),
              formData: rawData,
              receiptTarget: receiptSnapshot.data,
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
    );
  }

  Widget _buildDetailsContent({
    required LotteryGroup group,
    required String creatorDisplayName,
    required bool paidParticipantSetIsValid,
    required String currentCostIfSubmittedNowLabel,
    required _GroupTrackerSubmittedFormState trackerFormState,
    required Map<String, dynamic> formData,
    required _ResolvedReceiptOpenTarget? receiptTarget,
    List<LotteryGroupForm> groupForms = const <LotteryGroupForm>[],
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
    final bool isMultiFormBundle = group.isMultiFormBundle;
    final String groupStatusLabel = _groupStatusLabel(
      group: group,
      paidParticipantSetIsValid: paidParticipantSetIsValid,
      trackerFormState: trackerFormState,
    );
    final bool showPrintedButton = group.creatorUserId == widget.currentUserId &&
        !isMultiFormBundle &&
        group.status == LotteryGroupStatus.submitted &&
        trackerFormState.effectiveDispatchStatus ==
            LotteryGroupRepository.dispatchStatusQueuedForPrint;
    final bool showSubmittedToStationButton =
        group.creatorUserId == widget.currentUserId &&
            !isMultiFormBundle &&
            group.status == LotteryGroupStatus.submitted &&
            trackerFormState.effectiveDispatchStatus ==
                LotteryGroupRepository.dispatchStatusPrinted;
    final bool showOutcomeCard =
        group.status == LotteryGroupStatus.submitted ||
        group.status == LotteryGroupStatus.cancelled;
    final bool canOpenReceipt = !isMultiFormBundle &&
        _hasMatchedReceipt(formData) && receiptTarget != null;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
        _GroupInfoPanel(
          groupName: group.groupName,
          creatorDisplayName: creatorDisplayName,
          statusLabel: groupStatusLabel,
          ticketTypeLabel:
              isMultiFormBundle ? null : _ticketTypeLabel(formData),
          lotteryNumber: isMultiFormBundle
              ? (group.lotteryId?.toString() ??
                  _resolveMultiFormLotteryNumber(groupForms))
              : (group.lotteryId?.toString() ??
                  formData['lotteryId']?.toString()),
          lotteryDate: isMultiFormBundle
              ? group.salesCloseAt ?? _resolveMultiFormLotteryDate(groupForms)
              : group.salesCloseAt ??
                  presentationAsDateTime(formData['salesCloseAt']),
          formCount: isMultiFormBundle ? group.formCount : null,
          tablesCount:
              isMultiFormBundle ? group.totalTableCount : group.populatedTableCount,
          totalCost: isMultiFormBundle ? group.totalCost : group.baseTicketCost,
          onOpenForm: isMultiFormBundle ? null : () => _openPrimaryTicketView(group),
          onOpenReceipt:
              canOpenReceipt ? () => _openReceiptTarget(receiptTarget) : null,
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
          onFinalize: () => _confirmAndFinalizeGroup(group.groupId),
          showDeleteButton: showCancelButton,
          isCancelling: _isCancelling,
          onDelete: () => _confirmAndCancelGroup(group),
        ),
        const SizedBox(height: 12),
        isMultiFormBundle
            ? _GroupTicketTracker(
                group: group,
                trackerFormState: const _GroupTrackerSubmittedFormState.empty(),
              )
            : _buildProgressTracker(group),
        const SizedBox(height: 12),
        if (!isMultiFormBundle) ...[
          _OperationalGroupFormTracker(
            trackerFormState: trackerFormState,
            title: 'מעקב התקדמות הטופס',
          ),
          const SizedBox(height: 12),
        ],
        if (isMultiFormBundle) ...[
          _GroupFormsSection(
            group: group,
            forms: groupForms,
            showDebug: _showDebug,
            onOpenReceiptTarget: _openReceiptTarget,
            updatingFormId: _updatingGroupFormId,
            updatingAction: _updatingGroupFormAction,
            onMarkPrinted: (form) => _markGroupFormPrinted(
              group: group,
              form: form,
            ),
            onMarkSubmittedToStation: (form) => _markGroupFormSubmittedToStation(
              group: group,
              form: form,
            ),
          ),
          const SizedBox(height: 12),
        ],
        _WorkflowActionsRow(
          showSubmitButton: showSubmitButton,
          canSubmit: canSubmit,
          isSubmitting: _isSubmitting,
          onSubmit: () => _submitGroup(groupId: group.groupId),
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
        ),
        if (showOutcomeCard) ...[
          const SizedBox(height: 12),
          _GroupOutcomeCard(
            group: group,
            currentUserId: widget.currentUserId,
            creatorDisplayName: creatorDisplayName,
            groupForms: groupForms,
          ),
        ],
        const SizedBox(height: 12),
        if (canEditResponse) ...[
          _MyResponseCard(
            membership: myMembership,
            group: group,
            canEdit: canEditResponse,
            selectedStatus: _selectedStatus,
            minimumController: _minimumController,
            isSaving: _isSaving,
            isPaying: _isPaying,
            onStatusChanged: (status) {
              setState(() => _selectedStatus = status);
            },
            onSave: myMembership == null
                ? null
                : () => _saveMyResponse(groupId: group.groupId),
            onSimulatePayment: null,
            showDebug: _showDebug,
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
        ] else ...[
          if (myMembership != null &&
              group.status != LotteryGroupStatus.submitted &&
              group.status != LotteryGroupStatus.cancelled) ...[
            _GroupPaymentSection(
              userId: widget.currentUserId,
              group: group,
              membership: myMembership,
              isPaying: _isPaying,
              onWalletPayment: () => _payGroupViaWallet(
                group: group,
                membership: myMembership,
              ),
              onExternalPayment: () => _payGroupExternally(group: group),
            ),
            const SizedBox(height: 12),
          ],
          _ParticipantsCard(
            memberships: memberships,
            group: group,
            currentUserId: widget.currentUserId,
            currentUserDisplayName: currentUserDisplayName,
            creatorUserId: group.creatorUserId,
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
      ),
    );
  }

  Future<void> _openReceiptUrl(String? receiptUrl) async {
    if (receiptUrl == null || receiptUrl.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('הקבלה הותאמה אך אין קישור פתיחה זמין.')),
        );
      }
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

  Future<void> _openReceiptTarget(_ResolvedReceiptOpenTarget? receiptTarget) {
    return _openReceiptUrl(receiptTarget?.targetUrl);
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

  String _ticketTypeLabel(Map<String, dynamic> formData) {
    final String? rawTicketType = formData['ticketType'] as String?;
    switch (rawTicketType) {
      case 'double':
      case 'double_lotto':
        return 'דאבל';
      case 'regular':
      case 'regular_lotto':
        return 'רגיל';
      default:
        return 'רגיל';
    }
  }

  String? _resolveMultiFormLotteryNumber(List<LotteryGroupForm> groupForms) {
    for (final LotteryGroupForm form in groupForms) {
      final String? lotteryId = form.rawData['lotteryId']?.toString();
      if (lotteryId != null && lotteryId.trim().isNotEmpty) {
        return lotteryId.trim();
      }
    }
    return null;
  }

  DateTime? _resolveMultiFormLotteryDate(List<LotteryGroupForm> groupForms) {
    for (final LotteryGroupForm form in groupForms) {
      if (form.salesCloseAt != null) {
        return form.salesCloseAt;
      }
      final DateTime? rawDate =
          presentationAsDateTime(form.rawData['salesCloseAt']);
      if (rawDate != null) {
        return rawDate;
      }
    }
    return null;
  }

  bool _hasMatchedReceipt(Map<String, dynamic> formData) {
    return (formData['stationReceiptMatchStatus'] as String?) == 'matched';
  }

  _ResolvedReceiptOpenTarget? _resolvedReceiptTargetFromRawData(
    Map<String, dynamic> rawData,
  ) {
    final String? receiptUrl = _validReceiptUrl(rawData);
    if (receiptUrl == null) {
      return null;
    }
    return _ResolvedReceiptOpenTarget(
      targetUrl: receiptUrl,
      targetStoragePath: _receiptStoragePath(rawData),
      source: 'form',
    );
  }

  String? _validReceiptUrl(Map<String, dynamic> formData) {
    final String? receiptUrl = extractReceiptUrl(formData);
    if (receiptUrl == null || receiptUrl.isEmpty) {
      return null;
    }
    final Uri? uri = Uri.tryParse(receiptUrl);
    if (uri == null || (!uri.hasScheme || !uri.hasAuthority)) {
      return null;
    }
    return receiptUrl;
  }

  String? _receiptStoragePath(Map<String, dynamic> rawData) {
    final List<String> candidateKeys = <String>[
      'stationReceiptStoragePath',
      'receiptStoragePath',
      'uploadedReceiptStoragePath',
      'storagePath',
    ];
    for (final String key in candidateKeys) {
      final String? value = rawData[key] as String?;
      if (value != null && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  Future<_ResolvedReceiptOpenTarget?> _lookupReceiptOpenTarget({
    required String ownerUserId,
    required String formId,
    required Map<String, dynamic> formData,
  }) {
    final String matchedAtKey =
        '${formData['stationReceiptMatchedAt'] ?? ''}|${formData['updatedAt'] ?? ''}';
    final String cacheKey =
        '$ownerUserId|$formId|${formData['stationReceiptIntakeId'] ?? ''}|$matchedAtKey';
    if (_receiptLookupCacheKey == cacheKey && _receiptLookupFuture != null) {
      return _receiptLookupFuture!;
    }
    _receiptLookupCacheKey = cacheKey;
    _receiptLookupFuture = _fetchReceiptOpenTarget(
      ownerUserId: ownerUserId,
      formId: formId,
    );
    return _receiptLookupFuture!;
  }

  Future<_ResolvedReceiptOpenTarget?> _fetchReceiptOpenTarget({
    required String ownerUserId,
    required String formId,
  }) async {
    try {
      final HttpsCallable callable =
          FirebaseFunctions.instance.httpsCallable('getReceiptOpenTarget');
      final HttpsCallableResult<dynamic> result = await callable.call(
        <String, dynamic>{
          'ownerUserId': ownerUserId,
          'formId': formId,
        },
      );
      final dynamic raw = result.data;
      if (raw is! Map) {
        return null;
      }
      final Map<String, dynamic> data = Map<String, dynamic>.from(raw);
      final String? targetUrl = (data['targetUrl'] as String?)?.trim();
      if (targetUrl == null || targetUrl.isEmpty) {
        return null;
      }
      return _ResolvedReceiptOpenTarget(
        targetUrl: targetUrl,
        targetStoragePath: (data['targetStoragePath'] as String?)?.trim(),
        source: (data['source'] as String?)?.trim(),
      );
    } catch (error) {
      debugPrint('[GroupDetails] receipt target lookup failed: $error');
      return null;
    }
  }

  Future<Map<String, dynamic>> _loadFormData({
    required String ownerUserId,
    required String formId,
  }) {
    final String cacheKey = '$ownerUserId|$formId';
    if (_formDataCacheKey == cacheKey && _formDataFuture != null) {
      return _formDataFuture!;
    }
    _formDataCacheKey = cacheKey;
    _formDataFuture = _fetchFormData(
      ownerUserId: ownerUserId,
      formId: formId,
    );
    return _formDataFuture!;
  }

  Future<Map<String, dynamic>> _fetchFormData({
    required String ownerUserId,
    required String formId,
  }) async {
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken();
      final DocumentSnapshot<Map<String, dynamic>> snapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(ownerUserId)
              .collection('forms')
              .doc(formId)
              .get();
      return snapshot.data() ?? const <String, dynamic>{};
    } catch (error) {
      debugPrint('[GroupDetails] form data lookup failed: $error');
      return const <String, dynamic>{};
    }
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

class _ResolvedReceiptOpenTarget {
  const _ResolvedReceiptOpenTarget({
    required this.targetUrl,
    required this.targetStoragePath,
    required this.source,
  });

  final String targetUrl;
  final String? targetStoragePath;
  final String? source;
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
      label: 'הגשת הטופס/ים',
      icon: Icons.send_rounded,
      isSystemOwned: false,
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
            'מעקב התקדמות שליחת הטופס/ים',
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
    if (_isGroupSubmissionCompleted) {
      return 3;
    }
    if (_areRequiredPaymentsCompleted) {
      return 2;
    }
    if (_isParticipantCollectionCompleted) {
      return 1;
    }
    return 0;
  }

  bool get _isParticipantCollectionCompleted {
    return widget.group.status != LotteryGroupStatus.collectingResponses ||
        widget.group.finalizedAt != null ||
        widget.group.currentPerParticipantCost > 0;
  }

  bool get _areRequiredPaymentsCompleted {
    return widget.group.status == LotteryGroupStatus.readyForSubmission ||
        widget.group.status == LotteryGroupStatus.submitted ||
        _isGroupSubmissionCompleted;
  }

  bool get _isGroupSubmissionCompleted {
    return widget.group.submittedAt != null ||
        widget.group.status == LotteryGroupStatus.submitted ||
        widget.trackerFormState.dispatchStatus ==
            LotteryGroupRepository.dispatchStatusQueuedForPrint ||
        (widget.trackerFormState.printReadyUrl?.isNotEmpty ?? false) ||
        widget.trackerFormState.printedAt != null ||
        widget.trackerFormState.submittedToStationAt != null ||
        widget.trackerFormState.dispatchStatus ==
            LotteryGroupRepository.dispatchStatusPrinted ||
        widget.trackerFormState.dispatchStatus ==
            LotteryGroupRepository.dispatchStatusSubmittedToStation;
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

class _GroupFormsSection extends StatelessWidget {
  const _GroupFormsSection({
    required this.group,
    required this.forms,
    required this.showDebug,
    required this.onOpenReceiptTarget,
    required this.updatingFormId,
    required this.updatingAction,
    required this.onMarkPrinted,
    required this.onMarkSubmittedToStation,
  });

  final LotteryGroup group;
  final List<LotteryGroupForm> forms;
  final bool showDebug;
  final Future<void> Function(_ResolvedReceiptOpenTarget? receiptTarget)
      onOpenReceiptTarget;
  final String? updatingFormId;
  final String? updatingAction;
  final Future<void> Function(LotteryGroupForm form) onMarkPrinted;
  final Future<void> Function(LotteryGroupForm form) onMarkSubmittedToStation;

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
            'הטפסים בקבוצה',
            textAlign: TextAlign.right,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          if (forms.isEmpty)
            Text(
              'עדיין אין טפסים שמורים תחת הקבוצה.',
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium,
            )
          else
            ...List<Widget>.generate(forms.length, (index) {
              final LotteryGroupForm form = forms[index];
              return Column(
                children: [
                  _GroupBundleFormRow(
                    group: group,
                    form: form,
                    showDebug: showDebug,
                    onOpenReceiptTarget: onOpenReceiptTarget,
                    isUpdating:
                        updatingFormId == form.formId && updatingAction != null,
                    updatingAction: updatingFormId == form.formId
                        ? updatingAction
                        : null,
                    onMarkPrinted: () => onMarkPrinted(form),
                    onMarkSubmittedToStation: () =>
                        onMarkSubmittedToStation(form),
                  ),
                  if (index < forms.length - 1)
                    Divider(
                      height: 18,
                      color:
                          theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
                    ),
                ],
              );
            }),
        ],
      ),
    );
  }
}

class _GroupBundleFormRow extends StatelessWidget {
  const _GroupBundleFormRow({
    required this.group,
    required this.form,
    required this.showDebug,
    required this.onOpenReceiptTarget,
    required this.isUpdating,
    required this.updatingAction,
    required this.onMarkPrinted,
    required this.onMarkSubmittedToStation,
  });

  final LotteryGroup group;
  final LotteryGroupForm form;
  final bool showDebug;
  final Future<void> Function(_ResolvedReceiptOpenTarget? receiptTarget)
      onOpenReceiptTarget;
  final bool isUpdating;
  final String? updatingAction;
  final VoidCallback onMarkPrinted;
  final VoidCallback onMarkSubmittedToStation;

  @override
  Widget build(BuildContext context) {
    final _ResolvedReceiptOpenTarget? receiptTarget =
        _resolvedReceiptTargetFromGroupForm(form);
    final bool canOpenReceipt = receiptTarget != null;
    final bool canMarkPrinted = group.creatorUserId == FirebaseAuth.instance.currentUser?.uid &&
        group.status == LotteryGroupStatus.submitted &&
        (form.dispatchStatus == null ||
            form.dispatchStatus ==
                LotteryGroupRepository.dispatchStatusQueuedForPrint) &&
        form.printedAt == null;
    final bool canMarkSubmittedToStation =
        group.creatorUserId == FirebaseAuth.instance.currentUser?.uid &&
            group.status == LotteryGroupStatus.submitted &&
            (form.dispatchStatus ==
                    LotteryGroupRepository.dispatchStatusPrinted ||
                form.printedAt != null) &&
            form.submittedToStationAt == null;

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
            _GroupFormMetaText(
              value: 'סוג טופס: ${form.isDoubleMode ? 'דאבל' : 'רגיל'}',
            ),
            _GroupFormMetaText(value: 'מספר טבלאות: ${form.tableCount}'),
            _GroupFormMetaText(
              value: 'עלות הטופס: ${_formatGroupAmount(form.cost)} ש״ח',
            ),
            _GroupFormMetaText(
              value:
                  'מס׳ הגרלה: ${form.lotteryId?.toString() ?? form.rawData['lotteryId']?.toString() ?? '—'}',
            ),
            _GroupFormMetaText(
              value:
                  'תאריך הגרלה: ${formatPresentationDateTime(form.salesCloseAt ?? presentationAsDateTime(form.rawData['salesCloseAt']))}',
            ),
            _GroupFormMetaText(
              value: 'זכייה: ${_groupFormWinningLabel(form)}',
            ),
            if (showDebug)
              _GroupFormMetaText(value: 'sourceDraft: ${form.sourceDraftNumber}'),
          ],
        ),
        const SizedBox(height: 10),
        _GroupFormProgressTracker(form: form),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 10,
          runSpacing: 8,
          children: [
            if (canMarkPrinted)
              FilledButton.icon(
                onPressed: isUpdating ? null : onMarkPrinted,
                icon: isUpdating && updatingAction == 'printed'
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.print_rounded),
                label: const Text('סמן כהודפס'),
              ),
            if (canMarkSubmittedToStation)
              FilledButton.tonalIcon(
                onPressed: isUpdating ? null : onMarkSubmittedToStation,
                icon: isUpdating && updatingAction == 'submitted_to_station'
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.storefront_rounded),
                label: const Text('נמסר לתחנה'),
              ),
            FilledButton.tonalIcon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LotteryTicketPreviewPage(
                      title: 'טופס ${form.displayOrder}',
                      subtitle: 'תצוגה לקריאה בלבד של טופס מתוך קבוצה',
                      lotteryId: form.lotteryId,
                      tables: form.tables,
                      showDebug: showDebug,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('צפה בטופס'),
            ),
            OutlinedButton.icon(
              onPressed:
                  canOpenReceipt ? () => onOpenReceiptTarget(receiptTarget) : null,
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('צפה בקבלה'),
            ),
          ],
        ),
      ],
    );
  }
}

String _groupFormWinningLabel(LotteryGroupForm form) {
  final num winAmount = form.winAmount ?? 0;
  final String? resultStatus = form.resultStatus;
  final bool isPublished =
      resultStatus == LotteryResultStatus.checked.name ||
      resultStatus == LotteryResultStatus.winner.name ||
      resultStatus == LotteryResultStatus.loser.name ||
      resultStatus == 'checked' ||
      resultStatus == 'winner' ||
      resultStatus == 'loser';
  if (!isPublished) {
    return 'טרם פורסם';
  }
  return '$winAmount ש״ח';
}

class _GroupFormProgressTracker extends StatefulWidget {
  const _GroupFormProgressTracker({
    required this.form,
  });

  final LotteryGroupForm form;

  @override
  State<_GroupFormProgressTracker> createState() =>
      _GroupFormProgressTrackerState();
}

class _GroupFormProgressTrackerState extends State<_GroupFormProgressTracker>
    with SingleTickerProviderStateMixin {
  static const List<_GroupTrackerStepData> _steps = <_GroupTrackerStepData>[
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
    _GroupTrackerStepData(
      label: 'בדיקת תוצאות',
      icon: Icons.verified_outlined,
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
    final int? currentIndex =
        completedCount >= _steps.length ? null : completedCount;
    final Color trackerColor = Theme.of(context).colorScheme.primary;

    return Directionality(
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
                        isCurrent:
                            currentIndex != null && stepIndex == currentIndex,
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
                      glow:
                          currentIndex != null && currentIndex == stepIndex + 1,
                      color: trackerColor,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  int _deriveCompletedStepCount() {
    if (_areResultsChecked) {
      return 3;
    }
    if (_isSubmittedToStation) {
      return 2;
    }
    if (_isPrinted) {
      return 1;
    }
    return 0;
  }

  bool get _isPrinted {
    return widget.form.printedAt != null ||
        widget.form.dispatchStatus == LotteryGroupRepository.dispatchStatusPrinted;
  }

  bool get _isSubmittedToStation {
    return widget.form.submittedToStationAt != null ||
        widget.form.dispatchStatus ==
            LotteryGroupRepository.dispatchStatusSubmittedToStation;
  }

  bool get _areResultsChecked {
    final String? resultStatus = widget.form.resultStatus;
    return resultStatus == LotteryResultStatus.checked.name ||
        resultStatus == LotteryResultStatus.winner.name ||
        resultStatus == LotteryResultStatus.loser.name ||
        resultStatus == 'checked' ||
        resultStatus == 'winner' ||
        resultStatus == 'loser';
  }
}

class _OperationalGroupFormTracker extends StatefulWidget {
  const _OperationalGroupFormTracker({
    required this.trackerFormState,
    this.title,
  });

  final _GroupTrackerSubmittedFormState trackerFormState;
  final String? title;

  @override
  State<_OperationalGroupFormTracker> createState() =>
      _OperationalGroupFormTrackerState();
}

class _OperationalGroupFormTrackerState extends State<_OperationalGroupFormTracker>
    with SingleTickerProviderStateMixin {
  static const List<_GroupTrackerStepData> _steps = <_GroupTrackerStepData>[
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
    _GroupTrackerStepData(
      label: 'בדיקת תוצאות',
      icon: Icons.verified_outlined,
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
          if (widget.title != null) ...[
            Text(
              widget.title!,
              textAlign: TextAlign.right,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
          ],
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
      return 3;
    }
    if (_isSubmittedToStation) {
      return 2;
    }
    if (_isPrinted) {
      return 1;
    }
    return 0;
  }

  bool get _isPrinted {
    return widget.trackerFormState.printedAt != null ||
        widget.trackerFormState.dispatchStatus ==
            LotteryGroupRepository.dispatchStatusPrinted ||
        _isSubmittedToStation;
  }

  bool get _isSubmittedToStation {
    return widget.trackerFormState.submittedToStationAt != null ||
        widget.trackerFormState.dispatchStatus ==
            LotteryGroupRepository.dispatchStatusSubmittedToStation;
  }

  bool get _areResultsChecked {
    return widget.trackerFormState.hasReceipt;
  }
}

class _GroupFormMetaText extends StatelessWidget {
  const _GroupFormMetaText({
    required this.value,
  });

  final String value;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      textAlign: TextAlign.right,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

_ResolvedReceiptOpenTarget? _resolvedReceiptTargetFromGroupForm(
  LotteryGroupForm form,
) {
  final String? receiptUrl = form.receiptUrl;
  if (receiptUrl == null || receiptUrl.isEmpty) {
    return null;
  }
  final Uri? uri = Uri.tryParse(receiptUrl);
  if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
    return null;
  }
  return _ResolvedReceiptOpenTarget(
    targetUrl: receiptUrl,
    targetStoragePath: null,
    source: 'group_form',
  );
}

String _formatGroupAmount(num amount) {
  final double normalized = amount.toDouble();
  if ((normalized - normalized.roundToDouble()).abs() < 0.0001) {
    return normalized.round().toString();
  }
  return normalized.toStringAsFixed(1);
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

class _GroupInfoPanel extends StatelessWidget {
  const _GroupInfoPanel({
    required this.groupName,
    required this.creatorDisplayName,
    required this.statusLabel,
    this.ticketTypeLabel,
    required this.lotteryNumber,
    this.lotteryDate,
    this.formCount,
    required this.tablesCount,
    required this.totalCost,
    this.onOpenForm,
    required this.onOpenReceipt,
    required this.showInviteButton,
    required this.onInvite,
    required this.showFinalizeButton,
    required this.canFinalize,
    required this.isFinalizing,
    required this.onFinalize,
    required this.showDeleteButton,
    required this.isCancelling,
    required this.onDelete,
  });

  final String groupName;
  final String creatorDisplayName;
  final String statusLabel;
  final String? ticketTypeLabel;
  final String? lotteryNumber;
  final DateTime? lotteryDate;
  final int? formCount;
  final int tablesCount;
  final num totalCost;
  final VoidCallback? onOpenForm;
  final VoidCallback? onOpenReceipt;
  final bool showInviteButton;
  final void Function(BuildContext buttonContext)? onInvite;
  final bool showFinalizeButton;
  final bool canFinalize;
  final bool isFinalizing;
  final VoidCallback onFinalize;
  final bool showDeleteButton;
  final bool isCancelling;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isNarrow = constraints.maxWidth < 390;
        return Container(
          padding: EdgeInsets.fromLTRB(
            isNarrow ? 12 : 14,
            isNarrow ? 10 : 12,
            isNarrow ? 12 : 14,
            isNarrow ? 12 : 14,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.end,
                  children: [
                    if (showDeleteButton)
                      IconButton.filledTonal(
                        onPressed: isCancelling ? null : onDelete,
                        icon: isCancelling
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.delete_outline_rounded, size: 18),
                        tooltip: 'מחק טופס',
                      ),
                    if (showFinalizeButton)
                      IconButton.filledTonal(
                        onPressed:
                            canFinalize && !isFinalizing ? onFinalize : null,
                        icon: isFinalizing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.how_to_reg_rounded, size: 18),
                        tooltip: 'סיום בחירת משתתפים',
                      ),
                    if (showInviteButton && onInvite != null)
                      Builder(
                        builder: (buttonContext) => IconButton.filledTonal(
                          onPressed: () => onInvite!(buttonContext),
                          icon: const Icon(Icons.share_outlined, size: 18),
                          tooltip: 'שלח לינק להצטרפות',
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Directionality(
                textDirection: TextDirection.rtl,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'שם הקבוצה: $groupName',
                        textAlign: TextAlign.right,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          fontSize: isNarrow ? 22 : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (isNarrow)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'סטאטוס: $statusLabel',
                              textAlign: TextAlign.right,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'הגרלה מס׳: ${lotteryNumber?.isNotEmpty == true ? lotteryNumber : '—'}',
                              textAlign: TextAlign.right,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'תאריך הגרלה: ${formatPresentationDateTime(lotteryDate)}',
                              textAlign: TextAlign.right,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        )
                      else
                        Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          alignment: WrapAlignment.end,
                          children: [
                            Text(
                              'סטאטוס: $statusLabel',
                              textAlign: TextAlign.right,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            Text(
                              'הגרלה מס׳: ${lotteryNumber?.isNotEmpty == true ? lotteryNumber : '—'}',
                              textAlign: TextAlign.right,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'תאריך הגרלה: ${formatPresentationDateTime(lotteryDate)}',
                              textAlign: TextAlign.right,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _InfoPillsGrid(
                children: [
                  _MetaPill(label: 'יוצר הקבוצה', value: creatorDisplayName),
                  if (ticketTypeLabel != null)
                    _MetaPill(label: 'סוג טופס', value: ticketTypeLabel!),
                  if (formCount != null)
                    _MetaPill(label: 'מספר טפסים', value: '$formCount'),
                  _MetaPill(
                    label: formCount != null ? 'סה״כ טבלאות' : 'מספר טבלאות',
                    value: '$tablesCount',
                  ),
                  _MetaPill(label: 'עלות כוללת', value: '$totalCost ש״ח'),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 6,
                alignment: WrapAlignment.end,
                children: [
                  if (onOpenForm != null)
                    TextButton.icon(
                      onPressed: onOpenForm,
                      icon: const Icon(Icons.confirmation_num_outlined),
                      label: const Text('צפה בטופס'),
                    ),
                  if (onOpenForm != null)
                    Tooltip(
                      message: onOpenReceipt == null
                          ? 'הקבלה הותאמה אך עדיין אין קישור לפתיחה'
                          : 'צפה בקבלה',
                      child: TextButton.icon(
                        onPressed: onOpenReceipt,
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const Text('צפה בקבלה'),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InfoPillsGrid extends StatelessWidget {
  const _InfoPillsGrid({
    required this.children,
  });

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double spacing = 8;
        final double itemWidth = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          alignment: WrapAlignment.end,
          textDirection: TextDirection.rtl,
          children: children
              .map((child) => SizedBox(width: itemWidth, child: child))
              .toList(),
        );
      },
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Center(
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkflowActionsRow extends StatelessWidget {
  const _WorkflowActionsRow({
    required this.showSubmitButton,
    required this.canSubmit,
    required this.isSubmitting,
    required this.onSubmit,
    required this.showPrintedButton,
    required this.showSubmittedToStationButton,
    required this.isUpdatingDispatch,
    required this.onMarkPrinted,
    required this.onMarkSubmittedToStation,
  });

  final bool showSubmitButton;
  final bool canSubmit;
  final bool isSubmitting;
  final VoidCallback onSubmit;
  final bool showPrintedButton;
  final bool showSubmittedToStationButton;
  final bool isUpdatingDispatch;
  final VoidCallback onMarkPrinted;
  final VoidCallback onMarkSubmittedToStation;

  @override
  Widget build(BuildContext context) {
    if (!showSubmitButton && !showPrintedButton && !showSubmittedToStationButton) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        if (showSubmitButton)
          FilledButton.icon(
            onPressed: canSubmit && !isSubmitting ? onSubmit : null,
            icon: isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined, size: 18),
            label: const Text('הגש טופס קבוצתי'),
          ),
        if (showPrintedButton)
          OutlinedButton.icon(
            onPressed: isUpdatingDispatch ? null : onMarkPrinted,
            icon: const Icon(Icons.print_outlined, size: 18),
            label: const Text('סמן כהודפס'),
          ),
        if (showSubmittedToStationButton)
          OutlinedButton.icon(
            onPressed: isUpdatingDispatch ? null : onMarkSubmittedToStation,
            icon: const Icon(Icons.store_outlined, size: 18),
            label: const Text('סמן כנמסר לתחנה'),
          ),
      ],
    );
  }
}

class _GroupOutcomeCard extends StatelessWidget {
  const _GroupOutcomeCard({
    required this.group,
    required this.currentUserId,
    required this.creatorDisplayName,
    this.groupForms = const <LotteryGroupForm>[],
  });

  final LotteryGroup group;
  final String currentUserId;
  final String creatorDisplayName;
  final List<LotteryGroupForm> groupForms;

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
      final bool hasPublishedResults = group.resultPublishedAt != null;
      final num totalWinnings = group.groupWinningAmount;
      final num myWinnings = _aggregateMyWinningsFromGroupForms(
        forms: groupForms,
        currentUserId: currentUserId,
      );
      return _InfoCard(
        title: 'פרטי הקבוצה',
        rows: [
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
          _InfoRow(
            label: 'זכייה כוללת',
            value:
                hasPublishedResults ? '$totalWinnings ש״ח' : 'טרם פורסם',
          ),
          _InfoRow(
            label: 'הזכייה שלי',
            value:
                hasPublishedResults ? '$myWinnings ש״ח' : 'טרם פורסם',
          ),
        ],
      );
    }

    if (group.isMultiFormBundle) {
      final bool hasPublishedResults = group.resultPublishedAt != null ||
          groupForms.any(
            (form) => form.resultStatus != null || (form.winAmount ?? 0) > 0,
          );
      final num totalWinnings = group.groupWinningAmount > 0
          ? group.groupWinningAmount
          : groupForms.fold<num>(
              0,
              (num total, LotteryGroupForm form) => total + (form.winAmount ?? 0),
            );
      final num myWinnings = _aggregateMyWinningsFromGroupForms(
        forms: groupForms,
        currentUserId: currentUserId,
      );

      return _InfoCard(
        title: 'פרטי הקבוצה',
        rows: [
          _InfoRow(
            label: 'עלות למשתתף',
            value: group.currentPerParticipantCost > 0
                ? '${group.currentPerParticipantCost} ש״ח'
                : 'לא זמין',
          ),
          _InfoRow(
            label: 'מועד שליחה',
            value: formatPresentationDateTime(group.submittedAt),
          ),
          _InfoRow(
            label: 'זכייה כוללת',
            value: hasPublishedResults ? '$totalWinnings ש״ח' : 'טרם פורסם',
          ),
          _InfoRow(
            label: 'הזכייה שלי',
            value: hasPublishedResults ? '$myWinnings ש״ח' : 'טרם פורסם',
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

num _aggregateMyWinningsFromGroupForms({
  required List<LotteryGroupForm> forms,
  required String currentUserId,
}) {
  return forms.fold<num>(0, (num total, LotteryGroupForm form) {
    final num? myShare = extractMyWinningShare(
      winAllocations: form.rawData['winAllocations'],
      userId: currentUserId,
    );
    return total + (myShare ?? 0);
  });
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
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'השתתפות',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          if (membership == null)
            const Text('אין membership פעיל למשתמש זה.')
          else ...[
            Text(
              _myMembershipHeadline(membership!),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (showDebug) ...[
              const SizedBox(height: 8),
              Text('lockedIn: ${membership!.lockedIn}'),
              Text('paymentStatus: ${membership!.paymentStatus.value}'),
              Text('costShare: ${membership!.costShare ?? 0}'),
            ],
            const SizedBox(height: 10),
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
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
                  EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                ),
              ),
              segments: const [
                ButtonSegment(
                  value: LotteryGroupResponseStatus.undecided,
                  label: Text('לא החלטתי'),
                ),
                ButtonSegment(
                  value: LotteryGroupResponseStatus.interested,
                  label: Text('מעוניין'),
                ),
                ButtonSegment(
                  value: LotteryGroupResponseStatus.notInterested,
                  label: Text('לא מעוניין'),
                ),
              ],
              selected: <LotteryGroupResponseStatus>{selectedStatus},
              onSelectionChanged: canEdit
                  ? (selection) {
                      onStatusChanged(selection.first);
                    }
                  : null,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: minimumController,
              enabled: canEdit,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'מינימום משתתפים',
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 10),
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
    final bool collectionStage =
        group.status == LotteryGroupStatus.collectingResponses;
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
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
          const SizedBox(height: 10),
          if (collectionStage)
            ...List<Widget>.generate(memberships.length, (index) {
              final LotteryGroupMembership membership = memberships[index];
              return Column(
                children: [
                  _ParticipantRow(
                    name: _participantDisplayName(membership, index),
                    badgeText: _responseStatusLabel(membership.responseStatus.value),
                    badgeColor: _responseStatusColor(context, membership),
                    trailingText: membership.responseStatus ==
                            LotteryGroupResponseStatus.interested
                        ? 'מינימום: ${membership.minimumParticipantsRequired}'
                        : null,
                    shareText: _displayShareForMembership(membership) != null
                        ? 'חלק מתוכנן: ${_displayShareForMembership(membership)} ש״ח'
                        : null,
                    debugLines: showDebug
                        ? <String>[
                            'userId: ${membership.userId}',
                            'displayName: ${membership.displayName}',
                            'lockedIn: ${membership.lockedIn}',
                            'paymentStatus: ${membership.paymentStatus.value}',
                          ]
                        : const <String>[],
                  ),
                  if (index < memberships.length - 1)
                    Divider(
                      height: 16,
                      color: theme.colorScheme.outlineVariant,
                    ),
                ],
              );
            })
          else ...[
            _ParticipantGroupList(
              title: 'שילמו',
              memberships: memberships
                  .where(
                    (membership) =>
                        membership.lockedIn &&
                        membership.paymentStatus ==
                            LotteryGroupPaymentStatus.paid,
                  )
                  .toList(),
              emptyText: 'אין משתתפים ששילמו עדיין',
              accentColor: Colors.green,
              nameBuilder: _participantDisplayName,
              shareBuilder: (membership) => _displayShareForMembership(membership) != null
                  ? '${_displayShareForMembership(membership)} ש״ח'
                  : null,
            ),
            const SizedBox(height: 12),
            _ParticipantGroupList(
              title: 'לא שילמו',
              memberships: memberships
                  .where(
                    (membership) =>
                        membership.lockedIn &&
                        membership.paymentStatus !=
                            LotteryGroupPaymentStatus.paid,
                  )
                  .toList(),
              emptyText: 'אין משתתפים שממתינים לתשלום',
              accentColor: Colors.red,
              nameBuilder: _participantDisplayName,
              shareBuilder: (membership) => _displayShareForMembership(membership) != null
                  ? '${_displayShareForMembership(membership)} ש״ח'
                  : null,
            ),
          ],
        ],
      ),
    );
  }

  Color _responseStatusColor(
    BuildContext context,
    LotteryGroupMembership membership,
  ) {
    switch (membership.responseStatus) {
      case LotteryGroupResponseStatus.interested:
        return Theme.of(context).colorScheme.primary;
      case LotteryGroupResponseStatus.notInterested:
        return Theme.of(context).colorScheme.error;
      case LotteryGroupResponseStatus.undecided:
        return Theme.of(context).colorScheme.outline;
    }
  }

  String _responseStatusLabel(String rawStatus) {
    switch (rawStatus) {
      case 'interested':
        return 'מעוניין';
      case 'declined':
      case 'not_interested':
        return 'לא מעוניין';
      case 'undecided':
      default:
        return 'לא החלטתי';
    }
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

class _GroupPaymentSection extends StatelessWidget {
  const _GroupPaymentSection({
    required this.userId,
    required this.group,
    required this.membership,
    required this.isPaying,
    required this.onWalletPayment,
    required this.onExternalPayment,
  });

  final String userId;
  final LotteryGroup group;
  final LotteryGroupMembership membership;
  final bool isPaying;
  final VoidCallback onWalletPayment;
  final VoidCallback onExternalPayment;

  @override
  Widget build(BuildContext context) {
    final num payableAmount =
        membership.costShare ?? group.currentPerParticipantCost;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .snapshots(),
      builder: (context, snapshot) {
        final num balance = (snapshot.data?.data()?['balance'] as num?) ?? 0;
        final bool hasEnoughBalance = balance >= payableAmount;
        final bool alreadyPaid =
            membership.paymentStatus == LotteryGroupPaymentStatus.paid;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'תשלום',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _MetaPill(
                    label: 'עלות למשתתף',
                    value: '$payableAmount ש״ח',
                  ),
                  _MetaPill(
                    label: 'יתרה נוכחית',
                    value: '$balance ש״ח',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (alreadyPaid)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'התשלום בוצע',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                )
              else
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    if (hasEnoughBalance)
                      FilledButton(
                        onPressed: isPaying ? null : onWalletPayment,
                        child: isPaying
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('שלם מהיתרה'),
                      ),
                    OutlinedButton(
                      onPressed: isPaying ? null : onExternalPayment,
                      child: Text(
                        hasEnoughBalance
                            ? 'שלם באמצעי אחר'
                            : 'טען כסף ושלם',
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.name,
    required this.badgeText,
    required this.badgeColor,
    this.trailingText,
    this.shareText,
    this.debugLines = const <String>[],
  });

  final String name;
  final String badgeText;
  final Color badgeColor;
  final String? trailingText;
  final String? shareText;
  final List<String> debugLines;

  @override
  Widget build(BuildContext context) {
    final bool hasInlineAmount = trailingText != null && badgeText.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            textDirection: TextDirection.rtl,
            children: [
              Expanded(
                child: Text(
                  name,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (hasInlineAmount)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    trailingText!,
                    textAlign: TextAlign.left,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              if (badgeText.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: badgeColor.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      color: badgeColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          if ((!hasInlineAmount && trailingText != null) || shareText != null) ...[
            const SizedBox(height: 4),
            Text(
              [
                if (!hasInlineAmount) trailingText,
                shareText,
              ].whereType<String>().join(' • '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          for (final String line in debugLines) ...[
            const SizedBox(height: 2),
            Text(line, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _ParticipantGroupList extends StatelessWidget {
  const _ParticipantGroupList({
    required this.title,
    required this.memberships,
    required this.emptyText,
    required this.accentColor,
    required this.nameBuilder,
    required this.shareBuilder,
  });

  final String title;
  final List<LotteryGroupMembership> memberships;
  final String emptyText;
  final Color accentColor;
  final String Function(LotteryGroupMembership membership, int index) nameBuilder;
  final String? Function(LotteryGroupMembership membership) shareBuilder;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.35), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: accentColor,
            ),
          ),
          const SizedBox(height: 8),
          if (memberships.isEmpty)
            Text(emptyText, style: Theme.of(context).textTheme.bodySmall)
          else
            ...List<Widget>.generate(memberships.length, (index) {
              final LotteryGroupMembership membership = memberships[index];
              return Column(
                children: [
                  _ParticipantRow(
                    name: nameBuilder(membership, index),
                    badgeText: '',
                    badgeColor: accentColor,
                    trailingText: shareBuilder(membership),
                  ),
                  if (index < memberships.length - 1)
                    Divider(
                      height: 14,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                ],
              );
            }),
        ],
      ),
    );
  }
}
