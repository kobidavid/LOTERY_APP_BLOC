import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

import '../models/lottery_form.dart';
import '../models/lottery_group.dart';
import '../models/lottery_table.dart';

DateTime? _repositoryAsDateTime(dynamic value) {
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DateTime) {
    return value;
  }
  return null;
}

LotteryResultStatus? _repositoryResultStatusFromString(String? value) {
  switch (value) {
    case 'waiting_for_results':
      return LotteryResultStatus.waitingForResults;
    case 'checked':
      return LotteryResultStatus.checked;
    case 'winner':
      return LotteryResultStatus.winner;
    case 'loser':
      return LotteryResultStatus.loser;
    default:
      return null;
  }
}

class PersonalSubmissionDraftPayload {
  const PersonalSubmissionDraftPayload({
    required this.form,
    required this.cost,
    required this.tableCount,
    required this.isDoubleMode,
    required this.displayOrder,
  });

  final LotteryForm form;
  final num cost;
  final int tableCount;
  final bool isDoubleMode;
  final int displayOrder;
}

class PersonalSubmittedBundleForm {
  const PersonalSubmittedBundleForm({
    required this.formId,
    required this.displayOrder,
    required this.tableCount,
    required this.cost,
    required this.isDoubleMode,
    required this.tables,
    required this.submittedAt,
    required this.printedAt,
    required this.submittedToStationAt,
    required this.resultStatus,
    required this.winAmount,
    required this.receiptUrl,
  });

  final String formId;
  final int displayOrder;
  final int tableCount;
  final num cost;
  final bool isDoubleMode;
  final List<LotteryTable> tables;
  final DateTime? submittedAt;
  final DateTime? printedAt;
  final DateTime? submittedToStationAt;
  final LotteryResultStatus? resultStatus;
  final num winAmount;
  final String? receiptUrl;

  factory PersonalSubmittedBundleForm.fromFirestore(
    String formId,
    Map<String, dynamic> data,
  ) {
    final List<dynamic> rawTables = data['tables'] as List<dynamic>? ?? <dynamic>[];
    return PersonalSubmittedBundleForm(
      formId: formId,
      displayOrder: (data['displayOrder'] as num?)?.toInt() ?? 0,
      tableCount: (data['tableCount'] as num?)?.toInt() ?? rawTables.length,
      cost: (data['cost'] as num?) ?? 0,
      isDoubleMode: data['isDoubleMode'] as bool? ?? false,
      tables: rawTables
          .map((item) => LotteryTable.fromMap(item as Map<String, dynamic>))
          .toList(),
      submittedAt: _repositoryAsDateTime(data['submittedAt']),
      printedAt: _repositoryAsDateTime(data['printedAt']),
      submittedToStationAt: _repositoryAsDateTime(data['submittedToStationAt']),
      resultStatus: _repositoryResultStatusFromString(
        data['resultStatus'] as String?,
      ),
      winAmount: (data['winAmount'] as num?) ?? 0,
      receiptUrl: _extractSubmissionReceiptUrl(data),
    );
  }
}

class PersonalSubmittedBundle {
  const PersonalSubmittedBundle({
    required this.submissionId,
    required this.userId,
    required this.formCount,
    required this.totalCost,
    required this.submittedAt,
    required this.forms,
  });

  final String submissionId;
  final String userId;
  final int formCount;
  final num totalCost;
  final DateTime? submittedAt;
  final List<PersonalSubmittedBundleForm> forms;

  int get totalTableCount =>
      forms.fold<int>(0, (int total, form) => total + form.tableCount);
}

