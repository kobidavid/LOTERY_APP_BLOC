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

enum LotteryGroupBundleType {
  singleForm,
  multiForm,
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
    required this.cancelledAt,
    required this.cancelledByUserId,
    required this.cancelledByDisplayName,
    required this.totalRefundedAmount,
    required this.submittedFormId,
    required this.dispatchStatus,
    required this.printReadyUrl,
    required this.printReadyGeneratedAt,
    required this.printedAt,
    required this.submittedToStationAt,
    required this.lotteryId,
    required this.salesCloseAt,
    required this.resultPublishedAt,
    required this.groupWinningAmount,
    required this.bundleType,
    required this.formCount,
    required this.totalTableCount,
    required this.totalCost,
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
  final DateTime? cancelledAt;
  final String? cancelledByUserId;
  final String? cancelledByDisplayName;
  final num totalRefundedAmount;
  final String? submittedFormId;
  final String? dispatchStatus;
  final String? printReadyUrl;
  final DateTime? printReadyGeneratedAt;
  final DateTime? printedAt;
  final DateTime? submittedToStationAt;
  final int? lotteryId;
  final DateTime? salesCloseAt;
  final DateTime? resultPublishedAt;
  final num groupWinningAmount;
  final LotteryGroupBundleType bundleType;
  final int formCount;
  final int totalTableCount;
  final num totalCost;

  int get populatedTableCount => tables.where((table) => !table.isEmpty).length;
  bool get isMultiFormBundle => bundleType == LotteryGroupBundleType.multiForm;

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
      cancelledAt: _asDateTime(map['cancelledAt']),
      cancelledByUserId: map['cancelledByUserId'] as String?,
      cancelledByDisplayName: map['cancelledByDisplayName'] as String?,
      totalRefundedAmount: (map['totalRefundedAmount'] as num?) ?? 0,
      submittedFormId: map['submittedFormId'] as String?,
      dispatchStatus: map['dispatchStatus'] as String?,
      printReadyUrl: map['printReadyUrl'] as String?,
      printReadyGeneratedAt: _asDateTime(map['printReadyGeneratedAt']),
      printedAt: _asDateTime(map['printedAt']),
      submittedToStationAt: _asDateTime(map['submittedToStationAt']),
      lotteryId: (map['lotteryId'] as num?)?.toInt() ??
          (map['drawNumber'] as num?)?.toInt() ??
          (snapshot['lotteryId'] as num?)?.toInt(),
      salesCloseAt: _asDateTime(map['salesCloseAt']) ??
          _asDateTime(map['drawDate']) ??
          _asDateTime(snapshot['salesCloseAt']),
      resultPublishedAt: _asDateTime(map['resultPublishedAt']),
      groupWinningAmount: (map['groupWinningAmount'] as num?) ?? 0,
      bundleType: _bundleTypeFromString(map['bundleType'] as String?),
      formCount: (map['formCount'] as num?)?.toInt() ?? 1,
      totalTableCount: (map['totalTableCount'] as num?)?.toInt() ??
          rawTables
              .map((item) => LotteryTable.fromMap(item as Map<String, dynamic>))
              .where((table) => !table.isEmpty)
              .length,
      totalCost: (map['totalCost'] as num?) ?? (map['baseTicketCost'] as num?) ?? 0,
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

  static LotteryGroupBundleType _bundleTypeFromString(String? value) {
    switch (value) {
      case 'multi_form':
        return LotteryGroupBundleType.multiForm;
      default:
        return LotteryGroupBundleType.singleForm;
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
        cancelledAt,
        cancelledByUserId,
        cancelledByDisplayName,
        totalRefundedAmount,
        submittedFormId,
        dispatchStatus,
        printReadyUrl,
        printReadyGeneratedAt,
        printedAt,
        submittedToStationAt,
        lotteryId,
        salesCloseAt,
        resultPublishedAt,
        groupWinningAmount,
        bundleType,
        formCount,
        totalTableCount,
        totalCost,
      ];
}

class LotteryGroupForm extends Equatable {
  const LotteryGroupForm({
    required this.formId,
    required this.groupId,
    required this.displayOrder,
    required this.sourceUserId,
    required this.sourceDraftNumber,
    required this.status,
    required this.mode,
    required this.isDoubleMode,
    required this.tableCount,
    required this.cost,
    required this.tables,
    required this.isComplete,
    required this.createdAt,
    required this.updatedAt,
    required this.dispatchStatus,
    required this.printReadyUrl,
    required this.printedAt,
    required this.submittedToStationAt,
    required this.resultStatus,
    required this.winAmount,
    required this.receiptUrl,
    required this.lotteryId,
    required this.salesCloseAt,
    required this.rawData,
  });

