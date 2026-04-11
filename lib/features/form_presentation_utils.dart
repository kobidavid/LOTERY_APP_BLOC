import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? presentationAsDateTime(dynamic value) {
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DateTime) {
    return value;
  }
  return null;
}

String formatPresentationDateTime(DateTime? date) {
  if (date == null) {
    return 'ללא תאריך';
  }

  String twoDigits(int value) => value.toString().padLeft(2, '0');

  return '${twoDigits(date.day)}/${twoDigits(date.month)}/${date.year} '
      '${twoDigits(date.hour)}:${twoDigits(date.minute)}';
}

num? extractMyWinningShare({
  required dynamic winAllocations,
  required String userId,
}) {
  if (winAllocations == null) {
    return null;
  }

  if (winAllocations is Map) {
    final dynamic directValue = winAllocations[userId];
    final num? directAmount = _extractNumericAmount(directValue);
    if (directAmount != null) {
      return directAmount;
    }

    for (final MapEntry<dynamic, dynamic> entry in winAllocations.entries) {
      final dynamic value = entry.value;
      if (value is Map && value['userId'] == userId) {
        final num? nestedAmount = _extractNumericAmount(value);
        if (nestedAmount != null) {
          return nestedAmount;
        }
      }
    }
  }

  if (winAllocations is Iterable) {
    for (final dynamic entry in winAllocations) {
      if (entry is Map && entry['userId'] == userId) {
        final num? amount = _extractNumericAmount(entry);
        if (amount != null) {
          return amount;
        }
      }
    }
  }

  return null;
}

String? extractReceiptUrl(Map<String, dynamic> data) {
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

num? _extractNumericAmount(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value;
  }
  if (value is String) {
    return num.tryParse(value);
  }
  if (value is Map) {
    final List<dynamic> candidates = <dynamic>[
      value['amount'],
      value['winAmount'],
      value['myShare'],
      value['share'],
      value['allocatedAmount'],
      value['value'],
    ];
    for (final dynamic candidate in candidates) {
      final num? parsed = _extractNumericAmount(candidate);
      if (parsed != null) {
        return parsed;
      }
    }
  }
  return null;
}
