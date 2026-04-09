import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/app_user.dart';
import '../models/receipt_parsed_table.dart';
import '../models/receipt_intake_record.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class DispatchOverviewItem {
  const DispatchOverviewItem({
    required this.formOwnerUserId,
    required this.formId,
    required this.submissionType,
    required this.groupId,
    required this.groupName,
    required this.creatorUserId,
    required this.creatorName,
    required this.lotteryId,
    required this.submittedAt,
    required this.dispatchStatus,
    required this.ticketFingerprint,
    required this.ticketFingerprintSource,
    required this.effectiveParticipantCount,
    required this.tableCount,
    required this.tables,
    required this.stationReceiptUrl,
    required this.stationReceiptStoragePath,
    required this.stationReceiptIntakeId,
    required this.stationReceiptMatchStatus,
  });

  final String formOwnerUserId;
  final String formId;
  final String submissionType;
  final String? groupId;
  final String? groupName;
  final String creatorUserId;
  final String? creatorName;
  final int? lotteryId;
  final DateTime? submittedAt;
  final String dispatchStatus;
  final String? ticketFingerprint;
  final String? ticketFingerprintSource;
  final int? effectiveParticipantCount;
  final int tableCount;
  final List<ReceiptParsedTable> tables;
  final String? stationReceiptUrl;
  final String? stationReceiptStoragePath;
  final String? stationReceiptIntakeId;
  final String? stationReceiptMatchStatus;
}

class OperatorConsoleRepository {
  OperatorConsoleRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _auth = auth ?? FirebaseAuth.instance;

  static const String intakeStatusUploaded = 'uploaded';
  static const String intakeStatusProcessing = 'processing';
  static const String intakeStatusMatched = 'matched';
  static const String intakeStatusNeedsManualReview = 'needs_manual_review';
  static const String intakeStatusUnmatched = 'unmatched';
  static const String receiptParsingStatusPending = 'pending';
  static const String receiptParsingStatusParsed = 'parsed';
  static const String receiptParsingStatusPartial = 'partial';
  static const String receiptParsingStatusFailed = 'failed';
  static const int suggestionLookbackDays = 14;
  static const int suggestionThresholdScore = 10;
  static const int maxSuggestedMatches = 5;

  static const String dispatchStatusQueuedForPrint = 'queued_for_print';
  static const String dispatchStatusPrinted = 'printed';
  static const String dispatchStatusSubmittedToStation = 'submitted_to_station';
  static const String _extractorApiUrl =
    String.fromEnvironment(
        'LOTTO_EXTRACTOR_API_URL',
        defaultValue: 'http://127.0.0.1:3000/extract-lotto-ticket',
      );
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final FirebaseAuth _auth;
  int? _asInt(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

  Stream<List<DispatchOverviewItem>> watchDispatchOverview() {
    return _watchAllSubmittedForms().map(
      (items) => items
          .where(
            (item) =>
                item.dispatchStatus == dispatchStatusQueuedForPrint ||
                item.dispatchStatus == dispatchStatusPrinted,
          )
          .toList(),
    );
  }

  Future<void> _autoMatchReceiptByFingerprint({
  required String receiptId,
  required String? receiptFingerprint,
}) async {
  final DocumentReference<Map<String, dynamic>> receiptRef =
      _firestore.collection('receipt_intake').doc(receiptId);

  if (receiptFingerprint == null || receiptFingerprint.isEmpty) {
    await receiptRef.set(
      <String, dynamic>{
        'intakeStatus': intakeStatusUnmatched,
        'matchMessage': 'No fingerprint available for automatic matching.',
      },
      SetOptions(merge: true),
    );
    return;
  }

  final QuerySnapshot<Map<String, dynamic>> snapshot = await _firestore
      .collectionGroup('forms')
      .where('status', isEqualTo: 'submitted')
      .where('ticketFingerprint', isEqualTo: receiptFingerprint)
      .limit(2)
      .get();

  if (snapshot.docs.isEmpty) {
    await receiptRef.set(
      <String, dynamic>{
        'intakeStatus': intakeStatusUnmatched,
        'matchMessage': 'No submitted form matched this fingerprint.',
      },
      SetOptions(merge: true),
    );
    return;
  }

  if (snapshot.docs.length > 1) {
    await receiptRef.set(
      <String, dynamic>{
        'intakeStatus': intakeStatusNeedsManualReview,
        'matchMessage': 'Multiple submitted forms matched this fingerprint.',
      },
      SetOptions(merge: true),
    );
    return;
  }

  final QueryDocumentSnapshot<Map<String, dynamic>> matchedDoc =
      snapshot.docs.first;
  final Map<String, dynamic> matchedData = matchedDoc.data();

  final String matchedFormId =
      matchedData['formId'] as String? ?? matchedDoc.id;
  final String matchedOwnerUserId =
      matchedDoc.reference.parent.parent?.id ?? '';
  final String? matchedGroupId = matchedData['groupId'] as String?;
  final int? matchedLotteryId = _asInt(matchedData['lotteryId']);

  await receiptRef.set(
    <String, dynamic>{
      'matchedFormId': matchedFormId,
      'matchedFormOwnerUserId': matchedOwnerUserId,
      'matchedGroupId': matchedGroupId,
      'matchedLotteryId': matchedLotteryId,
      'matchedAt': FieldValue.serverTimestamp(),
      'matchedBy': _auth.currentUser?.uid,
      'intakeStatus': intakeStatusMatched,
      'matchMessage':
          'Matched automatically by fingerprint to submitted form $matchedFormId.',
    },
    SetOptions(merge: true),
  );

  await matchedDoc.reference.set(
    <String, dynamic>{
      'stationReceiptMatchStatus': intakeStatusMatched,
      'stationReceiptMatchedAt': FieldValue.serverTimestamp(),
      'stationReceiptMatchedBy': _auth.currentUser?.uid,
      'stationReceiptIntakeId': receiptId,
    },
    SetOptions(merge: true),
  );
}
  Future<Map<String, dynamic>> _extractReceiptWithApi({
    required String fileName,
    required String contentType,
    required Uint8List bytes,
  }) async {
    final http.MultipartRequest request = http.MultipartRequest(
      'POST',
      Uri.parse(_extractorApiUrl),
    );

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
        contentType: contentType.isNotEmpty
            ? MediaType.parse(contentType)
            : null,
      ),
    );

