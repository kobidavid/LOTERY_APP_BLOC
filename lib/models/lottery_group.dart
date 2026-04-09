import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

import 'lottery_table.dart';

enum LotteryGroupStatus {
  collectingResponses,
  awaitingPayments,
  readyForSubmission,
  submitted,
  cancelled,
}

extension LotteryGroupStatusX on LotteryGroupStatus {
  String get value {
    switch (this) {
      case LotteryGroupStatus.collectingResponses:
        return 'collecting_responses';
      case LotteryGroupStatus.awaitingPayments:
        return 'awaiting_payments';
      case LotteryGroupStatus.readyForSubmission:
        return 'ready_for_submission';
      case LotteryGroupStatus.submitted:
        return 'submitted';
      case LotteryGroupStatus.cancelled:
        return 'cancelled';
    }
  }
}

class LotteryGroup extends Equatable {
  const LotteryGroup({
    required this.groupId,
    required this.groupName,
    required this.creatorUserId,
    required this.sourceFormId,
    required this.status,
    required this.inviteToken,
    required this.tables,
    required this.isComplete,
    required this.baseTicketCost,
    required this.currentPerParticipantCost,
    required this.finalizedParticipantCount,
    required this.createdAt,
    required this.updatedAt,
    required this.finalizedAt,
    required this.submittedAt,
    required this.submittedFormId,
    required this.dispatchStatus,
    required this.printReadyUrl,
    required this.printReadyGeneratedAt,
    required this.printedAt,
    required this.submittedToStationAt,
  });

  final String groupId;
  final String groupName;
  final String creatorUserId;
  final String sourceFormId;
  final LotteryGroupStatus status;
  final String inviteToken;
  final List<LotteryTable> tables;
  final bool isComplete;
  final num baseTicketCost;
  final num currentPerParticipantCost;
  final int finalizedParticipantCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? finalizedAt;
  final DateTime? submittedAt;
  final String? submittedFormId;
  final String? dispatchStatus;
  final String? printReadyUrl;
  final DateTime? printReadyGeneratedAt;
  final DateTime? printedAt;
  final DateTime? submittedToStationAt;

  int get populatedTableCount => tables.where((table) => !table.isEmpty).length;

  static DateTime? _asDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }

  factory LotteryGroup.fromFirestore(
    String groupId,
    Map<String, dynamic> map,
  ) {
    final Map<String, dynamic> snapshot =
        Map<String, dynamic>.from(map['formSnapshot'] as Map? ?? const {});
    final List<dynamic> rawTables =
        snapshot['tables'] as List<dynamic>? ?? <dynamic>[];
    return LotteryGroup(
      groupId: groupId,
      groupName: map['groupName'] as String? ?? '',
      creatorUserId: map['creatorUserId'] as String? ?? '',
      sourceFormId: map['sourceFormId'] as String? ?? '',
      status: _statusFromString(map['status'] as String?),
      inviteToken: map['inviteToken'] as String? ?? '',
      tables: rawTables
          .map((item) => LotteryTable.fromMap(item as Map<String, dynamic>))
          .toList(),
      isComplete: snapshot['isComplete'] as bool? ?? false,
      baseTicketCost: (map['baseTicketCost'] as num?) ?? 0,
      currentPerParticipantCost:
          (map['currentPerParticipantCost'] as num?) ?? 0,
      finalizedParticipantCount:
          (map['finalizedParticipantCount'] as num?)?.toInt() ?? 0,
      createdAt: _asDateTime(map['createdAt']),
      updatedAt: _asDateTime(map['updatedAt']),
      finalizedAt: _asDateTime(map['finalizedAt']),
      submittedAt: _asDateTime(map['submittedAt']),
      submittedFormId: map['submittedFormId'] as String?,
      dispatchStatus: map['dispatchStatus'] as String?,
      printReadyUrl: map['printReadyUrl'] as String?,
      printReadyGeneratedAt: _asDateTime(map['printReadyGeneratedAt']),
      printedAt: _asDateTime(map['printedAt']),
      submittedToStationAt: _asDateTime(map['submittedToStationAt']),
    );
  }

  static LotteryGroupStatus _statusFromString(String? value) {
    switch (value) {
      case 'awaiting_payments':
        return LotteryGroupStatus.awaitingPayments;
      case 'ready_for_submission':
        return LotteryGroupStatus.readyForSubmission;
      case 'submitted':
        return LotteryGroupStatus.submitted;
      case 'cancelled':
        return LotteryGroupStatus.cancelled;
      default:
        return LotteryGroupStatus.collectingResponses;
    }
  }

  @override
  List<Object?> get props => [
        groupId,
        groupName,
        creatorUserId,
        sourceFormId,
        status,
        inviteToken,
        tables,
        isComplete,
        baseTicketCost,
        currentPerParticipantCost,
        finalizedParticipantCount,
        createdAt,
        updatedAt,
        finalizedAt,
        submittedAt,
        submittedFormId,
        dispatchStatus,
        printReadyUrl,
        printReadyGeneratedAt,
        printedAt,
        submittedToStationAt,
      ];
}
