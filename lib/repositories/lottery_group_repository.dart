import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/lottery_form.dart';
import '../models/lottery_group.dart';
import '../models/lottery_group_membership.dart';
import '../services/print_ready_artifact_service.dart';

class LotteryGroupInviteBundle {
  const LotteryGroupInviteBundle({
    required this.group,
    required this.membership,
    required this.creatorName,
  });

  final LotteryGroup group;
  final LotteryGroupMembership membership;
  final String creatorName;
}

class UserGroupListItem {
  const UserGroupListItem({
    required this.groupId,
    required this.groupName,
    required this.creatorUserId,
    this.creatorName,
    required this.groupStatus,
    required this.responseStatus,
    required this.minimumParticipantsRequired,
    required this.lockedIn,
    required this.paymentStatus,
    required this.updatedAt,
  });

  final String groupId;
  final String groupName;
  final String creatorUserId;
  /// Display name of the group creator. Falls back to [creatorUserId] when null.
  final String? creatorName;
  final String groupStatus;
  final String responseStatus;
  final int minimumParticipantsRequired;
  final bool lockedIn;
  final String paymentStatus;
  final DateTime? updatedAt;
}

class SubmittedGroupHistoryItem {
  const SubmittedGroupHistoryItem({
    required this.groupId,
    required this.groupName,
    required this.creatorName,
    required this.groupStatus,
    required this.dispatchStatus,
    required this.submittedAt,
    required this.myEffectiveShare,
  });

  final String groupId;
  final String groupName;
  final String creatorName;
  final String groupStatus;
  final String dispatchStatus;
  final DateTime? submittedAt;
  final num myEffectiveShare;
}

class CancelledGroupHistoryItem {
  const CancelledGroupHistoryItem({
    required this.groupId,
    required this.groupName,
    required this.creatorName,
    required this.cancelledAt,
    required this.cancelledByDisplayName,
    required this.myRefundAmount,
  });

  final String groupId;
  final String groupName;
  final String creatorName;
  final DateTime? cancelledAt;
  final String cancelledByDisplayName;
  final num myRefundAmount;
}

class LotteryGroupRepository {
  static const String dispatchStatusQueuedForPrint = 'queued_for_print';
  static const String dispatchStatusPrinted = 'printed';
  static const String dispatchStatusSubmittedToStation = 'submitted_to_station';

  /// When false (default) the submission updates the existing [sourceFormId]
  /// form in-place instead of creating a second snapshot document.
  /// Set to true to revert to the legacy create-new-snapshot behaviour.
  static const bool _useCreateNewSnapshot = false;

  LotteryGroupRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    PrintReadyArtifactService? printReadyArtifactService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'us-central1'),
        _printReadyArtifactService =
            printReadyArtifactService ?? PrintReadyArtifactService();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;
  final PrintReadyArtifactService _printReadyArtifactService;
  static const String _submitFunctionName = 'submitLotteryForm';
  static const String _cancelGroupDraftFunctionName = 'cancelGroupDraft';
  static const String _chargeWalletFunctionName = 'chargeUserWallet';

  DocumentReference<Map<String, dynamic>> _groupRef(String groupId) {
    return _firestore.collection('lottery_groups').doc(groupId);
  }

  DocumentReference<Map<String, dynamic>> _membershipRef(
    String groupId,
    String userId,
  ) {
    return _groupRef(groupId).collection('memberships').doc(userId);
  }

  DocumentReference<Map<String, dynamic>> _activeGroupRef(
    String userId,
    String groupId,
  ) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('active_groups')
        .doc(groupId);
  }

  DocumentReference<Map<String, dynamic>> _submittedGroupRef(
    String userId,
    String groupId,
  ) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('submitted_groups')
        .doc(groupId);
  }

  Stream<LotteryGroup> watchGroup({
    required String groupId,
    required String userId,
  }) async* {
    await _stabilizeAuthForInviteRead(expectedUserId: userId);

    yield* _groupRef(groupId).snapshots().map((snapshot) {
      final Map<String, dynamic>? data = snapshot.data();
      if (!snapshot.exists || data == null) {
        throw StateError('הקבוצה לא נמצאה.');
      }
      return LotteryGroup.fromFirestore(snapshot.id, data);
    });
  }

  Stream<List<LotteryGroupMembership>> watchMemberships({
    required String groupId,
    required String userId,
  }) async* {
    await _stabilizeAuthForInviteRead(expectedUserId: userId);

    yield* _groupRef(groupId)
        .collection('memberships')
        .orderBy('joinedAt')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => LotteryGroupMembership.fromFirestore(doc.data()))
              .toList(),
        );
  }

  Stream<List<UserGroupListItem>> watchGroupsForUser(String userId) async* {
    await _stabilizeAuthForInviteRead(expectedUserId: userId);

    yield* _firestore
        .collection('users')
        .doc(userId)
        .collection('active_groups')
        .snapshots()
        .map((snapshot) {
      final List<UserGroupListItem> items = snapshot.docs.map((doc) {
        final Map<String, dynamic> data = doc.data();
        return UserGroupListItem(
          groupId: doc.id,
          groupName: data['groupName'] as String? ?? doc.id,
          creatorUserId: data['creatorUserId'] as String? ?? '',
          creatorName: data['creatorName'] as String?,
          groupStatus: data['groupStatus'] as String? ?? '',
          responseStatus: data['responseStatus'] as String? ?? '',
          minimumParticipantsRequired:
              (data['minimumParticipantsRequired'] as num?)?.toInt() ?? 1,
          lockedIn: data['lockedIn'] as bool? ?? false,
          paymentStatus: data['paymentStatus'] as String? ?? '',
          updatedAt: _asDateTime(data['updatedAt']),
        );
      }).toList();

      items.sort((a, b) {
        final DateTime aDate = a.updatedAt ?? DateTime(0);
        final DateTime bDate = b.updatedAt ?? DateTime(0);
        return bDate.compareTo(aDate);
      });
      return items;
    });
  }

  Stream<List<SubmittedGroupHistoryItem>> watchSubmittedGroupsForUser(
    String userId,
  ) async* {
    await _stabilizeAuthForInviteRead(expectedUserId: userId);

    yield* _firestore
        .collection('users')
        .doc(userId)
        .collection('submitted_groups')
        .snapshots()
        .map((snapshot) {
      final List<SubmittedGroupHistoryItem> items = snapshot.docs.map((doc) {
        final Map<String, dynamic> data = doc.data();
        return SubmittedGroupHistoryItem(
          groupId: doc.id,
          groupName: data['groupName'] as String? ?? doc.id,
          creatorName: data['creatorName'] as String? ?? 'מנהל הקבוצה',
          groupStatus: data['groupStatus'] as String? ?? '',
          dispatchStatus: data['dispatchStatus'] as String? ?? '',
          submittedAt: _asDateTime(data['submittedAt']),
          myEffectiveShare: (data['myEffectiveShare'] as num?) ?? 0,
        );
      }).toList();

      items.sort((a, b) {
        final DateTime aDate = a.submittedAt ?? DateTime(0);
        final DateTime bDate = b.submittedAt ?? DateTime(0);
        return bDate.compareTo(aDate);
      });
      return items;
    });
  }

  Stream<List<CancelledGroupHistoryItem>> watchCancelledGroupsForUser(
    String userId,
  ) async* {
    await _stabilizeAuthForInviteRead(expectedUserId: userId);

    try {
      await for (final QuerySnapshot<Map<String, dynamic>> snapshot
          in _firestore
              .collection('users')
              .doc(userId)
              .collection('cancelled_groups')
              .snapshots()) {
        final List<CancelledGroupHistoryItem> items = snapshot.docs.map((doc) {
          final Map<String, dynamic> data = doc.data();
          return CancelledGroupHistoryItem(
            groupId: doc.id,
            groupName: data['groupName'] as String? ?? doc.id,
            creatorName: data['creatorName'] as String? ?? 'מנהל הקבוצה',
            cancelledAt: _asDateTime(data['cancelledAt']),
            cancelledByDisplayName:
                data['cancelledByDisplayName'] as String? ?? 'מנהל הקבוצה',
            myRefundAmount: (data['myRefundAmount'] as num?) ?? 0,
          );
        }).toList();

        items.sort((a, b) {
          final DateTime aDate = a.cancelledAt ?? DateTime(0);
          final DateTime bDate = b.cancelledAt ?? DateTime(0);
          return bDate.compareTo(aDate);
        });
        yield items;
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[LotteryGroupRepository] watchCancelledGroupsForUser fallback userId=$userId error=$error',
        );
      }
      yield const <CancelledGroupHistoryItem>[];
    }
  }

  Future<LotteryGroupInviteBundle> loadInvite({
    required String groupId,
    required String inviteToken,
    required String userId,
  }) async {
    await _stabilizeAuthForInviteRead(expectedUserId: userId);

    final DocumentSnapshot<Map<String, dynamic>> groupSnapshot =
        await _groupRef(groupId).get();

    if (!groupSnapshot.exists) {
      throw StateError('הקבוצה לא נמצאה.');
    }

    final LotteryGroup group =
        LotteryGroup.fromFirestore(groupSnapshot.id, groupSnapshot.data()!);
    if (group.inviteToken != inviteToken) {
      throw StateError('קישור ההזמנה אינו תקין.');
    }

    final LotteryGroupMembership membership = await ensureMembershipExists(
      groupId: groupId,
      userId: userId,
    );

    await upsertActiveGroupSummary(
      userId: userId,
      group: group,
      membership: membership,
    );

    return LotteryGroupInviteBundle(
      group: group,
      membership: membership,
      creatorName: group.creatorUserId,
    );
  }

  Future<LotteryGroupMembership> ensureMembershipExists({
    required String groupId,
    required String userId,
  }) async {
    await _stabilizeAuthForInviteRead(expectedUserId: userId);

    final DocumentReference<Map<String, dynamic>> membershipRef =
        _membershipRef(groupId, userId);
    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await membershipRef.get();

    if (snapshot.exists) {
      return LotteryGroupMembership.fromFirestore(snapshot.data()!);
    }

    final DateTime now = DateTime.now();
    final String displayName = _currentAuthDisplayName(userId);
    final Map<String, dynamic> payload = <String, dynamic>{
      'userId': userId,
      'displayName': displayName,
      'groupId': groupId,
      'responseStatus': LotteryGroupResponseStatus.undecided.value,
      'minimumParticipantsRequired': 1,
      'lockedIn': false,
      'paymentStatus': LotteryGroupPaymentStatus.notApplicable.value,
      'joinedAt': now,
    };

    await membershipRef.set(payload);
    return LotteryGroupMembership.fromFirestore(payload);
  }

  Future<void> updateMembershipResponse({
    required String groupId,
    required String userId,
    required LotteryGroupResponseStatus responseStatus,
    required int minimumParticipantsRequired,
  }) async {
    await _stabilizeAuthForInviteRead(expectedUserId: userId);

    final Map<String, dynamic> update = <String, dynamic>{
      'userId': userId,
      'displayName': _currentAuthDisplayName(userId),
      'groupId': groupId,
      'responseStatus': responseStatus.value,
      'minimumParticipantsRequired': minimumParticipantsRequired,
      'respondedAt': DateTime.now(),
    };
    await _membershipRef(groupId, userId).set(update, SetOptions(merge: true));

    final DocumentSnapshot<Map<String, dynamic>> groupSnapshot =
        await _groupRef(groupId).get();
    final DocumentSnapshot<Map<String, dynamic>> membershipSnapshot =
        await _membershipRef(groupId, userId).get();
    final Map<String, dynamic>? groupData = groupSnapshot.data();
    final Map<String, dynamic>? membershipData = membershipSnapshot.data();
    if (groupData != null && membershipData != null) {
      await upsertActiveGroupSummary(
        userId: userId,
        group: LotteryGroup.fromFirestore(groupId, groupData),
        membership: LotteryGroupMembership.fromFirestore(membershipData),
      );
    }
  }

  Future<void> finalizeGroup({
    required String groupId,
    required String creatorUserId,
  }) async {
    await _stabilizeAuthForInviteRead(expectedUserId: creatorUserId);
    final QuerySnapshot<Map<String, dynamic>> prefetchedMemberships =
        await _groupRef(groupId).collection('memberships').get();

    await _firestore.runTransaction((transaction) async {
      final DocumentReference<Map<String, dynamic>> groupRef =
          _groupRef(groupId);
      final DocumentSnapshot<Map<String, dynamic>> groupSnapshot =
          await transaction.get(groupRef);

      final Map<String, dynamic>? groupData = groupSnapshot.data();
      if (!groupSnapshot.exists || groupData == null) {
        throw StateError('הקבוצה לא נמצאה.');
      }

      final LotteryGroup group =
          LotteryGroup.fromFirestore(groupSnapshot.id, groupData);
      if (group.creatorUserId != creatorUserId) {
        throw StateError('רק יוצר הקבוצה יכול לבצע finalize.');
      }
      if (group.status != LotteryGroupStatus.collectingResponses) {
        throw StateError('הקבוצה כבר אינה בשלב איסוף תגובות.');
      }

      final List<DocumentSnapshot<Map<String, dynamic>>> membershipDocs =
          await Future.wait(
        prefetchedMemberships.docs.map(
          (doc) => transaction.get(doc.reference),
        ),
      );

      final List<_MembershipRecord> interested = membershipDocs
          .map(
            (doc) => _MembershipRecord(
              ref: doc.reference,
              membership: LotteryGroupMembership.fromFirestore(
                doc.data() ?? <String, dynamic>{},
              ),
            ),
          )
          .where(
            (record) =>
                record.membership.responseStatus ==
                LotteryGroupResponseStatus.interested,
          )
          .toList();

      if (interested.isEmpty) {
        throw StateError('לא ניתן לבצע finalize ללא משתמשים מעוניינים.');
      }

      final int interestedCount = interested.length;
      final List<_MembershipRecord> finalParticipants = interested
          .where(
            (record) =>
                interestedCount >=
                record.membership.minimumParticipantsRequired,
          )
          .toList();

      if (finalParticipants.isEmpty) {
        throw StateError('אין משתתפים שעומדים בתנאי המינימום שלהם.');
      }

      final int finalParticipantCount = finalParticipants.length;
      final num baseTicketCost = group.baseTicketCost;
      final num currentPerParticipantCost = finalParticipantCount == 0
          ? 0
          : baseTicketCost / finalParticipantCount;
      final DateTime now = DateTime.now();
      final Set<String> finalParticipantIds =
          finalParticipants.map((record) => record.membership.userId).toSet();

      for (final DocumentSnapshot<Map<String, dynamic>> doc in membershipDocs) {
        final LotteryGroupMembership membership =
            LotteryGroupMembership.fromFirestore(
          doc.data() ?? <String, dynamic>{},
        );
        if (finalParticipantIds.contains(membership.userId)) {
          transaction.set(
            doc.reference,
            <String, dynamic>{
              'lockedIn': true,
              'paymentStatus': LotteryGroupPaymentStatus.unpaid.value,
              'costShare': currentPerParticipantCost,
            },
            SetOptions(merge: true),
          );
        } else {
          transaction.set(
            doc.reference,
            <String, dynamic>{
              'lockedIn': false,
              'paymentStatus': LotteryGroupPaymentStatus.notApplicable.value,
              'costShare': null,
            },
            SetOptions(merge: true),
          );
        }
      }

      transaction.set(
        groupRef,
        <String, dynamic>{
          'status': LotteryGroupStatus.awaitingPayments.value,
          'finalizedParticipantCount': finalParticipantCount,
          'finalizedAt': now,
          'updatedAt': now,
          'currentPerParticipantCost': currentPerParticipantCost,
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> simulatePayment({
    required String groupId,
    required String userId,
  }) async {
    await _stabilizeAuthForInviteRead(expectedUserId: userId);
    final QuerySnapshot<Map<String, dynamic>> prefetchedMemberships =
        await _groupRef(groupId).collection('memberships').get();

    await _firestore.runTransaction((transaction) async {
      final DocumentReference<Map<String, dynamic>> groupRef =
          _groupRef(groupId);
      final DocumentReference<Map<String, dynamic>> membershipRef =
          _membershipRef(groupId, userId);

      final DocumentSnapshot<Map<String, dynamic>> groupSnapshot =
          await transaction.get(groupRef);
      final DocumentSnapshot<Map<String, dynamic>> currentMembershipSnapshot =
          await transaction.get(membershipRef);

      final Map<String, dynamic>? groupData = groupSnapshot.data();
      final Map<String, dynamic>? currentMembershipData =
          currentMembershipSnapshot.data();
      if (!groupSnapshot.exists || groupData == null) {
        throw StateError('הקבוצה לא נמצאה.');
      }
      if (!currentMembershipSnapshot.exists || currentMembershipData == null) {
        throw StateError('Membership לא נמצא.');
      }

      final LotteryGroup group =
          LotteryGroup.fromFirestore(groupSnapshot.id, groupData);
      final LotteryGroupMembership currentMembership =
          LotteryGroupMembership.fromFirestore(currentMembershipData);

      if (!currentMembership.lockedIn) {
        throw StateError('רק משתתפים שננעלו יכולים לשלם.');
      }
      if (currentMembership.paymentStatus == LotteryGroupPaymentStatus.paid) {
        return;
      }

      final DateTime now = DateTime.now();
      final List<LotteryGroupMembership> memberships = await Future.wait(
        prefetchedMemberships.docs.map((doc) async {
          final DocumentSnapshot<Map<String, dynamic>> snapshot =
              doc.reference.path == membershipRef.path
                  ? currentMembershipSnapshot
                  : await transaction.get(doc.reference);
          final Map<String, dynamic> data = Map<String, dynamic>.from(
            snapshot.data() ?? <String, dynamic>{},
          );
          if (doc.reference.path == membershipRef.path) {
            data['paymentStatus'] = LotteryGroupPaymentStatus.paid.value;
            data['paidAt'] = now;
          }
          return LotteryGroupMembership.fromFirestore(data);
        }),
      );

      transaction.set(
        membershipRef,
        <String, dynamic>{
          'paymentStatus': LotteryGroupPaymentStatus.paid.value,
          'paidAt': now,
        },
        SetOptions(merge: true),
      );

      final List<LotteryGroupMembership> paidLockedInMemberships = memberships
          .where(
            (membership) =>
                membership.lockedIn &&
                membership.paymentStatus == LotteryGroupPaymentStatus.paid,
          )
          .toList();
      final List<LotteryGroupMembership> validPaidMemberships =
          _computeStableValidMemberships(paidLockedInMemberships);
      final bool readyForSubmission = validPaidMemberships.isNotEmpty;

      if (readyForSubmission) {
        transaction.set(
          groupRef,
          <String, dynamic>{
            'status': LotteryGroupStatus.readyForSubmission.value,
            'currentPerParticipantCost':
                group.baseTicketCost / validPaidMemberships.length,
            'updatedAt': now,
          },
          SetOptions(merge: true),
        );
      } else if (group.status != LotteryGroupStatus.awaitingPayments) {
        transaction.set(
          groupRef,
          <String, dynamic>{
            'status': LotteryGroupStatus.awaitingPayments.value,
            'updatedAt': now,
          },
          SetOptions(merge: true),
        );
      }
    });

    final DocumentSnapshot<Map<String, dynamic>> groupSnapshot =
        await _groupRef(groupId).get();
    final DocumentSnapshot<Map<String, dynamic>> membershipSnapshot =
        await _membershipRef(groupId, userId).get();
    final Map<String, dynamic>? groupData = groupSnapshot.data();
    final Map<String, dynamic>? membershipData = membershipSnapshot.data();
    if (groupData != null && membershipData != null) {
      await upsertActiveGroupSummary(
        userId: userId,
        group: LotteryGroup.fromFirestore(groupId, groupData),
        membership: LotteryGroupMembership.fromFirestore(membershipData),
      );
    }
  }

  Future<void> chargeUserWalletForGroup({
    required String groupId,
    required String userId,
    required num amount,
  }) async {
    await _stabilizeAuthForInviteRead(expectedUserId: userId);
    final User? currentUser = _auth.currentUser;
    if (currentUser == null || currentUser.uid != userId) {
      throw FirebaseFunctionsException(
        code: 'permission-denied',
        message: 'Authenticated user does not match the wallet owner.',
      );
    }

    final String token = await currentUser.getIdToken(true) ?? '';
    final HttpsCallable callable =
        _functions.httpsCallable(_chargeWalletFunctionName);
    await callable.call(<String, dynamic>{
      'idToken': token,
      'userId': userId,
      'groupId': groupId,
      'amount': amount,
    });

    final DocumentSnapshot<Map<String, dynamic>> groupSnapshot =
        await _groupRef(groupId).get();
    final DocumentSnapshot<Map<String, dynamic>> membershipSnapshot =
        await _membershipRef(groupId, userId).get();
    final Map<String, dynamic>? groupData = groupSnapshot.data();
    final Map<String, dynamic>? membershipData = membershipSnapshot.data();
    if (groupData != null && membershipData != null) {
      await upsertActiveGroupSummary(
        userId: userId,
        group: LotteryGroup.fromFirestore(groupId, groupData),
        membership: LotteryGroupMembership.fromFirestore(membershipData),
      );
    }
  }

  Future<void> cancelGroupDraft({
    required String groupId,
    required String cancelledByUserId,
  }) async {
    debugPrint(
      '[LotteryGroupRepository] cancelGroupDraft start groupId=$groupId cancelledByUserId=$cancelledByUserId',
    );
    await _stabilizeAuthForInviteRead(expectedUserId: cancelledByUserId);
    final User? currentUser = _auth.currentUser;
    if (currentUser == null || currentUser.uid != cancelledByUserId) {
      throw StateError('Authenticated user does not match the group creator.');
    }

    final String token = await currentUser.getIdToken(true) ?? '';
    final HttpsCallable callable =
        _functions.httpsCallable(_cancelGroupDraftFunctionName);

    try {
      await callable.call(<String, dynamic>{
        'idToken': token,
        'groupId': groupId,
      });
      debugPrint(
        '[LotteryGroupRepository] cancelGroupDraft success groupId=$groupId',
      );
    } on FirebaseFunctionsException catch (error) {
      debugPrint(
        '[LotteryGroupRepository] cancelGroupDraft callable failed groupId=$groupId code=${error.code} message=${error.message}',
      );
      if (error.code == 'not-found') {
        throw StateError(
          'פונקציית ביטול הקבוצה עדיין לא נפרסה. יש לפרוס Cloud Functions ו-Firestore Rules.',
        );
      }
      if (error.code == 'permission-denied') {
        throw StateError(
          'אין עדיין הרשאה לביטול קבוצתי. יש לפרוס את חוקי Firestore המעודכנים.',
        );
      }
      throw StateError(error.message ?? 'ביטול הטופס הקבוצתי נכשל.');
    }
  }

  Future<String> submitGroupTicket({
    required String groupId,
    required String creatorUserId,
  }) async {
    await _stabilizeAuthForInviteRead(expectedUserId: creatorUserId);
    final QuerySnapshot<Map<String, dynamic>> prefetchedMemberships =
        await _groupRef(groupId).collection('memberships').get();
    final DocumentSnapshot<Map<String, dynamic>> initialGroupSnapshot =
        await _groupRef(groupId).get();
    final Map<String, dynamic>? initialGroupData = initialGroupSnapshot.data();
    if (!initialGroupSnapshot.exists || initialGroupData == null) {
      throw StateError('הקבוצה לא נמצאה.');
    }
    final LotteryGroup initialGroup = LotteryGroup.fromFirestore(
      initialGroupSnapshot.id,
      initialGroupData,
    );

    // Always call the Cloud Function — it generates the fingerprint.
    // In the new path the returned doc is a temporary fingerprint carrier that
    // we read and then delete; in the legacy path it becomes the submitted form.
    final String tempFormId = await _submitSnapshotViaCallable(
      creatorUserId: creatorUserId,
      tables: initialGroup.tables.map((table) => table.toMap()).toList(),
    );
    final DocumentReference<Map<String, dynamic>> tempFormRef = _firestore
        .collection('users')
        .doc(creatorUserId)
        .collection('forms')
        .doc(tempFormId);

    if (!_useCreateNewSnapshot) {
      // ── NEW PATH: update the existing sourceFormId form in-place ──────────
      final String sourceFormId = initialGroup.sourceFormId;
      if (sourceFormId.isEmpty) {
        await tempFormRef.delete();
        throw StateError('sourceFormId is missing on group $groupId.');
      }

      // Read ALL fields written by the callable to the temp doc.
      // These are the server-computed values we must copy to the original form.
      final DocumentSnapshot<Map<String, dynamic>> tempFormSnapshot =
          await tempFormRef.get();
      final Map<String, dynamic>? tempFormData = tempFormSnapshot.data();
      if (!tempFormSnapshot.exists || tempFormData == null) {
        throw StateError(
          'Temp form doc $tempFormId not found after callable.',
        );
      }
      final String? ticketFingerprint =
          tempFormData['ticketFingerprint'] as String?;
      final String? ticketFingerprintSource =
          tempFormData['ticketFingerprintSource'] as String?;
      final int? lotteryId = (tempFormData['lotteryId'] as num?)?.toInt();
      final dynamic salesCloseAt = tempFormData['salesCloseAt'];
      final int? fingerprintVersion =
          (tempFormData['fingerprintVersion'] as num?)?.toInt();
      final String? resultStatus = tempFormData['resultStatus'] as String?;

      final DocumentReference<Map<String, dynamic>> sourceFormRef = _firestore
          .collection('users')
          .doc(creatorUserId)
          .collection('forms')
          .doc(sourceFormId);

      List<String> submittedParticipantUserIds = <String>[];
      String creatorDisplayName = creatorUserId;

      try {
        await _firestore.runTransaction((transaction) async {
          final DocumentReference<Map<String, dynamic>> groupRef =
              _groupRef(groupId);
          final DocumentSnapshot<Map<String, dynamic>> groupSnapshot =
              await transaction.get(groupRef);
          final DocumentSnapshot<Map<String, dynamic>> sourceFormSnapshot =
              await transaction.get(sourceFormRef);

          final Map<String, dynamic>? groupData = groupSnapshot.data();
          if (!groupSnapshot.exists || groupData == null) {
            throw StateError('הקבוצה לא נמצאה.');
          }
          if (!sourceFormSnapshot.exists) {
            throw StateError(
              'הטופס המקורי sourceFormId=$sourceFormId לא נמצא.',
            );
          }

          final LotteryGroup group =
              LotteryGroup.fromFirestore(groupSnapshot.id, groupData);
          if (group.creatorUserId != creatorUserId) {
            throw StateError('רק יוצר הקבוצה יכול להגיש את הטופס.');
          }
          if (group.status == LotteryGroupStatus.submitted) {
            throw StateError('הקבוצה כבר הוגשה.');
          }

          final List<DocumentSnapshot<Map<String, dynamic>>> membershipDocs =
              await Future.wait(
            prefetchedMemberships.docs.map(
              (doc) => transaction.get(doc.reference),
            ),
          );

          final List<LotteryGroupMembership> lockedInPaidMemberships =
              membershipDocs
                  .map(
                    (doc) => LotteryGroupMembership.fromFirestore(
                      doc.data() ?? <String, dynamic>{},
                    ),
                  )
                  .where(
                    (membership) =>
                        membership.lockedIn &&
                        membership.paymentStatus ==
                            LotteryGroupPaymentStatus.paid,
                  )
                  .toList();

          final List<LotteryGroupMembership> validPaidMemberships =
              _computeStableValidMemberships(lockedInPaidMemberships);

          if (validPaidMemberships.isEmpty) {
            throw StateError('אין קבוצת משלמים תקפה להגשה כרגע.');
          }

          final DateTime now = DateTime.now();
          final int effectiveParticipantCount = validPaidMemberships.length;
          final num effectiveCostPerPaidParticipant =
              group.baseTicketCost / effectiveParticipantCount;
          submittedParticipantUserIds = validPaidMemberships
              .map((membership) => membership.userId)
              .toList();
          creatorDisplayName = _creatorDisplayNameFromMemberships(
            memberships: membershipDocs
                .map(
                  (doc) => LotteryGroupMembership.fromFirestore(
                    doc.data() ?? <String, dynamic>{},
                  ),
                )
                .toList(),
            creatorUserId: group.creatorUserId,
          );
          final List<Map<String, dynamic>> paidParticipants =
              validPaidMemberships
                  .map(
                    (membership) => <String, dynamic>{
                      'userId': membership.userId,
                      'displayName': membership.displayName,
                      'minimumParticipantsRequired':
                          membership.minimumParticipantsRequired,
                      'paymentStatus': membership.paymentStatus.value,
                      'costShare': effectiveCostPerPaidParticipant,
                      'paidAt': membership.paidAt,
                    },
                  )
                  .toList();

          // Update the original locked form in-place.
          // 'source: group_snapshot' keeps it out of watchSubmittedForms
          // (personal submissions list), while still appearing in the operator
          // console collectionGroup('forms') query (no source filter there).
          // All server-computed fields are copied from the temp doc so nothing
          // is lost (lotteryId, salesCloseAt, fingerprint, resultStatus, etc.).
          transaction.set(
            sourceFormRef,
            <String, dynamic>{
              'formId': sourceFormId,
              'status': 'submitted',
              'source': 'group_snapshot',
              'submittedAt': now,
              'groupId': group.groupId,
              'submissionType': 'group',
              'creatorUserId': creatorUserId,
              'creatorDisplayName': creatorDisplayName,
              'userId': creatorUserId,
              'groupName': group.groupName,
              'isEditable': false,
              'updatedAt': now,
              'dispatchStatus': dispatchStatusQueuedForPrint,
              'baseTicketCost': group.baseTicketCost,
              'effectiveParticipantCount': effectiveParticipantCount,
              'effectiveCostPerPaidParticipant':
                  effectiveCostPerPaidParticipant,
              'submittedParticipantUserIds': submittedParticipantUserIds,
              'paidParticipants': paidParticipants,
              // ── Fields copied from the Cloud Function's temp doc ──────────
              if (ticketFingerprint != null)
                'ticketFingerprint': ticketFingerprint,
              if (ticketFingerprintSource != null)
                'ticketFingerprintSource': ticketFingerprintSource,
              if (lotteryId != null) 'lotteryId': lotteryId,
              if (salesCloseAt != null) 'salesCloseAt': salesCloseAt,
              if (fingerprintVersion != null)
                'fingerprintVersion': fingerprintVersion,
              if (resultStatus != null) 'resultStatus': resultStatus,
            },
            SetOptions(merge: true),
          );

          transaction.set(
            groupRef,
            <String, dynamic>{
              'status': LotteryGroupStatus.submitted.value,
              'submittedAt': now,
              'submittedFormId': sourceFormId,
              'dispatchStatus': dispatchStatusQueuedForPrint,
              'updatedAt': now,
              'currentPerParticipantCost': effectiveCostPerPaidParticipant,
            },
            SetOptions(merge: true),
          );

          for (final LotteryGroupMembership membership
              in validPaidMemberships) {
            transaction.set(
              _submittedGroupRef(membership.userId, group.groupId),
              <String, dynamic>{
                'groupId': group.groupId,
                'groupName': group.groupName,
                'creatorUserId': group.creatorUserId,
                'creatorName': creatorDisplayName,
                'groupStatus': LotteryGroupStatus.submitted.value,
                'dispatchStatus': dispatchStatusQueuedForPrint,
                'submittedAt': now,
                'submittedFormId': sourceFormId,
                'myEffectiveShare': effectiveCostPerPaidParticipant,
                'updatedAt': now,
              },
            );
          }
        });
      } catch (error) {
        // Transaction failed — clean up the temp fingerprint doc.
        await tempFormRef.delete();
        rethrow;
      }

      // Transaction succeeded — remove the temp doc (all fields already merged).
      await tempFormRef.delete();
      await _generatePrintReadyArtifactAndSync(
        creatorUserId: creatorUserId,
        formId: sourceFormId,
        groupId: groupId,
        participantUserIds: submittedParticipantUserIds,
        creatorDisplayName: creatorDisplayName,
      );

      return sourceFormId;
    }

    // ── LEGACY PATH (_useCreateNewSnapshot = true) ─────────────────────────
    // Kept for reference. DO NOT enable without careful data migration.
    // The callable already created tempFormRef as the "submitted" form doc.
    //
    // final DocumentReference<Map<String, dynamic>> submittedFormRef = tempFormRef;
    // final String submittedFormId = tempFormId;
    // List<String> submittedParticipantUserIds = <String>[];
    // String creatorDisplayName = creatorUserId;
    //
    // try {
    //   await _firestore.runTransaction((transaction) async {
    //     final DocumentReference<Map<String, dynamic>> groupRef =
    //         _groupRef(groupId);
    //     final DocumentSnapshot<Map<String, dynamic>> groupSnapshot =
    //         await transaction.get(groupRef);
    //     final DocumentSnapshot<Map<String, dynamic>> submittedFormSnapshot =
    //         await transaction.get(submittedFormRef);
    //
    //     final Map<String, dynamic>? groupData = groupSnapshot.data();
    //     if (!groupSnapshot.exists || groupData == null) {
    //       throw StateError('הקבוצה לא נמצאה.');
    //     }
    //     if (!submittedFormSnapshot.exists) {
    //       throw StateError('הטופס שנוצר עבור ההגשה לא נמצא.');
    //     }
    //
    //     final LotteryGroup group =
    //         LotteryGroup.fromFirestore(groupSnapshot.id, groupData);
    //     if (group.creatorUserId != creatorUserId) {
    //       throw StateError('רק יוצר הקבוצה יכול להגיש את הטופס.');
    //     }
    //     if (group.status == LotteryGroupStatus.submitted) {
    //       throw StateError('הקבוצה כבר הוגשה.');
    //     }
    //
    //     ... [membership, cost, participant computation — identical to new path]
    //
    //     transaction.set(
    //       submittedFormRef,
    //       <String, dynamic>{
    //         'formId': submittedFormId,
    //         'groupId': group.groupId,
    //         'submissionType': 'group',
    //         'creatorUserId': creatorUserId,
    //         'creatorDisplayName': creatorDisplayName,
    //         'userId': creatorUserId,
    //         'groupName': group.groupName,
    //         'isEditable': false,
    //         'updatedAt': now,
    //         'dispatchStatus': dispatchStatusQueuedForPrint,
    //         'baseTicketCost': group.baseTicketCost,
    //         'effectiveParticipantCount': effectiveParticipantCount,
    //         'effectiveCostPerPaidParticipant': effectiveCostPerPaidParticipant,
    //         'submittedParticipantUserIds': submittedParticipantUserIds,
    //         'paidParticipants': paidParticipants,
    //         // Note: no ticketFingerprint/ticketFingerprintSource here —
    //         // those were already written by the callable on the same doc.
    //       },
    //       SetOptions(merge: true),
    //     );
    //
    //     transaction.set(
    //       groupRef,
    //       <String, dynamic>{
    //         'status': LotteryGroupStatus.submitted.value,
    //         'submittedAt': now,
    //         'submittedFormId': submittedFormRef.id, // ← new doc, not sourceFormId
    //         'dispatchStatus': dispatchStatusQueuedForPrint,
    //         'updatedAt': now,
    //         'currentPerParticipantCost': effectiveCostPerPaidParticipant,
    //       },
    //       SetOptions(merge: true),
    //     );
    //
    //     for (final LotteryGroupMembership membership in validPaidMemberships) {
    //       transaction.set(
    //         _submittedGroupRef(membership.userId, group.groupId),
    //         <String, dynamic>{
    //           ...
    //           'submittedFormId': submittedFormRef.id,
    //           ...
    //         },
    //       );
    //     }
    //   });
    // } catch (error) {
    //   await submittedFormRef.delete();
    //   rethrow;
    // }
    //
    // await _generatePrintReadyArtifactAndSync(
    //   creatorUserId: creatorUserId,
    //   formId: submittedFormId,
    //   groupId: groupId,
    //   participantUserIds: submittedParticipantUserIds,
    //   creatorDisplayName: creatorDisplayName,
    // );
    //
    // return submittedFormId;

    throw UnimplementedError(
      'Legacy path (_useCreateNewSnapshot = true) is disabled.',
    );
  }

  Future<void> updateSubmittedGroupDispatchStatus({
    required String groupId,
    required String creatorUserId,
    required String dispatchStatus,
  }) async {
    final DateTime now = DateTime.now();
    await _firestore.runTransaction((transaction) async {
      final DocumentReference<Map<String, dynamic>> groupRef =
          _groupRef(groupId);
      final DocumentSnapshot<Map<String, dynamic>> groupSnapshot =
          await transaction.get(groupRef);
      final Map<String, dynamic>? groupData = groupSnapshot.data();
      if (!groupSnapshot.exists || groupData == null) {
        throw StateError('הקבוצה לא נמצאה.');
      }

      final LotteryGroup group =
          LotteryGroup.fromFirestore(groupSnapshot.id, groupData);
      if (group.creatorUserId != creatorUserId) {
        throw StateError('רק יוצר הקבוצה יכול לעדכן את מצב השליחה.');
      }
      final String? submittedFormId = group.submittedFormId;
      if (submittedFormId == null || submittedFormId.isEmpty) {
        throw StateError('לא נמצא טופס שהוגש עבור הקבוצה.');
      }

      final DocumentReference<Map<String, dynamic>> formRef = _firestore
          .collection('users')
          .doc(creatorUserId)
          .collection('forms')
          .doc(submittedFormId);
      final DocumentSnapshot<Map<String, dynamic>> formSnapshot =
          await transaction.get(formRef);
      final Map<String, dynamic>? formData = formSnapshot.data();
      if (!formSnapshot.exists || formData == null) {
        throw StateError('הטופס שהוגש לא נמצא.');
      }

      final List<String> participantUserIds =
          (formData['submittedParticipantUserIds'] as List<dynamic>? ??
                  <dynamic>[])
              .whereType<String>()
              .toList();
      final Map<String, dynamic> dispatchUpdate = <String, dynamic>{
        'dispatchStatus': dispatchStatus,
        'updatedAt': now,
      };
      if (dispatchStatus == dispatchStatusPrinted) {
        dispatchUpdate['printedAt'] = now;
      }
      if (dispatchStatus == dispatchStatusSubmittedToStation) {
        dispatchUpdate['submittedToStationAt'] = now;
        dispatchUpdate['printedAt'] = formData['printedAt'] ?? now;
      }

      transaction.set(formRef, dispatchUpdate, SetOptions(merge: true));
      transaction.set(groupRef, dispatchUpdate, SetOptions(merge: true));

      for (final String userId in participantUserIds) {
        transaction.set(
          _submittedGroupRef(userId, groupId),
          <String, dynamic>{
            ...dispatchUpdate,
            'groupStatus': LotteryGroupStatus.submitted.value,
          },
          SetOptions(merge: true),
        );
      }
    });
  }

  Future<void> upsertActiveGroupSummary({
    required String userId,
    required LotteryGroup group,
    required LotteryGroupMembership membership,
    String? creatorName,
  }) {
    return _activeGroupRef(userId, group.groupId).set(
      <String, dynamic>{
        'groupId': group.groupId,
        'groupName': group.groupName,
        'creatorUserId': group.creatorUserId,
        if (creatorName != null) 'creatorName': creatorName,
        'groupStatus': group.status.value,
        'responseStatus': membership.responseStatus.value,
        'minimumParticipantsRequired': membership.minimumParticipantsRequired,
        'lockedIn': membership.lockedIn,
        'paymentStatus': membership.paymentStatus.value,
        'costShare': _effectiveSummaryCostShare(
          group: group,
          membership: membership,
        ),
        'updatedAt': DateTime.now(),
      },
      SetOptions(merge: true),
    );
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

  String _currentAuthDisplayName(String userId) {
    if (_auth.currentUser?.uid == userId) {
      final String? displayName = _auth.currentUser?.displayName?.trim();
      if (displayName != null && displayName.isNotEmpty) {
        return displayName;
      }
    }
    return userId;
  }

  static String _creatorDisplayNameFromMemberships({
    required List<LotteryGroupMembership> memberships,
    required String creatorUserId,
  }) {
    for (final LotteryGroupMembership membership in memberships) {
      if (membership.userId == creatorUserId &&
          membership.displayName.trim().isNotEmpty) {
        return membership.displayName;
      }
    }
    return creatorUserId;
  }

  static List<LotteryGroupMembership> _computeStableValidMemberships(
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

  static num? _effectiveSummaryCostShare({
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

  Future<void> _stabilizeAuthForInviteRead({
    required String expectedUserId,
  }) async {
    if (_auth.currentUser?.uid == expectedUserId) {
      await _auth.currentUser?.getIdToken();
      return;
    }

    try {
      final User user = await _auth
          .authStateChanges()
          .firstWhere(
            (user) => user?.uid == expectedUserId,
          )
          .timeout(const Duration(seconds: 3)) as User;
      await user.getIdToken();
    } catch (_) {
      // Let the Firestore call fail normally if auth still isn't ready.
    }
  }

  Future<String> _submitSnapshotViaCallable({
    required String creatorUserId,
    required List<Map<String, dynamic>> tables,
  }) async {
    final User? currentUser = _auth.currentUser;
    if (currentUser == null || currentUser.uid != creatorUserId) {
      throw FirebaseFunctionsException(
        code: 'permission-denied',
        message: 'Authenticated user does not match the group creator.',
      );
    }

    final String token = await currentUser.getIdToken(true) ?? '';
    final HttpsCallable callable =
        _functions.httpsCallable(_submitFunctionName);
    final HttpsCallableResult<dynamic> result = await callable.call(
      <String, dynamic>{
        'idToken': token,
        'tables': tables,
        'source': 'group_snapshot',
        'version': 1,
      },
    );

    final Map<String, dynamic> data =
        Map<String, dynamic>.from(result.data as Map<dynamic, dynamic>);
    final String? formId = data['formId'] as String?;
    if (formId == null || formId.isEmpty) {
      throw StateError('submitLotteryForm did not return a valid formId.');
    }
    return formId;
  }

  Future<void> _generatePrintReadyArtifactAndSync({
    required String creatorUserId,
    required String formId,
    required String groupId,
    required List<String> participantUserIds,
    required String creatorDisplayName,
  }) async {
    try {
      final DocumentReference<Map<String, dynamic>> formRef = _firestore
          .collection('users')
          .doc(creatorUserId)
          .collection('forms')
          .doc(formId);
      final DocumentSnapshot<Map<String, dynamic>> formSnapshot =
          await formRef.get();
      final Map<String, dynamic>? formData = formSnapshot.data();
      if (!formSnapshot.exists || formData == null) {
        return;
      }

      final LotteryForm form = LotteryForm.fromFirestore(formId, formData);
      final PrintReadyArtifactResult artifact =
          await _printReadyArtifactService.generateForSubmittedForm(form: form);

      final WriteBatch batch = _firestore.batch();
      final Map<String, dynamic> artifactUpdate = <String, dynamic>{
        'printReadyUrl': artifact.downloadUrl,
        'printReadyStoragePath': artifact.storagePath,
        'printReadyGeneratedAt': artifact.generatedAt,
        'dispatchStatus': dispatchStatusQueuedForPrint,
        'updatedAt': artifact.generatedAt,
      };
      batch.set(formRef, artifactUpdate, SetOptions(merge: true));
      batch.set(_groupRef(groupId), artifactUpdate, SetOptions(merge: true));
      for (final String userId in participantUserIds) {
        batch.set(
          _submittedGroupRef(userId, groupId),
          <String, dynamic>{
            'groupId': groupId,
            'creatorName': creatorDisplayName,
            ...artifactUpdate,
          },
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    } catch (_) {
      // The submitted form is already valid. If artifact generation fails,
      // keep the submission and allow lifecycle recovery later.
    }
  }
}

class _MembershipRecord {
  const _MembershipRecord({
    required this.ref,
    required this.membership,
  });

  final DocumentReference<Map<String, dynamic>> ref;
  final LotteryGroupMembership membership;
}
