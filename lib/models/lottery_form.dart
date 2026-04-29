import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

import 'lottery_table.dart';

enum LotteryFormStatus {
  draft,
  saved,
  lockedForGroup,
  cancelled,
  submitted,
}

enum LotteryFormMode {
  personal,
  group,
}

enum LotteryResultStatus {
  waitingForResults,
  checked,
  winner,
  loser,
}

extension LotteryFormStatusX on LotteryFormStatus {
  String get value {
    switch (this) {
      case LotteryFormStatus.draft:
        return 'draft';
      case LotteryFormStatus.saved:
        return 'saved';
      case LotteryFormStatus.lockedForGroup:
        return 'locked_for_group';
      case LotteryFormStatus.cancelled:
        return 'cancelled';
      case LotteryFormStatus.submitted:
        return 'submitted';
    }
  }
}

extension LotteryFormModeX on LotteryFormMode {
  String get value {
    switch (this) {
      case LotteryFormMode.personal:
        return 'personal';
      case LotteryFormMode.group:
        return 'group';
    }
  }
}

extension LotteryResultStatusX on LotteryResultStatus {
  String get value {
    switch (this) {
      case LotteryResultStatus.waitingForResults:
        return 'waiting_for_results';
      case LotteryResultStatus.checked:
        return 'checked';
      case LotteryResultStatus.winner:
        return 'winner';
      case LotteryResultStatus.loser:
        return 'loser';
    }
  }
}

class LotteryForm extends Equatable {
  const LotteryForm({
    required this.formId,
    required this.userId,
    required this.submissionId,
    required this.parentSubmissionId,
    required this.status,
    required this.tables,
    required this.isComplete,
    required this.createdAt,
    required this.updatedAt,
    required this.submittedAt,
    required this.savedAt,
    required this.cancelledAt,
    required this.cancelledByUserId,
    required this.cancelledByDisplayName,
    required this.refundAmount,
    required this.source,
    required this.version,
    required this.lotteryId,
    required this.salesCloseAt,
    required this.resultStatus,
    required this.resultPublishedAt,
    required this.winAmount,
    required this.checkedAt,
    required this.balanceApplied,
    required this.mode,
    required this.groupId,
    required this.isEditable,
    required this.dispatchStatus,
    required this.printReadyUrl,
    required this.printReadyGeneratedAt,
    required this.printReadyStoragePath,
    required this.printedAt,
    required this.submittedToStationAt,
    required this.ticketFingerprintSource,
    required this.ticketFingerprint,
    required this.fingerprintVersion,
  });

  final String? formId;
  final String userId;
  final String? submissionId;
  final String? parentSubmissionId;
  final LotteryFormStatus status;
  final List<LotteryTable> tables;
  final bool isComplete;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? submittedAt;
  final DateTime? savedAt;
  final DateTime? cancelledAt;
  final String? cancelledByUserId;
  final String? cancelledByDisplayName;
  final num refundAmount;
  final String source;
  final int version;
  final int? lotteryId;
  final DateTime? salesCloseAt;
  final LotteryResultStatus? resultStatus;
  final DateTime? resultPublishedAt;
  final num winAmount;
  final DateTime? checkedAt;
  final bool balanceApplied;
  final LotteryFormMode mode;
  final String? groupId;
  final bool isEditable;
  final String? dispatchStatus;
  final String? printReadyUrl;
  final DateTime? printReadyGeneratedAt;
  final String? printReadyStoragePath;
  final DateTime? printedAt;
  final DateTime? submittedToStationAt;
  final String? ticketFingerprintSource;
  final String? ticketFingerprint;
  final int? fingerprintVersion;

  factory LotteryForm.empty(String userId) {
    return LotteryForm(
      formId: null,
      userId: userId,
      submissionId: null,
      parentSubmissionId: null,
      status: LotteryFormStatus.draft,
      tables: List<LotteryTable>.generate(
        14,
        (index) => LotteryTable.empty(index + 1),
      ),
      isComplete: false,
      createdAt: null,
      updatedAt: null,
      submittedAt: null,
      savedAt: null,
      cancelledAt: null,
      cancelledByUserId: null,
      cancelledByDisplayName: null,
      refundAmount: 0,
      source: 'manual',
      version: 1,
      lotteryId: null,
      salesCloseAt: null,
      resultStatus: null,
      resultPublishedAt: null,
      winAmount: 0,
      checkedAt: null,
      balanceApplied: false,
      mode: LotteryFormMode.personal,
      groupId: null,
      isEditable: true,
      dispatchStatus: null,
      printReadyUrl: null,
      printReadyGeneratedAt: null,
      printReadyStoragePath: null,
      printedAt: null,
      submittedToStationAt: null,
      ticketFingerprintSource: null,
      ticketFingerprint: null,
      fingerprintVersion: null,
    );
  }

