import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

import '../models/lottery_form.dart';

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

  CollectionReference<Map<String, dynamic>> _formsRef(String userId) {
    return _firestore.collection('users').doc(userId).collection('forms');
  }

  Stream<List<LotteryForm>> watchSubmittedForms(String userId) {
    return _formsRef(userId).snapshots().map(
          (snapshot) => _mapForms(snapshot)
            ..retainWhere(
              (form) => form.status == LotteryFormStatus.submitted,
            )
            ..sort((a, b) => (b.submittedAt ?? DateTime(0)).compareTo(
                  a.submittedAt ?? DateTime(0),
                )),
        );
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
        'source': persistable.source,
        'version': persistable.version,
        'lotteryId': persistable.lotteryId,
        'salesCloseAt': persistable.salesCloseAt,
        'resultStatus': persistable.resultStatus?.value,
        'resultPublishedAt': persistable.resultPublishedAt,
        'winAmount': persistable.winAmount,
        'checkedAt': persistable.checkedAt,
        'balanceApplied': persistable.balanceApplied,
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
}