class LotteryFormRepository {
  LotteryFormRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'us-central1'),
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;
  static const String _submitFunctionName = 'submitLotteryForm';
  static const String _chargeWalletFunctionName = 'chargeUserWallet';
  static const int _regularLottoPairPriceNis = 6;
  static const String _groupSnapshotSource = 'group_snapshot';

  CollectionReference<Map<String, dynamic>> _formsRef(String userId) {
    return _firestore.collection('users').doc(userId).collection('forms');
  }

  CollectionReference<Map<String, dynamic>> _groupsRef() {
    return _firestore.collection('lottery_groups');
  }

  CollectionReference<Map<String, dynamic>> _submissionsRef(String userId) {
    return _firestore.collection('users').doc(userId).collection('submissions');
  }

  Stream<List<LotteryForm>> watchSubmittedForms(String userId) {
    return _formsRef(userId).snapshots().map(
          (snapshot) => _mapForms(snapshot)
            ..retainWhere(
              (form) =>
                  form.status == LotteryFormStatus.submitted &&
                  form.source != _groupSnapshotSource,
            )
            ..sort((a, b) => (b.submittedAt ?? DateTime(0)).compareTo(
                  a.submittedAt ?? DateTime(0),
                )),
        );
  }

  Stream<List<PersonalSubmittedBundle>> watchPersonalSubmissionBundles(
    String userId,
  ) {
    return _submissionsRef(userId)
        .where('type', isEqualTo: 'personal')
        .where('status', isEqualTo: 'submitted')
        .snapshots()
        .asyncMap((snapshot) async {
      final List<PersonalSubmittedBundle> bundles =
          await Future.wait<PersonalSubmittedBundle>(
        snapshot.docs.map((doc) async {
          final QuerySnapshot<Map<String, dynamic>> formsSnapshot =
              await doc.reference.collection('forms').get();
          final List<PersonalSubmittedBundleForm> forms = formsSnapshot.docs
              .map(
                (formDoc) => PersonalSubmittedBundleForm.fromFirestore(
                  formDoc.id,
                  formDoc.data(),
                ),
              )
              .toList()
            ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
          final Map<String, dynamic> data = doc.data();
          return PersonalSubmittedBundle(
            submissionId: doc.id,
            userId: data['userId'] as String? ?? userId,
            formCount: (data['formCount'] as num?)?.toInt() ?? forms.length,
            totalCost: (data['totalCost'] as num?) ??
                forms.fold<num>(0, (num total, form) => total + form.cost),
            submittedAt: _repositoryAsDateTime(data['submittedAt']),
            forms: forms,
          );
        }),
      );
      bundles.sort((a, b) => (b.submittedAt ?? DateTime(0))
          .compareTo(a.submittedAt ?? DateTime(0)));
      return bundles;
    });
  }

  Stream<List<PersonalSubmittedBundleForm>> watchPersonalSubmissionBundleForms({
    required String userId,
    required String submissionId,
  }) {
    return _submissionsRef(userId)
        .doc(submissionId)
        .collection('forms')
        .snapshots()
        .map((snapshot) {
      final List<PersonalSubmittedBundleForm> forms = snapshot.docs
          .map(
            (doc) => PersonalSubmittedBundleForm.fromFirestore(doc.id, doc.data()),
          )
          .toList()
        ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
      return forms;
    });
  }

  Stream<List<LotteryForm>> watchSavedForms(String userId) {
    return _formsRef(userId).snapshots().map(
          (snapshot) => _mapForms(snapshot)
            ..retainWhere(
              (form) => form.status == LotteryFormStatus.saved,
            )
            ..sort(
                (a, b) => (b.savedAt ?? b.updatedAt ?? DateTime(0)).compareTo(
                      a.savedAt ?? a.updatedAt ?? DateTime(0),
                    )),
        );
  }

  Stream<List<LotteryForm>> watchCancelledForms(String userId) {
    return _formsRef(userId).snapshots().map(
          (snapshot) => _mapForms(snapshot)
            ..retainWhere(
              (form) =>
                  form.status == LotteryFormStatus.cancelled &&
                  form.mode == LotteryFormMode.personal,
            )
            ..sort((a, b) =>
                (b.cancelledAt ?? b.updatedAt ?? DateTime(0)).compareTo(
                  a.cancelledAt ?? a.updatedAt ?? DateTime(0),
                )),
        );
  }

  Stream<LotteryForm> watchForm({
    required String userId,
    required String formId,
  }) {
    return _formsRef(userId).doc(formId).snapshots().map((snapshot) {
      final Map<String, dynamic>? data = snapshot.data();
      if (!snapshot.exists || data == null) {
        throw StateError('הטופס שנשלח לא נמצא.');
      }
      return LotteryForm.fromFirestore(snapshot.id, data);
    });
  }

  List<LotteryForm> _mapForms(QuerySnapshot<Map<String, dynamic>> snapshot) {
    return snapshot.docs
        .map((doc) => LotteryForm.fromFirestore(doc.id, doc.data()))
        .toList();
  }

  Future<int> countSavedForms(
    String userId, {
    String? excludingFormId,
  }) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _formsRef(userId)
        .where('status', isEqualTo: LotteryFormStatus.saved.value)
        .get();

    return snapshot.docs.where((doc) => doc.id != excludingFormId).length;
  }

  Future<bool> hasIdenticalSavedForm(
    LotteryForm form,
  ) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _formsRef(
      form.userId,
    ).where('status', isEqualTo: LotteryFormStatus.saved.value).get();

    final List<LotteryForm> savedForms = _mapForms(snapshot);
    return savedForms.any(
      (savedForm) => _tablesEqual(savedForm.tables, form.tables),
    );
  }

  Future<LotteryForm> upsertForm(LotteryForm form) async {
    final DocumentReference<Map<String, dynamic>> docRef = form.formId == null
        ? _formsRef(form.userId).doc()
        : _formsRef(form.userId).doc(form.formId);

    final DateTime now = DateTime.now();
    final LotteryForm persistable = form.copyWith(
      formId: docRef.id,
      createdAt: form.createdAt ?? now,
      updatedAt: now,
    );

    await docRef.set(
      <String, dynamic>{
        'formId': docRef.id,
        'userId': persistable.userId,
        'status': persistable.status.value,
        'tables': persistable.tables.map((table) => table.toMap()).toList(),
        'isComplete': persistable.isComplete,
        'createdAt': persistable.createdAt,
        'updatedAt': persistable.updatedAt,
        'submittedAt': persistable.submittedAt,
        'savedAt': persistable.savedAt,
        'cancelledAt': persistable.cancelledAt,
        'cancelledByUserId': persistable.cancelledByUserId,
        'cancelledByDisplayName': persistable.cancelledByDisplayName,
        'refundAmount': persistable.refundAmount,
        'source': persistable.source,
        'version': persistable.version,
        'lotteryId': persistable.lotteryId,
        'salesCloseAt': persistable.salesCloseAt,
        'resultStatus': persistable.resultStatus?.value,
        'resultPublishedAt': persistable.resultPublishedAt,
        'winAmount': persistable.winAmount,
        'checkedAt': persistable.checkedAt,
        'balanceApplied': persistable.balanceApplied,
        'mode': persistable.mode.value,
        'groupId': persistable.groupId,
        'isEditable': persistable.isEditable,
        'dispatchStatus': persistable.dispatchStatus,
        'printReadyUrl': persistable.printReadyUrl,
        'printReadyGeneratedAt': persistable.printReadyGeneratedAt,
        'printReadyStoragePath': persistable.printReadyStoragePath,
        'printedAt': persistable.printedAt,
        'submittedToStationAt': persistable.submittedToStationAt,
        'ticketFingerprintSource': persistable.ticketFingerprintSource,
        'ticketFingerprint': persistable.ticketFingerprint,
        'fingerprintVersion': persistable.fingerprintVersion,
      },
      SetOptions(merge: true),
    );

    return persistable;
  }

  Future<LotteryForm> submitForm(LotteryForm form) async {
    await _stabilizeAuthBeforeSubmit(form.userId);

    final User? currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'No authenticated Firebase user was found on the device.',
      );
    }

    if (currentUser.uid != form.userId) {
      throw FirebaseFunctionsException(
        code: 'permission-denied',
        message: 'Authenticated user does not match the current form owner.',
      );
    }

    final String token = await currentUser.getIdToken(true) ?? '';

    await Future<void>.delayed(const Duration(milliseconds: 250));

    final HttpsCallable callable =
        _functions.httpsCallable(_submitFunctionName);
    final HttpsCallableResult<dynamic> result = await callable.call(
      <String, dynamic>{
        'idToken': token,
        'tables': form.tables.map((table) => table.toMap()).toList(),
        'source': form.source,
        'version': form.version,
      },
    );

    final Map<String, dynamic> data =
        Map<String, dynamic>.from(result.data as Map<dynamic, dynamic>);
    final String formId = data['formId'] as String;
    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await _formsRef(form.userId).doc(formId).get();
    return LotteryForm.fromFirestore(formId, snapshot.data()!);
  }

  Future<void> chargeUserWallet({
    required String userId,
    required num amount,
    String? formId,
  }) async {
    await _stabilizeAuthBeforeSubmit(userId);

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
      'amount': amount,
      if (formId != null && formId.isNotEmpty) 'formId': formId,
    });
  }

  Future<String> submitPersonalSubmissionBundle({
    required String userId,
    required List<PersonalSubmissionDraftPayload> drafts,
    required num totalCost,
  }) async {
    if (drafts.isEmpty) {
      throw StateError('לא נמצאו טפסים לשליחה.');
    }

    final DateTime now = DateTime.now();
    final DocumentReference<Map<String, dynamic>> submissionRef =
        _submissionsRef(userId).doc();
    final WriteBatch batch = _firestore.batch();

    batch.set(
      submissionRef,
      <String, dynamic>{
        'submissionId': submissionRef.id,
        'userId': userId,
        'type': 'personal',
        'status': 'submitted',
        'formCount': drafts.length,
        'totalCost': totalCost,
        'createdAt': now,
        'updatedAt': now,
        'submittedAt': now,
      },
    );

    for (final PersonalSubmissionDraftPayload draft in drafts) {
      final DocumentReference<Map<String, dynamic>> formRef =
          submissionRef.collection('forms').doc();
      batch.set(
        formRef,
        <String, dynamic>{
          'formId': formRef.id,
          'submissionId': submissionRef.id,
          'userId': userId,
          'displayOrder': draft.displayOrder,
          'status': LotteryFormStatus.submitted.value,
          'mode': LotteryFormMode.personal.value,
          'isDoubleMode': draft.isDoubleMode,
          'tableCount': draft.tableCount,
          'cost': draft.cost,
          'tables': draft.form.tables.map((table) => table.toMap()).toList(),
          'isComplete': draft.form.isComplete,
          'createdAt': now,
          'updatedAt': now,
          'submittedAt': now,
          'savedAt': draft.form.savedAt,
          'source': draft.form.source,
          'version': draft.form.version,
          'lotteryId': draft.form.lotteryId,
          'salesCloseAt': draft.form.salesCloseAt,
          'balanceApplied': draft.form.balanceApplied,
        },
      );
    }

    await batch.commit();
    return submissionRef.id;
  }

  num calculateTicketCost(List<LotteryTable> tables) {
    final int populatedTableCount = tables.where((table) => !table.isEmpty).length;
    return _calculateRegularLottoBaseTicketCost(populatedTableCount);
  }

  Future<void> _stabilizeAuthBeforeSubmit(String expectedUserId) async {
    if (_auth.currentUser?.uid == expectedUserId) {
      return;
    }

    try {
      await _auth
          .authStateChanges()
          .firstWhere((user) => user?.uid == expectedUserId)
          .timeout(const Duration(seconds: 2));
    } on TimeoutException {
      return;
    } catch (error, stackTrace) {
      Zone.current.handleUncaughtError(error, stackTrace);
    }
  }

  Future<void> deleteSavedForm({
    required String userId,
    required String formId,
  }) {
    return _formsRef(userId).doc(formId).delete();
  }

  Future<void> cancelSavedForm({
    required String userId,
    required String formId,
  }) async {
    debugPrint(
      '[LotteryFormRepository] cancelSavedForm start userId=$userId formId=$formId',
    );
    final DateTime now = DateTime.now();
    final String cancelledByUserId = _auth.currentUser?.uid ?? userId;
    final String cancelledByDisplayName =
        _auth.currentUser?.displayName?.trim().isNotEmpty == true
            ? _auth.currentUser!.displayName!.trim()
            : cancelledByUserId;
    final DocumentReference<Map<String, dynamic>> formRef =
        _formsRef(userId).doc(formId);

    await _firestore.runTransaction((transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> snapshot =
          await transaction.get(formRef);
      final Map<String, dynamic>? data = snapshot.data();
      if (!snapshot.exists || data == null) {
        throw StateError('הטיוטה לא נמצאה.');
      }

      final LotteryForm form = LotteryForm.fromFirestore(snapshot.id, data);
      if (form.status != LotteryFormStatus.saved) {
        debugPrint(
          '[LotteryFormRepository] cancelSavedForm rejected formId=$formId status=${form.status.value}',
        );
        throw StateError('ניתן לבטל רק טיוטה שמורה.');
      }

      final num refundAmount = _calculateRefundAmount(data);
      debugPrint(
        '[LotteryFormRepository] cancelSavedForm applying refund formId=$formId refundAmount=$refundAmount',
      );
      if (refundAmount > 0) {
        final DocumentReference<Map<String, dynamic>> userRef =
            _firestore.collection('users').doc(userId);
        final DocumentSnapshot<Map<String, dynamic>> userSnapshot =
            await transaction.get(userRef);
        final num currentBalance =
            (userSnapshot.data()?['balance'] as num?) ?? 0;
        transaction.set(
          userRef,
          <String, dynamic>{
            'balance': currentBalance + refundAmount,
          },
          SetOptions(merge: true),
        );
      }

      transaction.set(
        formRef,
        <String, dynamic>{
          'status': LotteryFormStatus.cancelled.value,
          'updatedAt': now,
          'cancelledAt': now,
          'cancelledByUserId': cancelledByUserId,
          'cancelledByDisplayName': cancelledByDisplayName,
          'refundAmount': refundAmount,
          'isEditable': false,
        },
        SetOptions(merge: true),
      );
    });
    debugPrint(
      '[LotteryFormRepository] cancelSavedForm success userId=$userId formId=$formId',
    );
  }

  Future<LotteryGroup> createGroupFromForm({
    required LotteryForm form,
    required String groupName,
  }) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    debugPrint(
      '[CreateGroupFlow] repository.createGroupFromForm prepare refs start +0ms userId=${form.userId}',
    );
    final DateTime now = DateTime.now();
    final DocumentReference<Map<String, dynamic>> sourceFormRef =
        form.formId == null
            ? _formsRef(form.userId).doc()
            : _formsRef(form.userId).doc(form.formId);
    final DocumentReference<Map<String, dynamic>> groupRef = _groupsRef().doc();
    final DocumentReference<Map<String, dynamic>> membershipRef =
        groupRef.collection('memberships').doc(form.userId);

    final LotteryForm lockedForm = form.copyWith(
      formId: sourceFormRef.id,
      createdAt: form.createdAt ?? now,
      updatedAt: now,
      status: LotteryFormStatus.lockedForGroup,
      mode: LotteryFormMode.group,
      groupId: groupRef.id,
      isEditable: false,
    );

    final String inviteToken = groupRef.id;
    final int populatedTableCount =
        lockedForm.tables.where((table) => !table.isEmpty).length;
    final num baseTicketCost =
        _calculateRegularLottoBaseTicketCost(populatedTableCount);
    final String creatorDisplayName = _auth.currentUser?.uid == form.userId &&
            (_auth.currentUser?.displayName?.trim().isNotEmpty ?? false)
        ? _auth.currentUser!.displayName!.trim()
        : form.userId;
    final Map<String, dynamic> snapshot = <String, dynamic>{
      'tables': lockedForm.tables.map((table) => table.toMap()).toList(),
      'isComplete': lockedForm.isComplete,
    };
    debugPrint(
      '[CreateGroupFlow] repository.createGroupFromForm refs ready +${stopwatch.elapsedMilliseconds}ms sourceFormId=${sourceFormRef.id} groupId=${groupRef.id}',
    );

    final WriteBatch batch = _firestore.batch();
    batch.set(
      sourceFormRef,
      <String, dynamic>{
        'formId': sourceFormRef.id,
        'userId': lockedForm.userId,
        'status': lockedForm.status.value,
        'mode': lockedForm.mode.value,
        'groupId': lockedForm.groupId,
        'isEditable': lockedForm.isEditable,
        'tables': lockedForm.tables.map((table) => table.toMap()).toList(),
        'isComplete': lockedForm.isComplete,
        'createdAt': lockedForm.createdAt,
        'updatedAt': lockedForm.updatedAt,
        'submittedAt': lockedForm.submittedAt,
        'savedAt': lockedForm.savedAt,
        'source': lockedForm.source,
        'version': lockedForm.version,
        'lotteryId': lockedForm.lotteryId,
        'salesCloseAt': lockedForm.salesCloseAt,
        'resultStatus': lockedForm.resultStatus?.value,
        'resultPublishedAt': lockedForm.resultPublishedAt,
        'winAmount': lockedForm.winAmount,
        'checkedAt': lockedForm.checkedAt,
        'balanceApplied': lockedForm.balanceApplied,
      },
      SetOptions(merge: true),
    );

    batch.set(groupRef, <String, dynamic>{
      'groupId': groupRef.id,
      'groupName': groupName,
      'creatorUserId': form.userId,
      'sourceFormId': sourceFormRef.id,
      'status': LotteryGroupStatus.collectingResponses.value,
      'inviteToken': inviteToken,
      'formSnapshot': snapshot,
      'baseTicketCost': baseTicketCost,
      'currentPerParticipantCost': 0,
      'finalizedParticipantCount': 0,
      'dispatchStatus': null,
      'createdAt': now,
      'updatedAt': now,
    });

    batch.set(membershipRef, <String, dynamic>{
      'userId': form.userId,
      'displayName': creatorDisplayName,
      'groupId': groupRef.id,
      'responseStatus': 'interested',
      'minimumParticipantsRequired': 1,
      'lockedIn': false,
      'paymentStatus': 'not_applicable',
      'joinedAt': now,
      'respondedAt': now,
    });

    debugPrint(
      '[CreateGroupFlow] repository.createGroupFromForm batch.commit start +${stopwatch.elapsedMilliseconds}ms',
    );
    await batch.commit();
    debugPrint(
      '[CreateGroupFlow] repository.createGroupFromForm batch.commit end +${stopwatch.elapsedMilliseconds}ms',
    );

    return LotteryGroup.fromFirestore(groupRef.id, <String, dynamic>{
      'groupId': groupRef.id,
      'groupName': groupName,
      'creatorUserId': form.userId,
      'sourceFormId': sourceFormRef.id,
      'status': LotteryGroupStatus.collectingResponses.value,
      'inviteToken': inviteToken,
      'formSnapshot': snapshot,
      'baseTicketCost': baseTicketCost,
      'currentPerParticipantCost': 0,
      'finalizedParticipantCount': 0,
      'dispatchStatus': null,
      'createdAt': now,
      'updatedAt': now,
    });
  }

  bool _tablesEqual(List<dynamic> left, List<dynamic> right) {
    if (left.length != right.length) {
      return false;
    }

    for (int index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }

    return true;
  }

  num _calculateRegularLottoBaseTicketCost(int populatedTableCount) {
    if (populatedTableCount <= 0) {
      return 0;
    }

    final int tablePairs = (populatedTableCount / 2).ceil();
    return tablePairs * _regularLottoPairPriceNis;
  }

  num _calculateRefundAmount(Map<String, dynamic> data) {
    final List<dynamic> candidates = <dynamic>[
      data['paidAmount'],
      data['walletChargeAmount'],
      data['refundAmount'],
    ];
    for (final dynamic candidate in candidates) {
      if (candidate is num && candidate > 0) {
        return candidate;
      }
    }
    return 0;
  }
}

String? _extractSubmissionReceiptUrl(Map<String, dynamic> data) {
  const List<String> candidateKeys = <String>[
    'stationReceiptUrl',
    'receiptUrl',
    'uploadedReceiptUrl',
  ];
  for (final String key in candidateKeys) {
    final dynamic value = data[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return null;
}
