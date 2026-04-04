import '../models/lottery_form.dart';
import '../models/lottery_table.dart';

class LotteryFormService {
  static const int tableCount = 14;
  static const int regularCount = 6;

  const LotteryFormService();

  bool isTableComplete(LotteryTable table) => table.isComplete;

  bool isFormEmpty(LotteryForm form) =>
      form.tables.every((table) => table.isEmpty);

  bool isFormComplete(LotteryForm form) =>
      form.tables.length == tableCount && form.tables.every(isTableComplete);

  bool canSave(LotteryForm form) => !isFormEmpty(form);

  bool canSubmit(LotteryForm form) => isFormComplete(form);

  LotteryTable toggleRegularNumber(LotteryTable table, int number) {
    final List<int> regulars = List<int>.from(table.regularNumbers);

    if (regulars.contains(number)) {
      regulars.remove(number);
      return table.copyWith(regularNumbers: regulars);
    }

    if (regulars.length >= regularCount) {
      return table;
    }

    regulars.add(number);
    return table.copyWith(regularNumbers: regulars);
  }

  LotteryTable toggleStrongNumber(LotteryTable table, int number) {
    if (table.regularNumbers.length != regularCount) {
      return table;
    }

    if (table.strongNumber == number) {
      return table.copyWith(clearStrongNumber: true);
    }

    return table.copyWith(strongNumber: number);
  }

  LotteryForm updateTable(LotteryForm form, LotteryTable updatedTable) {
    final List<LotteryTable> updatedTables = form.tables
        .map(
          (table) => table.tableIndex == updatedTable.tableIndex
              ? updatedTable
              : table,
        )
        .toList();

    return form.copyWith(
      tables: updatedTables,
      isComplete: isFormComplete(form.copyWith(tables: updatedTables)),
    );
  }
}
