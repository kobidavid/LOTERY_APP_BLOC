import 'package:equatable/equatable.dart';

class ReceiptParsedTable extends Equatable {
  const ReceiptParsedTable({
    required this.tableIndex,
    required this.regularNumbers,
    required this.strongNumber,
  });

  final int tableIndex;
  final List<int> regularNumbers;
  final int? strongNumber;

  factory ReceiptParsedTable.fromMap(Map<String, dynamic> map) {
    final List<dynamic> rawRegularNumbers =
        map['regularNumbers'] as List<dynamic>? ?? const <dynamic>[];
    return ReceiptParsedTable(
      tableIndex: (map['tableIndex'] as num?)?.toInt() ?? 1,
      regularNumbers: _normalizeRegularNumbers(
        rawRegularNumbers
            .whereType<num>()
            .map((value) => value.toInt())
            .where((value) => value >= 1 && value <= 37)
            .toList(),
      ),
      strongNumber:
          _normalizeStrongNumber((map['strongNumber'] as num?)?.toInt()),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'tableIndex': tableIndex,
      'regularNumbers': regularNumbers,
      'strongNumber': strongNumber,
    };
  }

  bool get isComplete {
    final Set<int> uniqueRegulars = regularNumbers.toSet();
    return regularNumbers.length == 6 &&
        uniqueRegulars.length == 6 &&
        regularNumbers.every((value) => value >= 1 && value <= 37) &&
        strongNumber != null &&
        strongNumber! >= 1 &&
        strongNumber! <= 7;
  }

  String get canonicalRow {
    final String regulars =
        regularNumbers.map((value) => value.toString().padLeft(2, '0')).join();
    final String strong = strongNumber?.toString() ?? 'x';
    return '$regulars-$strong';
  }

  static List<int> _normalizeRegularNumbers(List<int> values) {
    final List<int> normalized = List<int>.from(values)..sort();
    return List<int>.unmodifiable(normalized);
  }

  static int? _normalizeStrongNumber(int? value) {
    if (value == null || value < 1 || value > 7) {
      return null;
    }
    return value;
  }

  @override
  List<Object?> get props =>
      <Object?>[tableIndex, regularNumbers, strongNumber];
}
