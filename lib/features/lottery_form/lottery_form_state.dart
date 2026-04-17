import 'package:equatable/equatable.dart';

import '../../models/lottery_form.dart';
import '../../models/lottery_table.dart';

class LotteryFormState extends Equatable {
  const LotteryFormState({
    required this.form,
    required this.selectedTableCount,
    required this.activeRowIndex,
    required this.maxUnlockedRowIndex,
    required this.isEditingSavedRecord,
    this.isBusy = false,
    this.errorMessage,
    this.successMessage,
  });

  final LotteryForm form;
  final int selectedTableCount;
  final int activeRowIndex;
  final int maxUnlockedRowIndex;
  final bool isEditingSavedRecord;
  final bool isBusy;
  final String? errorMessage;
  final String? successMessage;

  factory LotteryFormState.initial(String userId) {
    return LotteryFormState(
      form: LotteryForm.empty(userId),
      selectedTableCount: 14,
      activeRowIndex: 0,
      maxUnlockedRowIndex: 0,
      isEditingSavedRecord: false,
    );
  }

  LotteryFormState copyWith({
    LotteryForm? form,
    int? selectedTableCount,
    int? activeRowIndex,
    int? maxUnlockedRowIndex,
    bool? isEditingSavedRecord,
    bool? isBusy,
    String? errorMessage,
    String? successMessage,
    bool clearError = false,
    bool clearSuccess = false,
  }) {
    return LotteryFormState(
      form: form ?? this.form,
      selectedTableCount: selectedTableCount ?? this.selectedTableCount,
      activeRowIndex: activeRowIndex ?? this.activeRowIndex,
      maxUnlockedRowIndex: maxUnlockedRowIndex ?? this.maxUnlockedRowIndex,
      isEditingSavedRecord: isEditingSavedRecord ?? this.isEditingSavedRecord,
      isBusy: isBusy ?? this.isBusy,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      successMessage:
          clearSuccess ? null : (successMessage ?? this.successMessage),
    );
  }

  @override
  List<Object?> get props => [
        form,
        selectedTableCount,
        activeRowIndex,
        maxUnlockedRowIndex,
        isEditingSavedRecord,
        isBusy,
        errorMessage,
        successMessage,
      ];

  List<LotteryTable> get visibleTables =>
      form.tables.take(selectedTableCount).toList(growable: false);

  int? get firstEmptyRowIndex {
    for (int index = 0; index < visibleTables.length; index += 1) {
      if (visibleTables[index].isEmpty) {
        return index;
      }
    }
    return null;
  }

  int? get firstGapRowIndex {
    int? firstEmpty;
    for (int index = 0; index < visibleTables.length; index += 1) {
      final LotteryTable table = visibleTables[index];
      if (table.isEmpty) {
        firstEmpty ??= index;
        continue;
      }
      if (firstEmpty != null) {
        return firstEmpty;
      }
    }
    return null;
  }

  bool get hasGap => firstGapRowIndex != null;

  bool isRowInteractable(int rowIndex) {
    if (rowIndex < 0 || rowIndex >= selectedTableCount) {
      return false;
    }
    final LotteryTable table = form.tables[rowIndex];
    if (!table.isEmpty) {
      return true;
    }
    return firstEmptyRowIndex == rowIndex;
  }
}