  final String formId;
  final String groupId;
  final int displayOrder;
  final String sourceUserId;
  final int sourceDraftNumber;
  final String status;
  final String mode;
  final bool isDoubleMode;
  final int tableCount;
  final num cost;
  final List<LotteryTable> tables;
  final bool isComplete;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? dispatchStatus;
  final String? printReadyUrl;
  final DateTime? printedAt;
  final DateTime? submittedToStationAt;
  final String? resultStatus;
  final num? winAmount;
  final String? receiptUrl;
  final int? lotteryId;
  final DateTime? salesCloseAt;
  final Map<String, dynamic> rawData;

  factory LotteryGroupForm.fromFirestore(
    String formId,
    Map<String, dynamic> map,
  ) {
    final List<dynamic> rawTables = map['tables'] as List<dynamic>? ?? <dynamic>[];
    return LotteryGroupForm(
      formId: formId,
      groupId: map['groupId'] as String? ?? '',
      displayOrder: (map['displayOrder'] as num?)?.toInt() ?? 0,
      sourceUserId: map['sourceUserId'] as String? ?? '',
      sourceDraftNumber: (map['sourceDraftNumber'] as num?)?.toInt() ?? 0,
      status: map['status'] as String? ?? '',
      mode: map['mode'] as String? ?? '',
      isDoubleMode: map['isDoubleMode'] as bool? ?? false,
      tableCount: (map['tableCount'] as num?)?.toInt() ?? rawTables.length,
      cost: (map['cost'] as num?) ?? 0,
      tables: rawTables
          .map((item) => LotteryTable.fromMap(item as Map<String, dynamic>))
          .toList(),
      isComplete: map['isComplete'] as bool? ?? false,
      createdAt: LotteryGroup._asDateTime(map['createdAt']),
      updatedAt: LotteryGroup._asDateTime(map['updatedAt']),
      dispatchStatus: map['dispatchStatus'] as String?,
      printReadyUrl: map['printReadyUrl'] as String?,
      printedAt: LotteryGroup._asDateTime(map['printedAt']),
      submittedToStationAt: LotteryGroup._asDateTime(map['submittedToStationAt']),
      resultStatus: map['resultStatus'] as String?,
      winAmount: map['winAmount'] as num?,
      receiptUrl: _extractLotteryGroupFormReceiptUrl(map),
      lotteryId:
          (map['lotteryId'] as num?)?.toInt() ??
          (map['drawNumber'] as num?)?.toInt(),
      salesCloseAt:
          LotteryGroup._asDateTime(map['salesCloseAt']) ??
          LotteryGroup._asDateTime(map['drawDate']),
      rawData: Map<String, dynamic>.from(map),
    );
  }

  @override
  List<Object?> get props => [
        formId,
        groupId,
        displayOrder,
        sourceUserId,
        sourceDraftNumber,
        status,
        mode,
        isDoubleMode,
        tableCount,
        cost,
        tables,
        isComplete,
        createdAt,
        updatedAt,
        dispatchStatus,
        printReadyUrl,
        printedAt,
        submittedToStationAt,
        resultStatus,
        winAmount,
        receiptUrl,
        lotteryId,
        salesCloseAt,
        rawData,
      ];
}

String? _extractLotteryGroupFormReceiptUrl(Map<String, dynamic> data) {
  final List<String> candidateKeys = <String>[
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
