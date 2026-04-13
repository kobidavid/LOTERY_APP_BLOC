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

  void selectRow(int rowIndex) {
    if (rowIndex > state.maxUnlockedRowIndex) {
      return;
    }
    emit(state.copyWith(activeRowIndex: rowIndex, clearError: true));
  }

  void handleKeyboardPageChanged(int rowIndex) {
    if (rowIndex == state.activeRowIndex ||
        rowIndex > state.maxUnlockedRowIndex) {
      return;
    }
    emit(state.copyWith(activeRowIndex: rowIndex, clearError: true));
  }

  bool canSwipeForward() {
    if (state.activeRowIndex >= state.maxUnlockedRowIndex) {
      return false;
    }

    final LotteryTable activeTable = state.form.tables[state.activeRowIndex];
    return activeTable.isComplete;
  }

  bool canSwipeBackward() {
    return state.activeRowIndex > 0;
  }

  void swipeToNextRow() {
    if (!canSwipeForward()) {
      return;
    }
    selectRow(state.activeRowIndex + 1);
  }

  void swipeToPreviousRow() {
    if (!canSwipeBackward()) {
      return;
    }
    selectRow(state.activeRowIndex - 1);
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
    );
    emit(
      state.copyWith(
        form: updated,
        maxUnlockedRowIndex: 13,
        isEditingSavedRecord: false,
        successMessage: 'שאר הטבלאות הושלמו',
        clearError: true,
      ),
    );
  }

  void generateFullRandomForm() {
    final LotteryForm updated =
        _randomizerService.generateFullRandomForm(state.form);
    emit(
      state.copyWith(
        form: updated,
        activeRowIndex: 0,
        maxUnlockedRowIndex: 13,
        isEditingSavedRecord: false,
        successMessage: 'נוצר טופס לוטומט מלא',
        clearError: true,
      ),
    );
  }

  void clearForm() {
    emit(
      LotteryFormState.initial(state.form.userId).copyWith(
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
        activeRowIndex: 0,
        maxUnlockedRowIndex: 13,
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
        isComplete: _formService.isFormComplete(state.form),
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
    if (!_formService.canSubmit(state.form)) {
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
    final String trimmedName = groupName.trim();
    if (trimmedName.isEmpty) {
      emit(
        state.copyWith(
          errorMessage: 'יש להזין שם לקבוצה',
          clearSuccess: true,
        ),
      );
      return null;
    }

    if (!_formService.canSubmit(state.form)) {
      emit(
        state.copyWith(
          errorMessage: 'ניתן ליצור קבוצה רק מטופס מלא',
          clearSuccess: true,
        ),
      );
      return null;
    }

    emit(state.copyWith(isBusy: true, clearError: true, clearSuccess: true));

    try {
      final LotteryGroup group = await _formRepository.createGroupFromForm(
        form: state.form.copyWith(
          isComplete: true,
        ),
        groupName: trimmedName,
      );

      emit(
        LotteryFormState.initial(state.form.userId).copyWith(
          isBusy: false,
          successMessage: 'הקבוצה נוצרה והטופס ננעל לעריכה',
        ),
      );

      return group;
    } catch (error) {
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
  }) {
    final LotteryForm updatedForm =
        _formService.updateTable(state.form, updatedTable);

    int maxUnlockedRowIndex = state.maxUnlockedRowIndex;
    if (updatedTable.isComplete && updatedTable.tableIndex < 14) {
      maxUnlockedRowIndex = maxUnlockedRowIndex < updatedTable.tableIndex
          ? updatedTable.tableIndex
          : maxUnlockedRowIndex;
    }

    int activeRowIndex = state.activeRowIndex;
    if (advanceIfCompleted &&
        updatedTable.isComplete &&
        activeRowIndex < 13 &&
        activeRowIndex + 1 <= maxUnlockedRowIndex) {
      activeRowIndex += 1;
    }

    emit(
      state.copyWith(
        form: updatedForm,
        activeRowIndex: activeRowIndex,
        maxUnlockedRowIndex: maxUnlockedRowIndex,
        isEditingSavedRecord: state.isEditingSavedRecord,
        clearError: true,
        clearSuccess: true,
      ),
    );
  }
}
