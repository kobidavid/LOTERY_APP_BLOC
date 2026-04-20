import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../models/lottery_form.dart';
import '../../models/lottery_group.dart';
import '../../models/lottery_table.dart';
import '../../repositories/lottery_form_repository.dart';
import '../../services/lottery_form_service.dart';
import '../../services/lottery_randomizer_service.dart';
import 'lottery_form_state.dart';

class LotteryFormCubit extends Cubit<LotteryFormState> {
  LotteryFormCubit({
    required LotteryFormRepository formRepository,
    required LotteryFormService formService,
    required LotteryRandomizerService randomizerService,
    required String userId,
  })  : _formRepository = formRepository,
        _formService = formService,
        _randomizerService = randomizerService,
        super(LotteryFormState.initial(userId));

  final LotteryFormRepository _formRepository;
  final LotteryFormService _formService;
  final LotteryRandomizerService _randomizerService;

  void resetForUser(String userId) {
    emit(LotteryFormState.initial(userId));
  }

  void clearMessages() {
    emit(state.copyWith(clearError: true, clearSuccess: true));
  }

  void setSelectedTableCount(int count) {
    final int normalizedCount = count.clamp(1, state.form.tables.length);
    final int clampedActiveIndex = state.activeRowIndex >= normalizedCount
        ? normalizedCount - 1
        : state.activeRowIndex;
    final int preferredUnlockedIndex =
        _preferredUnlockedRowIndexForForm(state.form, normalizedCount);
    final int nextActiveIndex =
        _isRowInteractableForForm(state.form, clampedActiveIndex, normalizedCount)
            ? clampedActiveIndex
            : _fallbackActiveRowIndexForForm(state.form, normalizedCount);

    emit(
      state.copyWith(
        selectedTableCount: normalizedCount,
        activeRowIndex: nextActiveIndex,
        maxUnlockedRowIndex: preferredUnlockedIndex,
        form: state.form.copyWith(
          isComplete: _formService.isFormComplete(
            state.form,
            selectedTableCount: normalizedCount,
          ),
        ),
        clearError: true,
        clearSuccess: true,
      ),
    );
  }

  void selectRow(int rowIndex) {
    if (!state.isRowInteractable(rowIndex)) {
      return;
    }
    emit(state.copyWith(activeRowIndex: rowIndex, clearError: true));
  }

  void handleKeyboardPageChanged(int rowIndex) {
    if (rowIndex == state.activeRowIndex ||
        !state.isRowInteractable(rowIndex)) {
      return;
    }
    emit(state.copyWith(activeRowIndex: rowIndex, clearError: true));
  }

  bool canSwipeForward() {
    return _nextAccessibleRowIndexFromForm(
          state.form,
          state.activeRowIndex,
          state.selectedTableCount,
        ) !=
        null;
  }

  bool canSwipeBackward() {
    return _previousAccessibleRowIndexFromForm(
          state.form,
          state.activeRowIndex,
          state.selectedTableCount,
        ) !=
        null;
  }

  void swipeToNextRow() {
    final int? nextIndex = _nextAccessibleRowIndexFromForm(
      state.form,
      state.activeRowIndex,
      state.selectedTableCount,
    );
    if (nextIndex == null) {
      return;
    }
    selectRow(nextIndex);
  }

  void swipeToPreviousRow() {
    final int? previousIndex = _previousAccessibleRowIndexFromForm(
      state.form,
      state.activeRowIndex,
      state.selectedTableCount,
    );
    if (previousIndex == null) {
      return;
    }
    selectRow(previousIndex);
  }

  bool canSwipeToNextRow() {
    return _nextAccessibleRowIndexFromForm(
          state.form,
          state.activeRowIndex,
          state.selectedTableCount,
        ) !=
        null;
  }

  bool canSwipeToPreviousRow() {
    return _previousAccessibleRowIndexFromForm(
          state.form,
          state.activeRowIndex,
          state.selectedTableCount,
        ) !=
        null;
  }

  void toggleRegularNumber(int number) {
    final LotteryTable table = state.form.tables[state.activeRowIndex];
    final LotteryTable updated =
        _formService.toggleRegularNumber(table, number);
    _updateTable(updated);
  }

  void toggleStrongNumber(int number) {
    final LotteryTable table = state.form.tables[state.activeRowIndex];
    final LotteryTable updated = _formService.toggleStrongNumber(table, number);
    _updateTable(updated, advanceIfCompleted: true);
  }

