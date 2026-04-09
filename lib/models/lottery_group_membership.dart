import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

enum LotteryGroupResponseStatus {
  interested,
  notInterested,
  undecided,
}

extension LotteryGroupResponseStatusX on LotteryGroupResponseStatus {
  String get value {
    switch (this) {
      case LotteryGroupResponseStatus.interested:
        return 'interested';
      case LotteryGroupResponseStatus.notInterested:
        return 'not_interested';
      case LotteryGroupResponseStatus.undecided:
        return 'undecided';
    }
  }
}

enum LotteryGroupPaymentStatus {
  notApplicable,
  unpaid,
  paid,
}

extension LotteryGroupPaymentStatusX on LotteryGroupPaymentStatus {
  String get value {
    switch (this) {
      case LotteryGroupPaymentStatus.notApplicable:
        return 'not_applicable';
      case LotteryGroupPaymentStatus.unpaid:
        return 'unpaid';
      case LotteryGroupPaymentStatus.paid:
        return 'paid';
    }
  }
}

class LotteryGroupMembership extends Equatable {
  const LotteryGroupMembership({
    required this.userId,
    required this.displayName,
    required this.groupId,
    required this.responseStatus,
    required this.minimumParticipantsRequired,
    required this.lockedIn,
    required this.paymentStatus,
    required this.joinedAt,
    required this.respondedAt,
    required this.costShare,
    required this.paidAt,
  });

  final String userId;
  final String displayName;
  final String groupId;
  final LotteryGroupResponseStatus responseStatus;
  final int minimumParticipantsRequired;
  final bool lockedIn;
  final LotteryGroupPaymentStatus paymentStatus;
  final DateTime? joinedAt;
  final DateTime? respondedAt;
  final num? costShare;
  final DateTime? paidAt;

  static DateTime? _asDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }

  factory LotteryGroupMembership.fromFirestore(
    Map<String, dynamic> map,
  ) {
    return LotteryGroupMembership(
      userId: map['userId'] as String? ?? '',
      displayName: map['displayName'] as String? ?? '',
      groupId: map['groupId'] as String? ?? '',
      responseStatus:
          _responseStatusFromString(map['responseStatus'] as String?),
      minimumParticipantsRequired:
          (map['minimumParticipantsRequired'] as num?)?.toInt() ?? 1,
      lockedIn: map['lockedIn'] as bool? ?? false,
      paymentStatus: _paymentStatusFromString(map['paymentStatus'] as String?),
      joinedAt: _asDateTime(map['joinedAt']),
      respondedAt: _asDateTime(map['respondedAt']),
      costShare: map['costShare'] as num?,
      paidAt: _asDateTime(map['paidAt']),
    );
  }

  static LotteryGroupResponseStatus _responseStatusFromString(String? value) {
    switch (value) {
      case 'interested':
        return LotteryGroupResponseStatus.interested;
      case 'not_interested':
        return LotteryGroupResponseStatus.notInterested;
      default:
        return LotteryGroupResponseStatus.undecided;
    }
  }

  static LotteryGroupPaymentStatus _paymentStatusFromString(String? value) {
    switch (value) {
      case 'unpaid':
        return LotteryGroupPaymentStatus.unpaid;
      case 'paid':
        return LotteryGroupPaymentStatus.paid;
      default:
        return LotteryGroupPaymentStatus.notApplicable;
    }
  }

  @override
  List<Object?> get props => [
        userId,
        displayName,
        groupId,
        responseStatus,
        minimumParticipantsRequired,
        lockedIn,
        paymentStatus,
        joinedAt,
        respondedAt,
        costShare,
        paidAt,
      ];
}
