import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

import 'lottery_table.dart';

enum LotteryFormStatus {
  draft,
  saved,
  submitted,
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
      case LotteryFormStatus.submitted:
        return 'submitted';
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
    required this.status,
    required this.tables,
    required this.isComplete,
    required this.createdAt,
    required this.updatedAt,
    required this.submittedAt,
    required this.savedAt,
    required this.source,
    required this.version,
    required this.lotteryId,
    required this.salesCloseAt,
    required this.resultStatus,
    required this.resultPublishedAt,
    required this.winAmount,
    required this.checkedAt,
    required this.balanceApplied,
  });

  final String? formId;
  final String userId;
  final LotteryFormStatus status;
  final List<LotteryTable> tables;
  final bool isComplete;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? submittedAt;
  final DateTime? savedAt;
  final String source;
  final int version;
  final int? lotteryId;
  final DateTime? salesCloseAt;
  final LotteryResultStatus? resultStatus;
  final DateTime? resultPublishedAt;
  final num winAmount;
  final DateTime? checkedAt;
  final bool balanceApplied;

  factory LotteryForm.empty(String userId) {
    return LotteryForm(
      formId: null,
      userId: userId,
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
      source: 'manual',
      version: 1,
      lotteryId: null,
      salesCloseAt: null,
      resultStatus: null,
      resultPublishedAt: null,
      winAmount: 0,
      checkedAt: null,
      balanceApplied: false,
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
      status: _statusFromString(map['status'] as String?),
      tables: rawTables
          .map((item) => LotteryTable.fromMap(item as Map<String, dynamic>))
          .toList(),
      isComplete: map['isComplete'] as bool? ?? false,
      createdAt: _asDateTime(map['createdAt']),
      updatedAt: _asDateTime(map['updatedAt']),
      submittedAt: _asDateTime(map['submittedAt']),
      savedAt: _asDateTime(map['savedAt']),
      source: map['source'] as String? ?? 'manual',
      version: (map['version'] as num?)?.toInt() ?? 1,
      lotteryId: (map['lotteryId'] as num?)?.toInt(),
      salesCloseAt: _asDateTime(map['salesCloseAt']),
      resultStatus: _resultStatusFromString(map['resultStatus'] as String?),
      resultPublishedAt: _asDateTime(map['resultPublishedAt']),
      winAmount: (map['winAmount'] as num?) ?? 0,
      checkedAt: _asDateTime(map['checkedAt']),
      balanceApplied: map['balanceApplied'] as bool? ?? false,
    );
  }

  static LotteryFormStatus _statusFromString(String? value) {
    switch (value) {
      case 'saved':
        return LotteryFormStatus.saved;
      case 'submitted':
        return LotteryFormStatus.submitted;
      default:
        return LotteryFormStatus.draft;
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
    LotteryFormStatus? status,
    List<LotteryTable>? tables,
    bool? isComplete,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? submittedAt,
    DateTime? savedAt,
    String? source,
    int? version,
    int? lotteryId,
    DateTime? salesCloseAt,
    LotteryResultStatus? resultStatus,
    DateTime? resultPublishedAt,
    num? winAmount,
    DateTime? checkedAt,
    bool? balanceApplied,
    bool clearId = false,
    bool clearSubmittedAt = false,
    bool clearSavedAt = false,
    bool clearLotteryId = false,
    bool clearSalesCloseAt = false,
    bool clearResultStatus = false,
    bool clearResultPublishedAt = false,
    bool clearCheckedAt = false,
  }) {
    return LotteryForm(
      formId: clearId ? null : (formId ?? this.formId),
      userId: userId ?? this.userId,
      status: status ?? this.status,
      tables: tables ?? this.tables,
      isComplete: isComplete ?? this.isComplete,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      submittedAt: clearSubmittedAt ? null : (submittedAt ?? this.submittedAt),
      savedAt: clearSavedAt ? null : (savedAt ?? this.savedAt),
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
    );
  }

  @override
  List<Object?> get props => [
        formId,
        userId,
        status,
        tables,
        isComplete,
        createdAt,
        updatedAt,
        submittedAt,
        savedAt,
        source,
        version,
        lotteryId,
        salesCloseAt,
        resultStatus,
        resultPublishedAt,
        winAmount,
        checkedAt,
        balanceApplied,
      ];
}