  factory LotteryForm.fromFirestore(
    String formId,
    Map<String, dynamic> map,
  ) {
    final List<dynamic> rawTables =
        map['tables'] as List<dynamic>? ?? <dynamic>[];
    return LotteryForm(
      formId: formId,
      userId: map['userId'] as String? ?? '',
      submissionId: map['submissionId'] as String?,
      parentSubmissionId: map['parentSubmissionId'] as String?,
      status: _statusFromString(map['status'] as String?),
      tables: rawTables
          .map((item) => LotteryTable.fromMap(item as Map<String, dynamic>))
          .toList(),
      isComplete: map['isComplete'] as bool? ?? false,
      createdAt: _asDateTime(map['createdAt']),
      updatedAt: _asDateTime(map['updatedAt']),
      submittedAt: _asDateTime(map['submittedAt']),
      savedAt: _asDateTime(map['savedAt']),
      cancelledAt: _asDateTime(map['cancelledAt']),
      cancelledByUserId: map['cancelledByUserId'] as String?,
      cancelledByDisplayName: map['cancelledByDisplayName'] as String?,
      refundAmount: (map['refundAmount'] as num?) ?? 0,
      source: map['source'] as String? ?? 'manual',
      version: (map['version'] as num?)?.toInt() ?? 1,
      lotteryId:
          (map['lotteryId'] as num?)?.toInt() ??
          (map['drawNumber'] as num?)?.toInt(),
      salesCloseAt:
          _asDateTime(map['salesCloseAt']) ?? _asDateTime(map['drawDate']),
      resultStatus: _resultStatusFromString(map['resultStatus'] as String?),
      resultPublishedAt: _asDateTime(map['resultPublishedAt']),
      winAmount: (map['winAmount'] as num?) ?? 0,
      checkedAt: _asDateTime(map['checkedAt']),
      balanceApplied: map['balanceApplied'] as bool? ?? false,
      mode: _modeFromString(map['mode'] as String?),
      groupId: map['groupId'] as String?,
      isEditable: map['isEditable'] as bool? ?? true,
      dispatchStatus: map['dispatchStatus'] as String?,
      printReadyUrl: map['printReadyUrl'] as String?,
      printReadyGeneratedAt: _asDateTime(map['printReadyGeneratedAt']),
      printReadyStoragePath: map['printReadyStoragePath'] as String?,
      printedAt: _asDateTime(map['printedAt']),
      submittedToStationAt: _asDateTime(map['submittedToStationAt']),
      ticketFingerprintSource: map['ticketFingerprintSource'] as String?,
      ticketFingerprint: map['ticketFingerprint'] as String?,
      fingerprintVersion: (map['fingerprintVersion'] as num?)?.toInt(),
    );
  }

  static LotteryFormStatus _statusFromString(String? value) {
    switch (value) {
      case 'saved':
        return LotteryFormStatus.saved;
      case 'submitted':
        return LotteryFormStatus.submitted;
      case 'cancelled':
        return LotteryFormStatus.cancelled;
      case 'locked_for_group':
        return LotteryFormStatus.lockedForGroup;
      default:
        return LotteryFormStatus.draft;
    }
  }

  static LotteryFormMode _modeFromString(String? value) {
    switch (value) {
      case 'group':
        return LotteryFormMode.group;
      default:
        return LotteryFormMode.personal;
    }
  }

  static LotteryResultStatus? _resultStatusFromString(String? value) {
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

  static DateTime? _asDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }

