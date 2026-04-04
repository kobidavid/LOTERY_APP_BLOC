import 'dart:math';

import '../models/lottery_form.dart';
import '../models/lottery_table.dart';

class LotteryRandomizerService {
  LotteryRandomizerService({Random? random}) : _random = random ?? Random();

  final Random _random;

  LotteryForm generateFullRandomForm(LotteryForm baseForm) {
    return baseForm.copyWith(
      tables: List<LotteryTable>.generate(
        14,
        (index) => _generateFullTable(index + 1),
      ),
      source: 'lotomat_full',
      isComplete: true,
    );
  }

  LotteryForm completeRemainingTables(LotteryForm baseForm) {
    final List<LotteryTable> completedTables =
        baseForm.tables.map(_completeTablePreservingValues).toList();

    return baseForm.copyWith(
      tables: completedTables,
      source: 'lotomat_partial',
      isComplete: completedTables.every((table) => table.isComplete),
    );
  }

  LotteryTable _generateFullTable(int tableIndex) {
    final List<int> candidates = List<int>.generate(37, (index) => index + 1)
      ..shuffle(_random);
    return LotteryTable(
      tableIndex: tableIndex,
      regularNumbers: candidates.take(6).toList(),
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
      regularNumbers: validExisting,
      strongNumber: table.strongNumber ?? (_random.nextInt(7) + 1),
    );
  }
}
