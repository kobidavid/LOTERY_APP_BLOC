import 'dart:math';

import '../models/lottery_form.dart';
import '../models/lottery_table.dart';

class LotteryRandomizerService {
  LotteryRandomizerService({Random? random}) : _random = random ?? Random();

  final Random _random;

  LotteryForm generateFullRandomForm(
    LotteryForm baseForm, {
    required int tableCount,
  }) {
    final int normalizedCount = tableCount.clamp(1, baseForm.tables.length);
    return baseForm.copyWith(
      tables: List<LotteryTable>.generate(
        baseForm.tables.length,
        (index) => index < normalizedCount
            ? _generateFullTable(index + 1)
            : LotteryTable.empty(index + 1),
      ),
      source: 'lotomat_full',
      isComplete: true,
    );
  }

  LotteryForm completeRemainingTables(
    LotteryForm baseForm, {
    required int tableCount,
  }) {
    final int normalizedCount = tableCount.clamp(1, baseForm.tables.length);
    final List<LotteryTable> completedTables = List<LotteryTable>.generate(
      baseForm.tables.length,
      (index) => index < normalizedCount
          ? _completeTablePreservingValues(baseForm.tables[index])
          : LotteryTable.empty(index + 1),
    );

    return baseForm.copyWith(
      tables: completedTables,
      source: 'lotomat_partial',
      isComplete: completedTables.take(normalizedCount).every(
            (table) => table.isComplete,
          ),
    );
  }

  LotteryTable _generateFullTable(int tableIndex) {
    final List<int> candidates = List<int>.generate(37, (index) => index + 1)
      ..shuffle(_random);
    return LotteryTable(
      tableIndex: tableIndex,
      regularNumbers:
          LotteryTable.normalizeRegularNumbers(candidates.take(6).toList()),
      strongNumber: _random.nextInt(7) + 1,
    );
  }

  LotteryTable _completeTablePreservingValues(LotteryTable table) {
    final List<int> validExisting = table.regularNumbers
        .where((value) => value >= 1 && value <= 37)
        .toSet()
        .toList();

    final List<int> remainingPool = List<int>.generate(37, (index) => index + 1)
      ..removeWhere(validExisting.contains)
      ..shuffle(_random);

    while (validExisting.length < 6) {
      validExisting.add(remainingPool.removeAt(0));
    }

    return LotteryTable(
      tableIndex: table.tableIndex,
      regularNumbers: LotteryTable.normalizeRegularNumbers(validExisting),
      strongNumber: table.strongNumber ?? (_random.nextInt(7) + 1),
    );
  }
}
