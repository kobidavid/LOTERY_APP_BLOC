import 'package:equatable/equatable.dart';

import '../../models/lottery_form.dart';

class LotteryFormState extends Equatable {
  const LotteryFormState({
    required this.form,
    required this.activeRowIndex,
    required this.maxUnlockedRowIndex,
    required this.isEditingSavedRecord,
    this.isBusy = false,
    this.errorMessage,
    this.successMessage,
  });

  final LotteryForm form;
  final int activeRowIndex;
  final int maxUnlockedRowIndex;
  final bool isEditingSavedRecord;
  final bool isBusy;
  final String? errorMessage;
  final String? successMessage;

  factory LotteryFormState.initial(String userId) {
    return LotteryFormState(
      form: LotteryForm.empty(userId),
      activeRowIndex: 0,
      maxUnlockedRowIndex: 0,
      isEditingSavedRecord: false,
    );
  }

  LotteryFormState copyWith({
    LotteryForm? form,
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
        activeRowIndex,
        maxUnlockedRowIndex,
        isEditingSavedRecord,
        isBusy,
        errorMessage,
        successMessage,
      ];
}