  LotteryForm copyWith({
    String? formId,
    String? userId,
    String? submissionId,
    String? parentSubmissionId,
    LotteryFormStatus? status,
    List<LotteryTable>? tables,
    bool? isComplete,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? submittedAt,
    DateTime? savedAt,
    DateTime? cancelledAt,
    String? cancelledByUserId,
    String? cancelledByDisplayName,
    num? refundAmount,
    String? source,
    int? version,
    int? lotteryId,
    DateTime? salesCloseAt,
    LotteryResultStatus? resultStatus,
    DateTime? resultPublishedAt,
    num? winAmount,
    DateTime? checkedAt,
    bool? balanceApplied,
    LotteryFormMode? mode,
    String? groupId,
    bool? isEditable,
    String? dispatchStatus,
    String? printReadyUrl,
    DateTime? printReadyGeneratedAt,
    String? printReadyStoragePath,
    DateTime? printedAt,
    DateTime? submittedToStationAt,
    String? ticketFingerprintSource,
    String? ticketFingerprint,
    int? fingerprintVersion,
    bool clearId = false,
    bool clearSubmissionId = false,
    bool clearParentSubmissionId = false,
    bool clearSubmittedAt = false,
    bool clearSavedAt = false,
    bool clearCancelledAt = false,
    bool clearCancelledByUserId = false,
    bool clearCancelledByDisplayName = false,
    bool clearLotteryId = false,
    bool clearSalesCloseAt = false,
    bool clearResultStatus = false,
    bool clearResultPublishedAt = false,
    bool clearCheckedAt = false,
    bool clearGroupId = false,
  }) {
    return LotteryForm(
      formId: clearId ? null : (formId ?? this.formId),
      userId: userId ?? this.userId,
      submissionId:
          clearSubmissionId ? null : (submissionId ?? this.submissionId),
      parentSubmissionId: clearParentSubmissionId
          ? null
          : (parentSubmissionId ?? this.parentSubmissionId),
      status: status ?? this.status,
      tables: tables ?? this.tables,
      isComplete: isComplete ?? this.isComplete,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      submittedAt: clearSubmittedAt ? null : (submittedAt ?? this.submittedAt),
      savedAt: clearSavedAt ? null : (savedAt ?? this.savedAt),
      cancelledAt: clearCancelledAt ? null : (cancelledAt ?? this.cancelledAt),
      cancelledByUserId: clearCancelledByUserId
          ? null
          : (cancelledByUserId ?? this.cancelledByUserId),
      cancelledByDisplayName: clearCancelledByDisplayName
          ? null
          : (cancelledByDisplayName ?? this.cancelledByDisplayName),
      refundAmount: refundAmount ?? this.refundAmount,
      source: source ?? this.source,
      version: version ?? this.version,
      lotteryId: clearLotteryId ? null : (lotteryId ?? this.lotteryId),
      salesCloseAt:
          clearSalesCloseAt ? null : (salesCloseAt ?? this.salesCloseAt),
      resultStatus:
          clearResultStatus ? null : (resultStatus ?? this.resultStatus),
      resultPublishedAt: clearResultPublishedAt
          ? null
          : (resultPublishedAt ?? this.resultPublishedAt),
      winAmount: winAmount ?? this.winAmount,
      checkedAt: clearCheckedAt ? null : (checkedAt ?? this.checkedAt),
      balanceApplied: balanceApplied ?? this.balanceApplied,
      mode: mode ?? this.mode,
      groupId: clearGroupId ? null : (groupId ?? this.groupId),
      isEditable: isEditable ?? this.isEditable,
      dispatchStatus: dispatchStatus ?? this.dispatchStatus,
      printReadyUrl: printReadyUrl ?? this.printReadyUrl,
      printReadyGeneratedAt:
          printReadyGeneratedAt ?? this.printReadyGeneratedAt,
      printReadyStoragePath:
          printReadyStoragePath ?? this.printReadyStoragePath,
      printedAt: printedAt ?? this.printedAt,
      submittedToStationAt: submittedToStationAt ?? this.submittedToStationAt,
      ticketFingerprintSource:
          ticketFingerprintSource ?? this.ticketFingerprintSource,
      ticketFingerprint: ticketFingerprint ?? this.ticketFingerprint,
      fingerprintVersion: fingerprintVersion ?? this.fingerprintVersion,
    );
  }

  @override
  List<Object?> get props => [
        formId,
        userId,
        submissionId,
        parentSubmissionId,
        status,
        tables,
        isComplete,
        createdAt,
        updatedAt,
        submittedAt,
        savedAt,
        cancelledAt,
        cancelledByUserId,
        cancelledByDisplayName,
        refundAmount,
        source,
        version,
        lotteryId,
        salesCloseAt,
        resultStatus,
        resultPublishedAt,
        winAmount,
        checkedAt,
        balanceApplied,
        mode,
        groupId,
        isEditable,
        dispatchStatus,
        printReadyUrl,
        printReadyGeneratedAt,
        printReadyStoragePath,
        printedAt,
        submittedToStationAt,
        ticketFingerprintSource,
        ticketFingerprint,
        fingerprintVersion,
      ];
}