    final http.StreamedResponse response = await request.send();
    final String body = await response.stream.bytesToString();

    if (response.statusCode != 200) {
      throw StateError(
        'Extractor API failed (${response.statusCode}): $body',
      );
    }

    final Map<String, dynamic> json =
        jsonDecode(body) as Map<String, dynamic>;

    if (json['ok'] != true || json['data'] is! Map<String, dynamic>) {
      throw StateError('Extractor API returned invalid payload: $body');
    }

    return json['data'] as Map<String, dynamic>;
  }

  Stream<List<DispatchOverviewItem>> watchHandledDispatchOverview() {
    return _watchAllSubmittedForms().map(
      (items) => items
          .where(
            (item) => item.dispatchStatus == dispatchStatusSubmittedToStation,
          )
          .toList(),
    );
  }

  Stream<List<DispatchOverviewItem>> watchSubmittedFormCandidates() {
    return _watchAllSubmittedForms();
  }

  Stream<List<DispatchOverviewItem>> _watchAllSubmittedForms() {
    _logOperatorContext();
    return _firestore
        .collectionGroup('forms')
        .where('status', isEqualTo: 'submitted')
        .snapshots()
        .map((snapshot) {
      debugPrint(
        '[OperatorConsole] submitted forms query returned ${snapshot.docs.length} docs',
      );
      final List<DispatchOverviewItem> items =
          snapshot.docs.map(_mapSubmittedFormDoc).toList();

      items.sort((a, b) {
        final DateTime aDate = a.submittedAt ?? DateTime(0);
        final DateTime bDate = b.submittedAt ?? DateTime(0);
        return bDate.compareTo(aDate);
      });
      return items;
    }).handleError((Object error, StackTrace stackTrace) {
      debugPrint('[OperatorConsole] submitted forms query failed: $error');
      debugPrint('$stackTrace');
    });
  }

  Future<void> _logOperatorContext() async {
    final User? user = _auth.currentUser;
    debugPrint(
      '[OperatorConsole] app projectId=${Firebase.app().options.projectId} '
      'uid=${user?.uid} email=${user?.email}',
    );

    if (user == null) {
      debugPrint('[OperatorConsole] no authenticated user in operator console');
      return;
    }

    try {
      final DocumentSnapshot<Map<String, dynamic>> userSnapshot =
          await _firestore.collection('users').doc(user.uid).get();
      debugPrint(
        '[OperatorConsole] operator user doc exists=${userSnapshot.exists} '
        'path=${userSnapshot.reference.path} data=${userSnapshot.data()}',
      );
    } catch (error, stackTrace) {
      debugPrint('[OperatorConsole] failed to read operator user doc: $error');
      debugPrint('$stackTrace');
    }
  }

  Stream<List<ReceiptIntakeRecord>> watchReceiptIntakeQueue() {
    return _firestore.collection('receipt_intake').snapshots().map((snapshot) {
      final List<ReceiptIntakeRecord> items = snapshot.docs
          .map((doc) => ReceiptIntakeRecord.fromFirestore(doc.id, doc.data()))
          .toList();
      items.sort((a, b) {
        final DateTime aDate = a.uploadedAt ?? DateTime(0);
        final DateTime bDate = b.uploadedAt ?? DateTime(0);
        return bDate.compareTo(aDate);
      });
      for (final ReceiptIntakeRecord item in items) {
        final bool shouldGenerate = item.matchedFormId == null &&
            (item.intakeStatus == intakeStatusUploaded ||
                item.intakeStatus == intakeStatusUnmatched) &&
            item.suggestionsGeneratedAt == null;
        if (shouldGenerate) {
          unawaited(refreshSuggestionsForReceipt(receipt: item));
        }
      }
      return items;
    });
  }

  Future<ReceiptIntakeRecord> uploadReceipt({
    required AppUser operator,
    required PlatformFile file,
  }) async {
    final Uint8List? bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Receipt upload requires file bytes.');
    }

    final DateTime now = DateTime.now();
    final String receiptId = const Uuid().v4();
    final String extension = _normalizedExtension(file.extension);
    final String fileName =
        file.name.isEmpty ? 'receipt.$extension' : file.name;
    final String contentType = _contentTypeForExtension(extension);
    final String year = now.year.toString();
    final String month = now.month.toString().padLeft(2, '0');
    final String storagePath =
        'receipt_intake/$year/$month/$receiptId/original.$extension';

    final Reference ref = _storage.ref(storagePath);
    await ref.putData(
      bytes,
      SettableMetadata(
        contentType: contentType,
        customMetadata: <String, String>{
          'receiptId': receiptId,
          'uploadedBy': operator.uid,
        },
      ),
    );
    final String downloadUrl = await ref.getDownloadURL();

    final Map<String, dynamic> payload = <String, dynamic>{
      'receiptId': receiptId,
      'uploadedAt': now,
      'uploadedBy': operator.uid,
      'uploadedByDisplayName': operator.displayName,
      'storagePath': storagePath,
      'downloadUrl': downloadUrl,
      'contentType': contentType,
      'fileName': fileName,
      'intakeStatus': intakeStatusUploaded,
      'matchedFormId': null,
      'matchedFormOwnerUserId': null,
      'matchedGroupId': null,
      'matchedLotteryId': null,
      'matchedAt': null,
      'matchedBy': null,
      'matchMessage': 'Uploaded successfully. Matching has not started yet.',
      'notes': null,
      'suggestedFormIds': const <String>[],
      'suggestionScores': const <String, num>{},
      'suggestionsGeneratedAt': null,
      'receiptCreatorUserIdHint': null,
      'receiptCreatorNameHint': null,
      'receiptTicketTypeHint': null,
      'receiptTableCountHint': null,
      'receiptFingerprintHint': null,
      'receiptFingerprintPrefixHint': null,
      'receiptFingerprintSourcePrefixHint': null,
      'receiptLotteryIdHint': null,
      'receiptParsedTables': const <Map<String, dynamic>>[],
      'receiptFingerprintSource': null,
      'receiptFingerprint': null,
      'receiptParsedAt': null,
      'receiptParsingStatus': receiptParsingStatusPending,
      'receiptParsingMessage':
          'Receipt uploaded. Structured parsing has not completed yet.',
      'lastMatchedFormId': null,
      'lastMatchedGroupId': null,
      'lastMatchedLotteryId': null,
      'lastMatchedCreatorUserId': null,
      'lastMatchedTableCount': null,
      'lastMatchedFingerprint': null,
      'lastMatchedAt': null,
    };

    await _firestore.collection('receipt_intake').doc(receiptId).set(payload);
    debugPrint('[OperatorConsole] receipt parsing started for $receiptId');
    unawaited(
      _parseAndPersistReceiptHints(
        receiptId: receiptId,
        fileName: fileName,
        contentType: contentType,
        bytes: bytes,
      ),
    );
    return ReceiptIntakeRecord.fromFirestore(receiptId, payload);
  }

  Future<void> updateDispatchStatus({
    required DispatchOverviewItem item,
    required String dispatchStatus,
  }) async {
    final String operatorUserId = _auth.currentUser?.uid ?? '';
    if (operatorUserId.isEmpty) {
      throw StateError('Authentication is required.');
    }

    final DateTime now = DateTime.now();
    final DocumentReference<Map<String, dynamic>> formRef = _firestore
        .collection('users')
        .doc(item.formOwnerUserId)
        .collection('forms')
        .doc(item.formId);

    await _firestore.runTransaction((transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> formSnapshot =
          await transaction.get(formRef);
      final Map<String, dynamic>? formData = formSnapshot.data();
      if (!formSnapshot.exists || formData == null) {
        throw StateError('Submitted form not found.');
      }

      final Map<String, dynamic> dispatchUpdate = <String, dynamic>{
        'dispatchStatus': dispatchStatus,
        'updatedAt': now,
        'dispatchUpdatedBy': operatorUserId,
      };
      if (dispatchStatus == dispatchStatusPrinted) {
        dispatchUpdate['printedAt'] = now;
      }
      if (dispatchStatus == dispatchStatusSubmittedToStation) {
        dispatchUpdate['submittedToStationAt'] = now;
        dispatchUpdate['printedAt'] = formData['printedAt'] ?? now;
      }

      transaction.set(formRef, dispatchUpdate, SetOptions(merge: true));

      final String? groupId = item.groupId;
      if (groupId == null || groupId.isEmpty) {
        return;
      }

      final DocumentReference<Map<String, dynamic>> groupRef =
          _firestore.collection('lottery_groups').doc(groupId);
      final DocumentSnapshot<Map<String, dynamic>> groupSnapshot =
          await transaction.get(groupRef);
      if (groupSnapshot.exists) {
        transaction.set(groupRef, dispatchUpdate, SetOptions(merge: true));
      }

      final List<String> participantUserIds =
          (formData['submittedParticipantUserIds'] as List<dynamic>? ??
                  <dynamic>[])
              .whereType<String>()
              .toList();

      for (final String userId in participantUserIds) {
        final DocumentReference<Map<String, dynamic>> submittedGroupRef =
            _firestore
                .collection('users')
                .doc(userId)
                .collection('submitted_groups')
                .doc(groupId);
        transaction.set(
          submittedGroupRef,
          <String, dynamic>{
            ...dispatchUpdate,
            'groupStatus': 'submitted',
          },
          SetOptions(merge: true),
        );
      }
    });
  }

  Future<void> matchReceiptToSubmittedForm({
    required ReceiptIntakeRecord receipt,
    required DispatchOverviewItem candidate,
  }) async {
    final String operatorUserId = _auth.currentUser?.uid ?? '';
    if (operatorUserId.isEmpty) {
      throw StateError('Authentication is required.');
    }

    final DateTime now = DateTime.now();
    final DocumentReference<Map<String, dynamic>> receiptRef =
        _firestore.collection('receipt_intake').doc(receipt.receiptId);
    final DocumentReference<Map<String, dynamic>> formRef = _firestore
        .collection('users')
        .doc(candidate.formOwnerUserId)
        .collection('forms')
        .doc(candidate.formId);

    await _firestore.runTransaction((transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> receiptSnapshot =
          await transaction.get(receiptRef);
      final DocumentSnapshot<Map<String, dynamic>> formSnapshot =
          await transaction.get(formRef);

      final Map<String, dynamic>? receiptData = receiptSnapshot.data();
      final Map<String, dynamic>? formData = formSnapshot.data();
      if (!receiptSnapshot.exists || receiptData == null) {
        throw StateError('Receipt intake item not found.');
      }
      if (!formSnapshot.exists || formData == null) {
        throw StateError('Submitted form not found.');
      }

      final String? existingMatchedFormId =
          receiptData['matchedFormId'] as String?;
      if (existingMatchedFormId != null &&
          existingMatchedFormId.isNotEmpty &&
          existingMatchedFormId != candidate.formId) {
        throw StateError(
          'This receipt is already matched. Unmatch it before selecting a different submitted form.',
        );
      }

      final String? existingReceiptIntakeId =
          formData['stationReceiptIntakeId'] as String?;
      if (existingReceiptIntakeId != null &&
          existingReceiptIntakeId.isNotEmpty &&
          existingReceiptIntakeId != receipt.receiptId) {
        throw StateError(
          'This submitted form already has a different receipt attached. Unmatch it first.',
        );
      }

      transaction.set(
        receiptRef,
        <String, dynamic>{
          'matchedFormId': candidate.formId,
          'matchedFormOwnerUserId': candidate.formOwnerUserId,
          'matchedGroupId': candidate.groupId,
          'matchedLotteryId': candidate.lotteryId,
          'matchedAt': now,
          'matchedBy': operatorUserId,
          'intakeStatus': intakeStatusMatched,
          'matchMessage':
              'Matched manually by operator to submitted form ${candidate.formId}.',
          'receiptCreatorUserIdHint': candidate.creatorUserId,
          'receiptCreatorNameHint': candidate.creatorName,
          'receiptTableCountHint': candidate.tableCount,
          'receiptFingerprintHint': candidate.ticketFingerprint,
          'receiptFingerprintPrefixHint':
              _prefixOrNull(candidate.ticketFingerprint, 8),
          'receiptFingerprintSourcePrefixHint':
              _prefixOrNull(candidate.ticketFingerprintSource, 24),
          'receiptLotteryIdHint': candidate.lotteryId,
          'lastMatchedFormId': candidate.formId,
          'lastMatchedGroupId': candidate.groupId,
          'lastMatchedLotteryId': candidate.lotteryId,
          'lastMatchedCreatorUserId': candidate.creatorUserId,
          'lastMatchedTableCount': candidate.tableCount,
          'lastMatchedFingerprint': candidate.ticketFingerprint,
          'lastMatchedAt': now,
        },
        SetOptions(merge: true),
      );

      transaction.set(
        formRef,
        <String, dynamic>{
          'stationReceiptUrl': receipt.downloadUrl,
          'stationReceiptStoragePath': receipt.storagePath,
          'stationReceiptUploadedAt': receipt.uploadedAt,
          'stationReceiptMatchStatus': intakeStatusMatched,
          'stationReceiptMatchedAt': now,
          'stationReceiptMatchedBy': operatorUserId,
          'stationReceiptIntakeId': receipt.receiptId,
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> unmatchReceipt({
    required ReceiptIntakeRecord receipt,
  }) async {
    final String operatorUserId = _auth.currentUser?.uid ?? '';
    if (operatorUserId.isEmpty) {
      throw StateError('Authentication is required.');
    }

    final DateTime now = DateTime.now();
    final DocumentReference<Map<String, dynamic>> receiptRef =
        _firestore.collection('receipt_intake').doc(receipt.receiptId);

    await _firestore.runTransaction((transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> receiptSnapshot =
          await transaction.get(receiptRef);
      final Map<String, dynamic>? receiptData = receiptSnapshot.data();
      if (!receiptSnapshot.exists || receiptData == null) {
        throw StateError('Receipt intake item not found.');
      }

      final String? matchedFormId = receiptData['matchedFormId'] as String?;
      final String? matchedFormOwnerUserId =
          receiptData['matchedFormOwnerUserId'] as String?;

      if (matchedFormId != null &&
          matchedFormId.isNotEmpty &&
          matchedFormOwnerUserId != null &&
          matchedFormOwnerUserId.isNotEmpty) {
        final DocumentReference<Map<String, dynamic>> formRef = _firestore
            .collection('users')
            .doc(matchedFormOwnerUserId)
            .collection('forms')
            .doc(matchedFormId);
        final DocumentSnapshot<Map<String, dynamic>> formSnapshot =
            await transaction.get(formRef);
        final Map<String, dynamic>? formData = formSnapshot.data();
        if (formSnapshot.exists &&
            formData != null &&
            formData['stationReceiptIntakeId'] == receipt.receiptId) {
          transaction.set(
            formRef,
            <String, dynamic>{
              'stationReceiptUrl': null,
              'stationReceiptStoragePath': null,
              'stationReceiptUploadedAt': null,
              'stationReceiptMatchStatus': intakeStatusUnmatched,
              'stationReceiptMatchedAt': null,
              'stationReceiptMatchedBy': null,
              'stationReceiptIntakeId': null,
            },
            SetOptions(merge: true),
          );
        }
      }

      transaction.set(
        receiptRef,
        <String, dynamic>{
          'matchedFormId': null,
          'matchedFormOwnerUserId': null,
          'matchedGroupId': null,
          'matchedLotteryId': null,
          'matchedAt': null,
          'matchedBy': null,
          'intakeStatus': intakeStatusUnmatched,
          'matchMessage': 'Receipt was manually unmatched by operator.',
          'suggestedFormIds': const <String>[],
          'suggestionScores': const <String, num>{},
          'suggestionsGeneratedAt': null,
          'updatedAt': now,
          'updatedBy': operatorUserId,
        },
        SetOptions(merge: true),
      );
    });

    final DocumentSnapshot<Map<String, dynamic>> refreshedReceiptSnapshot =
        await _firestore
            .collection('receipt_intake')
            .doc(receipt.receiptId)
            .get();
    final Map<String, dynamic>? refreshedReceiptData =
        refreshedReceiptSnapshot.data();
    if (refreshedReceiptSnapshot.exists && refreshedReceiptData != null) {
      await refreshSuggestionsForReceipt(
        receipt: ReceiptIntakeRecord.fromFirestore(
          receipt.receiptId,
          refreshedReceiptData,
        ),
        force: true,
      );
    }
  }

  Future<void> refreshSuggestionsForReceipt({
    required ReceiptIntakeRecord receipt,
    bool force = false,
  }) async {
    if (receipt.matchedFormId != null && receipt.matchedFormId!.isNotEmpty) {
      return;
    }
    if (receipt.intakeStatus != intakeStatusUploaded &&
        receipt.intakeStatus != intakeStatusUnmatched) {
      return;
    }
    if (!force && receipt.suggestionsGeneratedAt != null) {
      return;
    }

    final DateTime? uploadedAt = receipt.uploadedAt;
    if (uploadedAt == null) {
      return;
    }

    final QuerySnapshot<Map<String, dynamic>> snapshot = await _firestore
        .collectionGroup('forms')
        .where('status', isEqualTo: 'submitted')
        .get();

    final DateTime oldestAllowed =
        uploadedAt.subtract(const Duration(days: suggestionLookbackDays));
    final List<_ScoredCandidate> scoredCandidates = snapshot.docs
        .map(_mapSubmittedFormDoc)
        .where(
          (candidate) => _isEligibleSuggestionCandidate(
            candidate,
            oldestAllowed,
            receipt: receipt,
          ),
        )
        .map(
          (candidate) => _ScoredCandidate(
            candidate: candidate,
            exactFingerprintMatch: _sameNonEmpty(
              receipt.receiptFingerprint,
              candidate.ticketFingerprint,
            ),
            score: _scoreCandidateForReceipt(
              receipt: receipt,
              candidate: candidate,
              uploadedAt: uploadedAt,
            ),
            reasons: buildSuggestionReasons(
              receipt: receipt,
              candidate: candidate,
              uploadedAt: uploadedAt,
            ),
          ),
        )
        .toList()
      ..sort((a, b) {
        if (a.exactFingerprintMatch != b.exactFingerprintMatch) {
          return a.exactFingerprintMatch ? -1 : 1;
        }
        return b.score.compareTo(a.score);
      });

    final List<_ScoredCandidate> strongCandidates = scoredCandidates
        .where((candidate) => candidate.score >= suggestionThresholdScore)
        .take(maxSuggestedMatches)
        .toList();
    final List<_ScoredCandidate> topCandidates = strongCandidates.isNotEmpty
        ? strongCandidates
        : scoredCandidates.take(3).toList();

    await _firestore.collection('receipt_intake').doc(receipt.receiptId).set(
      <String, dynamic>{
        'suggestedFormIds': topCandidates
            .map((candidate) => candidate.candidate.formId)
            .toList(),
        'suggestionScores': <String, double>{
          for (final _ScoredCandidate candidate in topCandidates)
            candidate.candidate.formId: candidate.score.toDouble(),
        },
        'suggestionsGeneratedAt': DateTime.now(),
      },
      SetOptions(merge: true),
    );
  }

  DispatchOverviewItem _mapSubmittedFormDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data();
    final String ownerUserId = doc.reference.parent.parent?.id ?? '';
    final String creatorUserId =
        data['creatorUserId'] as String? ?? data['userId'] as String? ?? '';
    debugPrint(
      '[OperatorConsole] doc formId=${doc.id} '
      'ownerUserId=$ownerUserId '
      'path=${doc.reference.path} '
      'dispatchStatus=${data['dispatchStatus']} '
      'submissionType=${data['submissionType']} '
      'groupId=${data['groupId']}',
    );
    return DispatchOverviewItem(
      formOwnerUserId: ownerUserId,
      formId: doc.id,
      submissionType: data['submissionType'] as String? ?? 'personal',
      groupId: data['groupId'] as String?,
      groupName: data['groupName'] as String?,
      creatorUserId: creatorUserId,
      creatorName: data['creatorDisplayName'] as String?,
      lotteryId: _asInt(data['lotteryId']),
      submittedAt: _asDateTime(data['submittedAt']),
      dispatchStatus:
          data['dispatchStatus'] as String? ?? dispatchStatusQueuedForPrint,
      ticketFingerprint: data['ticketFingerprint'] as String?,
      ticketFingerprintSource: data['ticketFingerprintSource'] as String?,
      effectiveParticipantCount:
          (data['effectiveParticipantCount'] as num?)?.toInt(),
      tableCount:
          (data['tables'] as List<dynamic>? ?? const <dynamic>[]).length,
      tables: _submittedTablesFromData(data['tables']),
      stationReceiptUrl: data['stationReceiptUrl'] as String?,
      stationReceiptStoragePath: data['stationReceiptStoragePath'] as String?,
      stationReceiptIntakeId: data['stationReceiptIntakeId'] as String?,
      stationReceiptMatchStatus: data['stationReceiptMatchStatus'] as String?,
    );
  }

  bool _isEligibleSuggestionCandidate(
    DispatchOverviewItem candidate,
    DateTime oldestAllowed, {
    required ReceiptIntakeRecord receipt,
  }) {
    final DateTime? submittedAt = candidate.submittedAt;
    if (submittedAt == null || submittedAt.isBefore(oldestAllowed)) {
      return false;
    }
    if (candidate.stationReceiptMatchStatus == intakeStatusMatched &&
        candidate.formId != receipt.lastMatchedFormId) {
      return false;
    }
    return true;
  }

  int _scoreCandidateForReceipt({
    required ReceiptIntakeRecord receipt,
    required DispatchOverviewItem candidate,
    required DateTime uploadedAt,
  }) {
    int score = 0;
    final bool exactFingerprintMatch =
        _sameNonEmpty(receipt.receiptFingerprint, candidate.ticketFingerprint);
    final bool strongTableAlignment = !exactFingerprintMatch &&
        _receiptTablesStronglyAlign(
          receipt.receiptParsedTables,
          candidate.tables,
        );

    final DateTime? submittedAt = candidate.submittedAt;
    if (submittedAt != null) {
      final Duration delta = uploadedAt.difference(submittedAt).abs();
      if (delta <= const Duration(hours: 1)) {
        score += 30;
      } else if (delta <= const Duration(hours: 6)) {
        score += 20;
      } else if (delta <= const Duration(hours: 24)) {
        score += 10;
      }
    }

    final int? receiptLotteryId = receipt.receiptLotteryIdHint;
    if (receiptLotteryId != null &&
        candidate.lotteryId != null &&
        candidate.lotteryId == receiptLotteryId) {
      score += 50;
    }

    if (_sameNonEmpty(
      receipt.receiptCreatorUserIdHint,
      candidate.creatorUserId,
    )) {
      score += 30;
    }

    if (_strongNameMatch(
      receipt.receiptCreatorNameHint,
      candidate.creatorName,
    )) {
      score += 20;
    }

    if (receipt.receiptTableCountHint != null &&
        receipt.receiptTableCountHint == candidate.tableCount) {
      score += 30;
    }

    if (exactFingerprintMatch) {
      score += 100;
    } else if (strongTableAlignment) {
      score += 60;
    }

    return score;
  }

  List<String> buildSuggestionReasons({
    required ReceiptIntakeRecord receipt,
    required DispatchOverviewItem candidate,
    required DateTime uploadedAt,
  }) {
    final List<String> reasons = <String>[];
    final bool exactFingerprintMatch =
        _sameNonEmpty(receipt.receiptFingerprint, candidate.ticketFingerprint);
    final bool strongTableAlignment = !exactFingerprintMatch &&
        _receiptTablesStronglyAlign(
          receipt.receiptParsedTables,
          candidate.tables,
        );

    final DateTime? submittedAt = candidate.submittedAt;
    if (submittedAt != null) {
      final Duration delta = uploadedAt.difference(submittedAt).abs();
      if (delta <= const Duration(hours: 1)) {
        reasons.add('submitted within 1 hour');
      } else if (delta <= const Duration(hours: 6)) {
        reasons.add('submitted within 6 hours');
      } else if (delta <= const Duration(hours: 24)) {
        reasons.add('submitted within 24 hours');
      }
    }
    if (receipt.receiptLotteryIdHint != null &&
        receipt.receiptLotteryIdHint == candidate.lotteryId) {
      reasons.add('same lottery');
    }
    if (_sameNonEmpty(
        receipt.receiptCreatorUserIdHint, candidate.creatorUserId)) {
      reasons.add('same creator');
    }
    if (_strongNameMatch(
        receipt.receiptCreatorNameHint, candidate.creatorName)) {
      reasons.add('same creator name');
    }
    if (receipt.receiptTableCountHint != null &&
        receipt.receiptTableCountHint == candidate.tableCount) {
      reasons.add('same table count');
    }
    if (exactFingerprintMatch) {
      reasons.add('same parsed receipt fingerprint');
    } else if (strongTableAlignment) {
      reasons.add('parsed ticket rows align strongly');
    }
    return reasons;
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

  String _normalizedExtension(String? rawExtension) {
    final String cleaned =
        (rawExtension ?? '').trim().toLowerCase().replaceAll('.', '');
    if (cleaned.isEmpty) {
      return 'bin';
    }
    return cleaned;
  }

  String _contentTypeForExtension(String extension) {
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }

  String? _prefixOrNull(String? value, int length) {
    if (value == null || value.isEmpty) {
      return null;
    }
    final int end = value.length < length ? value.length : length;
    return value.substring(0, end);
  }

  bool _sameNonEmpty(String? left, String? right) {
    return left != null &&
        left.isNotEmpty &&
        right != null &&
        right.isNotEmpty &&
        left == right;
  }

  bool _strongNameMatch(String? left, String? right) {
    final String normalizedLeft = _normalizeForMatching(left);
    final String normalizedRight = _normalizeForMatching(right);
    if (normalizedLeft.isEmpty || normalizedRight.isEmpty) {
      return false;
    }
    return normalizedLeft == normalizedRight ||
        normalizedLeft.contains(normalizedRight) ||
        normalizedRight.contains(normalizedLeft);
  }

  String _normalizeForMatching(String? value) {
    if (value == null) {
      return '';
    }
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<void> _parseAndPersistReceiptHints({
    required String receiptId,
    required String fileName,
    required String contentType,
    required Uint8List bytes,
  }) async {
    final DocumentReference<Map<String, dynamic>> receiptRef =
        _firestore.collection('receipt_intake').doc(receiptId);

    await receiptRef.set(
      <String, dynamic>{
        'receiptParsingStatus': receiptParsingStatusPending,
        'receiptParsedAt': null,
        'receiptParsingMessage': 'Structured receipt parsing is in progress.',
      },
      SetOptions(merge: true),
    );
    
    try {
      final Map<String, dynamic> extracted = await _extractReceiptWithApi(
  fileName: fileName,
  contentType: contentType,
  bytes: bytes,
);

final DateTime parsedAt = DateTime.now();

final int? lotteryId =
    extracted['lotteryId'] is num ? (extracted['lotteryId'] as num).toInt() : null;
final String? ticketType = extracted['ticketType'] as String?;
final String? fingerprint = extracted['ticketFingerprint'] as String?;
final String? fingerprintSource =
    extracted['ticketFingerprintSource'] as String?;

final List<Map<String, dynamic>> parsedTables =
    ((extracted['tables'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((dynamic table) => Map<String, dynamic>.from(table as Map))
        .toList();

debugPrint(
  '[OperatorConsole] extractor api completed for $receiptId '
  'lotteryId=$lotteryId '
  'ticketType=$ticketType '
  'tableCount=${parsedTables.length}',
);
await _autoMatchReceiptByFingerprint(
  receiptId: receiptId,
  receiptFingerprint: fingerprint,
);
await receiptRef.set(
  <String, dynamic>{
    'receiptLotteryIdHint': lotteryId,
    'receiptTicketTypeHint': ticketType,
    'receiptTableCountHint': parsedTables.length,
    'receiptParsedTables': parsedTables,
    'receiptFingerprintSource': fingerprintSource,
    'receiptFingerprint': fingerprint,
    'receiptFingerprintHint': fingerprint,
    'receiptFingerprintPrefixHint': _prefixOrNull(fingerprint, 8),
    'receiptFingerprintSourcePrefixHint':
        _prefixOrNull(fingerprintSource, 24),
    'receiptParsedAt': parsedAt,
    'receiptParsingStatus': receiptParsingStatusParsed,
    'receiptParsingMessage': 'Parsed successfully via extractor API.',
  },
  SetOptions(merge: true),
);
    } catch (error, stackTrace) {
      debugPrint(
          '[OperatorConsole] receipt parsing failure for $receiptId: $error');
      debugPrint('$stackTrace');

      await receiptRef.set(
        <String, dynamic>{
          'receiptTicketTypeHint': null,
          'receiptParsedTables': const <Map<String, dynamic>>[],
          'receiptFingerprintSource': null,
          'receiptFingerprint': null,
          'receiptParsedAt': DateTime.now(),
          'receiptParsingStatus': receiptParsingStatusFailed,
          'receiptParsingMessage': 'Receipt parsing via extractor API crashed: $error',
        },
        SetOptions(merge: true),
      );
    }

    final DocumentSnapshot<Map<String, dynamic>> refreshedSnapshot =
        await receiptRef.get();
    final Map<String, dynamic>? refreshedData = refreshedSnapshot.data();
    if (!refreshedSnapshot.exists || refreshedData == null) {
      return;
    }

    await refreshSuggestionsForReceipt(
      receipt: ReceiptIntakeRecord.fromFirestore(receiptId, refreshedData),
      force: true,
    );
  }

  List<ReceiptParsedTable> _submittedTablesFromData(dynamic rawTables) {
    if (rawTables is! List) {
      return const <ReceiptParsedTable>[];
    }

    final List<ReceiptParsedTable> normalizedTables = <ReceiptParsedTable>[];
    for (var index = 0; index < rawTables.length; index += 1) {
      final dynamic rawTable = rawTables[index];
      if (rawTable is! Map) {
        continue;
      }
      final ReceiptParsedTable parsedTable =
          ReceiptParsedTable.fromMap(Map<String, dynamic>.from(rawTable));
      normalizedTables.add(
        ReceiptParsedTable(
          tableIndex: index + 1,
          regularNumbers: parsedTable.regularNumbers,
          strongNumber: parsedTable.strongNumber,
        ),
      );
    }
    return List<ReceiptParsedTable>.unmodifiable(normalizedTables);
  }

  bool _receiptTablesStronglyAlign(
    List<ReceiptParsedTable> receiptTables,
    List<ReceiptParsedTable> candidateTables,
  ) {
    if (receiptTables.isEmpty || candidateTables.isEmpty) {
      return false;
    }

    final Set<String> candidateRows =
        candidateTables.map((table) => table.canonicalRow).toSet();
    final int exactMatches = receiptTables
        .where((table) => candidateRows.contains(table.canonicalRow))
        .length;

    return exactMatches == receiptTables.length ||
        (receiptTables.length >= 2 && exactMatches >= 2);
  }

  // ---------------------------------------------------------------------------
  // Archive
  // ---------------------------------------------------------------------------

  Future<void> archiveReceipt({
    required ReceiptIntakeRecord receipt,
  }) async {
    final String operatorUserId = _auth.currentUser?.uid ?? '';
    if (operatorUserId.isEmpty) {
      throw StateError('Authentication is required.');
    }
    await _firestore
        .collection('receipt_intake')
        .doc(receipt.receiptId)
        .set(
          <String, dynamic>{
            'isArchived': true,
            'archivedAt': DateTime.now(),
            'archivedBy': operatorUserId,
          },
          SetOptions(merge: true),
        );
    debugPrint('[OperatorConsole] archived receipt ${receipt.receiptId}');
  }

  // ---------------------------------------------------------------------------
  // Delete
  // ---------------------------------------------------------------------------

  Future<void> deleteReceipt({
    required ReceiptIntakeRecord receipt,
  }) async {
    final String operatorUserId = _auth.currentUser?.uid ?? '';
    if (operatorUserId.isEmpty) {
      throw StateError('Authentication is required.');
    }

    // If matched, clean up the form reference first
    if (receipt.matchedFormId != null &&
        receipt.matchedFormOwnerUserId != null) {
      try {
        await _firestore
            .collection('users')
            .doc(receipt.matchedFormOwnerUserId)
            .collection('forms')
            .doc(receipt.matchedFormId)
            .set(
              <String, dynamic>{
                'stationReceiptUrl': null,
                'stationReceiptStoragePath': null,
                'stationReceiptUploadedAt': null,
                'stationReceiptMatchStatus': null,
                'stationReceiptMatchedAt': null,
                'stationReceiptMatchedBy': null,
                'stationReceiptIntakeId': null,
              },
              SetOptions(merge: true),
            );
        debugPrint(
          '[OperatorConsole] cleared form receipt ref for ${receipt.matchedFormId}',
        );
      } catch (error) {
        debugPrint(
          '[OperatorConsole] failed to clear form receipt ref: $error',
        );
      }
    }

    // Delete the Firestore document
    await _firestore
        .collection('receipt_intake')
        .doc(receipt.receiptId)
        .delete();

    // Best-effort: delete storage file
    if (receipt.storagePath.isNotEmpty) {
      try {
        await _storage.ref(receipt.storagePath).delete();
      } catch (error) {
        debugPrint(
          '[OperatorConsole] storage delete failed for ${receipt.storagePath}: $error',
        );
      }
    }

    debugPrint('[OperatorConsole] deleted receipt ${receipt.receiptId}');
  }
}

class _ScoredCandidate {
  const _ScoredCandidate({
    required this.candidate,
    required this.exactFingerprintMatch,
    required this.score,
    required this.reasons,
  });

  final DispatchOverviewItem candidate;
  final bool exactFingerprintMatch;
  final int score;
  final List<String> reasons;
}