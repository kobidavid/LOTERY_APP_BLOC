import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

import 'receipt_parsed_table.dart';

class ReceiptIntakeRecord extends Equatable {
  const ReceiptIntakeRecord({
    required this.receiptId,
    required this.uploadedAt,
    required this.uploadedBy,
    required this.uploadedByDisplayName,
    required this.storagePath,
    required this.downloadUrl,
    required this.contentType,
    required this.fileName,
    required this.intakeStatus,
    required this.matchedFormId,
    required this.matchedFormOwnerUserId,
    required this.matchedGroupId,
    required this.matchedLotteryId,
    required this.matchedAt,
    required this.matchedBy,
    required this.matchMessage,
    required this.notes,
    required this.suggestedFormIds,
    required this.suggestionScores,
    required this.suggestionsGeneratedAt,
    required this.receiptCreatorUserIdHint,
    required this.receiptCreatorNameHint,
    required this.receiptTicketTypeHint,
    required this.receiptTableCountHint,
    required this.receiptFingerprintHint,
    required this.receiptFingerprintPrefixHint,
    required this.receiptFingerprintSourcePrefixHint,
    required this.receiptLotteryIdHint,
    required this.receiptParsedTables,
    required this.receiptFingerprintSource,
    required this.receiptFingerprint,
    required this.receiptParsedAt,
    required this.receiptParsingStatus,
    required this.receiptParsingMessage,
    required this.lastMatchedFormId,
    required this.lastMatchedGroupId,
    required this.lastMatchedLotteryId,
    required this.lastMatchedCreatorUserId,
    required this.lastMatchedTableCount,
    required this.lastMatchedFingerprint,
    required this.lastMatchedAt,
    // Archive support — new field, nullable/false by default
    this.isArchived,
  });

  final String receiptId;
  final DateTime? uploadedAt;
  final String uploadedBy;
  final String? uploadedByDisplayName;
  final String storagePath;
  final String? downloadUrl;
  final String contentType;
  final String fileName;
  final String intakeStatus;
  final String? matchedFormId;
  final String? matchedFormOwnerUserId;
  final String? matchedGroupId;
  final int? matchedLotteryId;
  final DateTime? matchedAt;
  final String? matchedBy;
  final String? matchMessage;
  final String? notes;
  final List<String> suggestedFormIds;
  final Map<String, double> suggestionScores;
  final DateTime? suggestionsGeneratedAt;
  final String? receiptCreatorUserIdHint;
  final String? receiptCreatorNameHint;
  final String? receiptTicketTypeHint;
  final int? receiptTableCountHint;
  final String? receiptFingerprintHint;
  final String? receiptFingerprintPrefixHint;
  final String? receiptFingerprintSourcePrefixHint;
  final int? receiptLotteryIdHint;
  final List<ReceiptParsedTable> receiptParsedTables;
  final String? receiptFingerprintSource;
  final String? receiptFingerprint;
  final DateTime? receiptParsedAt;
  final String? receiptParsingStatus;
  final String? receiptParsingMessage;
  final String? lastMatchedFormId;
  final String? lastMatchedGroupId;
  final int? lastMatchedLotteryId;
  final String? lastMatchedCreatorUserId;
  final int? lastMatchedTableCount;
  final String? lastMatchedFingerprint;
  final DateTime? lastMatchedAt;
  // Archive flag — null treated as false for backwards compatibility
  final bool? isArchived;