  void completeRemainingTables() {
    final LotteryForm updated = _randomizerService.completeRemainingTables(
      state.form,
      tableCount: state.selectedTableCount,
    );
    emit(
      state.copyWith(
        form: updated,
        maxUnlockedRowIndex: state.selectedTableCount - 1,
        isEditingSavedRecord: false,
        successMessage: 'שאר הטבלאות הושלמו',
        clearError: true,
      ),
    );
  }

  void generateFullRandomForm() {
    final LotteryForm updated =
        _randomizerService.generateFullRandomForm(
      state.form,
      tableCount: state.selectedTableCount,
    );
    emit(
      state.copyWith(
        form: updated,
        activeRowIndex: 0,
        maxUnlockedRowIndex: state.selectedTableCount - 1,
        isEditingSavedRecord: false,
        successMessage: 'נוצר טופס לוטומט מלא',
        clearError: true,
      ),
    );
  }

  void randomizeSingleTable(int rowIndex) {
    if (!_isRowInteractableForForm(state.form, rowIndex, state.selectedTableCount)) {
      return;
    }

    final LotteryTable randomTable =
        _randomizerService.generateRandomTable(rowIndex + 1);
    _updateTable(
      randomTable,
      advanceIfCompleted: true,
      successMessage: 'טבלה ${rowIndex + 1} מולאה בלוטומט',
    );
  }

  void clearSingleTable(int rowIndex) {
    if (!_isRowInteractableForForm(state.form, rowIndex, state.selectedTableCount)) {
      return;
    }

    _updateTable(
      LotteryTable.empty(rowIndex + 1),
      successMessage: 'טבלה ${rowIndex + 1} נוקתה',
    );
  }

  void clearForm() {
    emit(
      LotteryFormState.initial(state.form.userId).copyWith(
        selectedTableCount: state.selectedTableCount,
        successMessage: 'הטופס נוקה',
      ),
    );
  }

  void loadForm(LotteryForm form) {
    final bool isSavedRecord = form.status == LotteryFormStatus.saved;
    final LotteryForm formForEditing = isSavedRecord
        ? form
        : form.copyWith(
            clearId: true,
            status: LotteryFormStatus.draft,
            clearSubmittedAt: true,
            clearSavedAt: true,
          );
    emit(
      state.copyWith(
        form: formForEditing,
        selectedTableCount: state.selectedTableCount,
        activeRowIndex: 0,
        maxUnlockedRowIndex: state.selectedTableCount > 0
            ? state.selectedTableCount - 1
            : 0,
        isEditingSavedRecord: isSavedRecord,
        successMessage: 'הטופס נטען לעריכה',
        clearError: true,
      ),
    );
  }

  Future<void> saveForm() async {
    if (!_formService.canSave(state.form)) {
      emit(
        state.copyWith(
          errorMessage: 'לא ניתן לשמור טופס ריק',
          clearSuccess: true,
        ),
      );
      return;
    }

    emit(state.copyWith(isBusy: true, clearError: true, clearSuccess: true));

    try {
      final int savedCount = await _formRepository.countSavedForms(
        state.form.userId,
      );

      if (savedCount >= 3) {
        emit(
          state.copyWith(
            isBusy: false,
            errorMessage: 'ניתן לשמור עד 3 טפסים',
          ),
        );
        return;
      }

      final LotteryForm candidate = state.form.copyWith(
        status: LotteryFormStatus.saved,
        isComplete: _formService.isFormComplete(
          state.form,
          selectedTableCount: state.selectedTableCount,
        ),
        savedAt: DateTime.now(),
        clearSubmittedAt: true,
        clearId: true,
      );

      final bool alreadyExists =
          await _formRepository.hasIdenticalSavedForm(candidate);

      if (alreadyExists) {
        emit(
          state.copyWith(
            isBusy: false,
            successMessage: 'טופס זהה כבר שמור במערכת',
          ),
        );
        return;
      }

      final LotteryForm saved = await _formRepository.upsertForm(candidate);
      emit(
        state.copyWith(
          form: saved.copyWith(
            clearId: true,
            status: LotteryFormStatus.draft,
            clearSavedAt: true,
          ),
          isEditingSavedRecord: false,
          isBusy: false,
          successMessage: 'הטופס נשמר בהצלחה',
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          isBusy: false,
          errorMessage: 'שמירת הטופס נכשלה',
        ),
      );
    }
  }

