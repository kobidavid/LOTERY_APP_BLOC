import 'package:equatable/equatable.dart';

class LotteryTable extends Equatable {
  const LotteryTable({
    required this.tableIndex,
    required this.regularNumbers,
    required this.strongNumber,
  });

  final int tableIndex;
  final List<int> regularNumbers;
  final int? strongNumber;

  factory LotteryTable.empty(int tableIndex) {
    return LotteryTable(
      tableIndex: tableIndex,
      regularNumbers: const <int>[],
      strongNumber: null,
    );
  }

  factory LotteryTable.fromMap(Map<String, dynamic> map) {
    final List<dynamic> rawRegulars =
        (map['regularNumbers'] as List<dynamic>? ?? const <dynamic>[]);

    return LotteryTable(
      tableIndex: (map['tableIndex'] as num?)?.toInt() ?? 1,
      regularNumbers: _normalizeRegularNumbers(
        rawRegulars
            .map((value) => (value as num).toInt())
            .where((value) => value >= 1 && value <= 37)
            .toList(),
      ),
      strongNumber: (map['strongNumber'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'tableIndex': tableIndex,
      'regularNumbers': regularNumbers,
      'strongNumber': strongNumber,
      'isComplete': isComplete,
    };
  }

  LotteryTable copyWith({
    int? tableIndex,
    List<int>? regularNumbers,
    int? strongNumber,
    bool clearStrongNumber = false,
  }) {
    return LotteryTable(
      tableIndex: tableIndex ?? this.tableIndex,
      regularNumbers: regularNumbers == null
          ? this.regularNumbers
          : _normalizeRegularNumbers(regularNumbers),
      strongNumber:
          clearStrongNumber ? null : (strongNumber ?? this.strongNumber),
    );
  }

  static List<int> normalizeRegularNumbers(List<int> regularNumbers) {
    return _normalizeRegularNumbers(regularNumbers);
  }

  static List<int> _normalizeRegularNumbers(List<int> regularNumbers) {
    final List<int> normalized = List<int>.from(regularNumbers)..sort();
    return List<int>.unmodifiable(normalized);
  }

  bool get isComplete {
    final Set<int> unique = regularNumbers.toSet();
    return regularNumbers.length == 6 &&
        unique.length == 6 &&
        regularNumbers.every((value) => value >= 1 && value <= 37) &&
        strongNumber != null &&
        strongNumber! >= 1 &&
        strongNumber! <= 7;
  }

  bool get isEmpty => regularNumbers.isEmpty && strongNumber == null;

  @override
  List<Object?> get props => [tableIndex, regularNumbers, strongNumber];
}