  factory ReceiptIntakeRecord.fromFirestore(
    String receiptId,
    Map<String, dynamic> map,
  ) {
    return ReceiptIntakeRecord(
      receiptId: receiptId,
      uploadedAt: _asDateTime(map['uploadedAt']),
      uploadedBy: map['uploadedBy'] as String? ?? '',
      uploadedByDisplayName: map['uploadedByDisplayName'] as String?,
      storagePath: map['storagePath'] as String? ?? '',
      downloadUrl: map['downloadUrl'] as String?,
      contentType: map['contentType'] as String? ?? 'application/octet-stream',
      fileName: map['fileName'] as String? ?? receiptId,
      intakeStatus: map['intakeStatus'] as String? ?? 'uploaded',
      matchedFormId: map['matchedFormId'] as String?,
      matchedFormOwnerUserId: map['matchedFormOwnerUserId'] as String?,
      matchedGroupId: map['matchedGroupId'] as String?,
      matchedLotteryId: (map['matchedLotteryId'] as num?)?.toInt(),
      matchedAt: _asDateTime(map['matchedAt']),
      matchedBy: map['matchedBy'] as String?,
      matchMessage: map['matchMessage'] as String?,
      notes: map['notes'] as String?,
      suggestedFormIds: (map['suggestedFormIds'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      suggestionScores: _asScoreMap(map['suggestionScores']),
      suggestionsGeneratedAt: _asDateTime(map['suggestionsGeneratedAt']),
      receiptCreatorUserIdHint: map['receiptCreatorUserIdHint'] as String?,
      receiptCreatorNameHint: map['receiptCreatorNameHint'] as String?,
      receiptTicketTypeHint: map['receiptTicketTypeHint'] as String?,
      receiptTableCountHint: (map['receiptTableCountHint'] as num?)?.toInt(),
      receiptFingerprintHint: map['receiptFingerprintHint'] as String?,
      receiptFingerprintPrefixHint:
          map['receiptFingerprintPrefixHint'] as String?,
      receiptFingerprintSourcePrefixHint:
          map['receiptFingerprintSourcePrefixHint'] as String?,
      receiptLotteryIdHint: (map['receiptLotteryIdHint'] as num?)?.toInt(),
      receiptParsedTables:
          (map['receiptParsedTables'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map>()
              .map((item) =>
                  ReceiptParsedTable.fromMap(Map<String, dynamic>.from(item)))
              .toList(),
      receiptFingerprintSource: map['receiptFingerprintSource'] as String?,
      receiptFingerprint: map['receiptFingerprint'] as String?,
      receiptParsedAt: _asDateTime(map['receiptParsedAt']),
      receiptParsingStatus: map['receiptParsingStatus'] as String?,
      receiptParsingMessage: map['receiptParsingMessage'] as String?,
      lastMatchedFormId: map['lastMatchedFormId'] as String?,
      lastMatchedGroupId: map['lastMatchedGroupId'] as String?,
      lastMatchedLotteryId: (map['lastMatchedLotteryId'] as num?)?.toInt(),
      lastMatchedCreatorUserId: map['lastMatchedCreatorUserId'] as String?,
      lastMatchedTableCount: (map['lastMatchedTableCount'] as num?)?.toInt(),
      lastMatchedFingerprint: map['lastMatchedFingerprint'] as String?,
      lastMatchedAt: _asDateTime(map['lastMatchedAt']),
      isArchived: map['isArchived'] as bool?,
    );
  }

  static Map<String, double> _asScoreMap(dynamic value) {
    if (value is! Map<String, dynamic>) {
      return const <String, double>{};
    }
    return value.map(
      (key, rawValue) => MapEntry(
        key,
        rawValue is num ? rawValue.toDouble() : 0,
      ),
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

  @override
  List<Object?> get props => [
        receiptId,
        uploadedAt,
        uploadedBy,
        uploadedByDisplayName,
        storagePath,
        downloadUrl,
        contentType,
        fileName,
        intakeStatus,
        matchedFormId,
        matchedFormOwnerUserId,
        matchedGroupId,
        matchedLotteryId,
        matchedAt,
        matchedBy,
        matchMessage,
        notes,
        suggestedFormIds,
        suggestionScores,
        suggestionsGeneratedAt,
        receiptCreatorUserIdHint,
        receiptCreatorNameHint,
        receiptTicketTypeHint,
        receiptTableCountHint,
        receiptFingerprintHint,
        receiptFingerprintPrefixHint,
        receiptFingerprintSourcePrefixHint,
        receiptLotteryIdHint,
        receiptParsedTables,
        receiptFingerprintSource,
        receiptFingerprint,
        receiptParsedAt,
        receiptParsingStatus,
        receiptParsingMessage,
        lastMatchedFormId,
        lastMatchedGroupId,
        lastMatchedLotteryId,
        lastMatchedCreatorUserId,
        lastMatchedTableCount,
        lastMatchedFingerprint,
        lastMatchedAt,
        isArchived,
      ];
}