  Future<void> submitForm() async {
    if (!_formService.canSubmit(
      state.form,
      selectedTableCount: state.selectedTableCount,
    )) {
      emit(
        state.copyWith(
          errorMessage: 'ניתן לשלוח רק טופס מלא',
          clearSuccess: true,
        ),
      );
      return;
    }

    emit(state.copyWith(isBusy: true, clearError: true, clearSuccess: true));

    try {
      final LotteryForm submitted = await _formRepository.submitForm(
        state.form.copyWith(
          tables: state.form.tables.take(state.selectedTableCount).toList(),
          status: LotteryFormStatus.submitted,
          isComplete: true,
          clearSavedAt: true,
          clearId: true,
        ),
      );
      emit(
        state.copyWith(
          form: submitted.copyWith(
            clearId: true,
            status: LotteryFormStatus.draft,
            clearSubmittedAt: true,
            clearLotteryId: true,
            clearSalesCloseAt: true,
            clearResultStatus: true,
            clearResultPublishedAt: true,
            clearCheckedAt: true,
            winAmount: 0,
            balanceApplied: false,
          ),
          isEditingSavedRecord: false,
          isBusy: false,
          successMessage: 'הטופס נשלח בהצלחה',
        ),
      );
    } on FirebaseFunctionsException catch (error) {
      final String details = [
        if (error.code.isNotEmpty) error.code,
        if ((error.message ?? '').trim().isNotEmpty) error.message!.trim(),
        if (error.details != null) error.details.toString(),
      ].join(' - ');
      emit(
        state.copyWith(
          isBusy: false,
          errorMessage: details.isEmpty
              ? 'שליחת הטופס נכשלה'
              : 'שליחת הטופס נכשלה: $details',
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          isBusy: false,
          errorMessage: 'שליחת הטופס נכשלה: $error',
        ),
      );
    }
  }

  Future<void> deleteSavedForm(LotteryForm form) async {
    if (form.formId == null) {
      return;
    }

    await _formRepository.deleteSavedForm(
      userId: form.userId,
      formId: form.formId!,
    );

    if (state.form.formId == form.formId) {
      resetForUser(state.form.userId);
    }
  }

  Future<void> cancelSavedForm(LotteryForm form) async {
    if (form.formId == null) {
      return;
    }

    await _formRepository.cancelSavedForm(
      userId: form.userId,
      formId: form.formId!,
    );

    if (state.form.formId == form.formId) {
      resetForUser(state.form.userId);
    }
  }

  Future<LotteryGroup?> createGroup(String groupName) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    final String trimmedName = groupName.trim();
    debugPrint(
      '[CreateGroupFlow] cubit.createGroup validation start +0ms rawName="$groupName"',
    );
    if (trimmedName.isEmpty) {
      debugPrint(
        '[CreateGroupFlow] cubit.createGroup validation failed empty +${stopwatch.elapsedMilliseconds}ms',
      );
      emit(
        state.copyWith(
          errorMessage: 'יש להזין שם לקבוצה',
          clearSuccess: true,
        ),
      );
      return null;
    }

    if (!_formService.canSubmit(
      state.form,
      selectedTableCount: state.selectedTableCount,
    )) {
      debugPrint(
        '[CreateGroupFlow] cubit.createGroup validation failed incomplete +${stopwatch.elapsedMilliseconds}ms',
      );
      emit(
        state.copyWith(
          errorMessage: 'ניתן ליצור קבוצה רק מטופס מלא',
          clearSuccess: true,
        ),
      );
      return null;
    }
    debugPrint(
      '[CreateGroupFlow] cubit.createGroup validation success +${stopwatch.elapsedMilliseconds}ms selectedTableCount=${state.selectedTableCount}',
    );

    emit(state.copyWith(isBusy: true, clearError: true, clearSuccess: true));

    try {
      debugPrint(
        '[CreateGroupFlow] repository.createGroupFromForm start +${stopwatch.elapsedMilliseconds}ms',
      );
      final LotteryGroup group = await _formRepository.createGroupFromForm(
        form: state.form.copyWith(
          tables: state.form.tables.take(state.selectedTableCount).toList(),
          isComplete: true,
        ),
        groupName: trimmedName,
      );
      debugPrint(
        '[CreateGroupFlow] repository.createGroupFromForm end +${stopwatch.elapsedMilliseconds}ms groupId=${group.groupId}',
      );

      emit(
        LotteryFormState.initial(state.form.userId).copyWith(
          isBusy: false,
          successMessage: 'הקבוצה נוצרה והטופס ננעל לעריכה',
        ),
      );

      return group;
    } catch (error) {
      debugPrint(
        '[CreateGroupFlow] cubit.createGroup error +${stopwatch.elapsedMilliseconds}ms error=$error',
      );
      emit(
        state.copyWith(
          isBusy: false,
          errorMessage: 'יצירת הקבוצה נכשלה: $error',
        ),
      );
      return null;
    }
  }

  void _updateTable(
    LotteryTable updatedTable, {
    bool advanceIfCompleted = false,
    String? successMessage,
  }) {
    final LotteryForm updatedForm =
        _formService.updateTable(
      state.form,
      updatedTable,
      selectedTableCount: state.selectedTableCount,
    );

    int activeRowIndex = state.activeRowIndex;
    if (advanceIfCompleted &&
        _isTableCompleteStrict(updatedTable)) {
      final int? nextIndex = _nextRelevantRowIndexAfterCompletion(
        updatedForm,
        activeRowIndex,
        state.selectedTableCount,
      );
      if (nextIndex != null) {
        activeRowIndex = nextIndex;
      }
    }

    if (!_isRowInteractableForForm(
      updatedForm,
      activeRowIndex,
      state.selectedTableCount,
    )) {
      activeRowIndex = _fallbackActiveRowIndexForForm(
        updatedForm,
        state.selectedTableCount,
      );
    }

    emit(
      state.copyWith(
        form: updatedForm,
        activeRowIndex: activeRowIndex,
        maxUnlockedRowIndex: _preferredUnlockedRowIndexForForm(
          updatedForm,
          state.selectedTableCount,
        ),
        isEditingSavedRecord: state.isEditingSavedRecord,
        clearError: true,
        successMessage: successMessage,
        clearSuccess: successMessage == null,
      ),
    );
  }

  bool _isRowInteractableForForm(
    LotteryForm form,
    int rowIndex,
    int selectedTableCount,
  ) {
    if (rowIndex < 0 || rowIndex >= selectedTableCount) {
      return false;
    }
    final int? firstEmptyIndex =
        _firstEmptyRowIndexForForm(form, selectedTableCount);
    final LotteryTable table = form.tables[rowIndex];
    if (!table.isEmpty) {
      return true;
    }
    return firstEmptyIndex == rowIndex;
  }

  int? _firstEmptyRowIndexForForm(LotteryForm form, int selectedTableCount) {
    for (int index = 0; index < selectedTableCount; index += 1) {
      if (form.tables[index].isEmpty) {
        return index;
      }
    }
    return null;
  }

  int? _nextAccessibleRowIndexFromForm(
    LotteryForm form,
    int currentIndex,
    int selectedTableCount,
  ) {
    for (int index = currentIndex + 1; index < selectedTableCount; index += 1) {
      if (_isRowInteractableForForm(form, index, selectedTableCount)) {
        return index;
      }
    }
    return null;
  }

  int? _previousAccessibleRowIndexFromForm(
    LotteryForm form,
    int currentIndex,
    int selectedTableCount,
  ) {
    for (int index = currentIndex - 1; index >= 0; index -= 1) {
      if (_isRowInteractableForForm(form, index, selectedTableCount)) {
        return index;
      }
    }
    return null;
  }

  int _fallbackActiveRowIndexForForm(LotteryForm form, int selectedTableCount) {
    final int? firstEmptyIndex =
        _firstEmptyRowIndexForForm(form, selectedTableCount);
    if (firstEmptyIndex != null) {
      return firstEmptyIndex;
    }
    return selectedTableCount > 0 ? selectedTableCount - 1 : 0;
  }

  int _preferredUnlockedRowIndexForForm(LotteryForm form, int selectedTableCount) {
    final int? firstEmptyIndex =
        _firstEmptyRowIndexForForm(form, selectedTableCount);
    return firstEmptyIndex ?? (selectedTableCount > 0 ? selectedTableCount - 1 : 0);
  }

  int? _firstIncompleteRowIndexForForm(
    LotteryForm form,
    int selectedTableCount,
  ) {
    for (int index = 0; index < selectedTableCount; index += 1) {
      if (!_isTableCompleteStrict(form.tables[index])) {
        return index;
      }
    }
    return null;
  }

  bool _isTableCompleteStrict(LotteryTable table) {
    return _formService.isTableComplete(table) &&
        table.regularNumbers.length == LotteryFormService.regularCount &&
        table.strongNumber != null;
  }

  int? _nextRelevantRowIndexAfterCompletion(
    LotteryForm form,
    int currentIndex,
    int selectedTableCount,
  ) {
    final int? firstIncompleteIndex =
        _firstIncompleteRowIndexForForm(form, selectedTableCount);
    if (firstIncompleteIndex == null) {
      return null;
    }

    if (firstIncompleteIndex != currentIndex &&
        _isRowInteractableForForm(form, firstIncompleteIndex, selectedTableCount)) {
      return firstIncompleteIndex;
    }

    return _nextAccessibleRowIndexFromForm(
      form,
      currentIndex,
      selectedTableCount,
    );
  }
}
