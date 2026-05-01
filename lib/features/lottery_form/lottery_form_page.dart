import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/lottery_form.dart';
import '../../models/lottery_group.dart';
import '../../repositories/lottery_form_repository.dart';
import '../../repositories/lottery_group_repository.dart';
import '../../services/group_invite_link_service.dart';
import '../../models/lottery_table.dart';
import '../payments/payment_options_page.dart';
import 'group_details_page.dart';
import 'lottery_form_cubit.dart';
import 'lottery_form_state.dart';

enum _LottomatAction {
  completeRemaining,
  fullRandom,
}

class LotteryFormPage extends StatefulWidget {
  const LotteryFormPage({
    super.key,
    required this.inviteLinkService,
    required this.onOpenMyForms,
    this.personalDraftLoadRequest,
    this.personalDraftLoadVersion = 0,
  });

  static const double rowLabelWidth = 98;
  final GroupInviteLinkService inviteLinkService;
  final VoidCallback onOpenMyForms;
  final PersonalDraftLoadRequest? personalDraftLoadRequest;
  final int personalDraftLoadVersion;

  @override
  State<LotteryFormPage> createState() => _LotteryFormPageState();
}

class PersonalDraftLoadRequest {
  const PersonalDraftLoadRequest({
    required this.entries,
  });

  final List<PersonalSavedDraftEntry> entries;
}

class _FormPageLayoutMetrics {
  const _FormPageLayoutMetrics({
    required this.compactness,
    required this.topPadding,
    required this.topBottomPadding,
    required this.sectionGap,
    required this.listGap,
    required this.keyboardTopGap,
    required this.fieldShellHeight,
    required this.toggleHeight,
    required this.primaryButtonHeight,
    required this.secondaryButtonHeight,
    required this.actionHorizontalPadding,
    required this.actionLabelSpacing,
  });

  factory _FormPageLayoutMetrics.fromAvailableHeight(double availableHeight) {
    final double compactness =
        ((780.0 - availableHeight) / 260.0).clamp(0.0, 1.0);
    return _FormPageLayoutMetrics(
      compactness: compactness,
      topPadding: lerpDouble(8.0, 4.0, compactness) ?? 6.0,
      topBottomPadding: lerpDouble(6.0, 2.0, compactness) ?? 4.0,
      sectionGap: lerpDouble(6.0, 2.0, compactness) ?? 4.0,
      listGap: lerpDouble(6.0, 2.0, compactness) ?? 4.0,
      keyboardTopGap: lerpDouble(6.0, 1.0, compactness) ?? 3.0,
      fieldShellHeight: lerpDouble(42.0, 34.0, compactness) ?? 38.0,
      toggleHeight: lerpDouble(31.0, 25.0, compactness) ?? 28.0,
      primaryButtonHeight: lerpDouble(48.0, 40.0, compactness) ?? 44.0,
      secondaryButtonHeight: lerpDouble(42.0, 34.0, compactness) ?? 38.0,
      actionHorizontalPadding: lerpDouble(8.0, 6.0, compactness) ?? 7.0,
      actionLabelSpacing: lerpDouble(5.0, 2.0, compactness) ?? 3.5,
    );
  }

  final double compactness;
  final double topPadding;
  final double topBottomPadding;
  final double sectionGap;
  final double listGap;
  final double keyboardTopGap;
  final double fieldShellHeight;
  final double toggleHeight;
  final double primaryButtonHeight;
  final double secondaryButtonHeight;
  final double actionHorizontalPadding;
  final double actionLabelSpacing;
}

class _LotteryFormPageState extends State<LotteryFormPage> {
  late final LotteryGroupRepository _groupRepository;
  late final LotteryFormRepository _paymentRepository;
  final ScrollController _tablesScrollController = ScrollController();
  final GlobalKey _tablesListKey = GlobalKey();
  final Map<int, GlobalKey> _tableRowKeys = <int, GlobalKey>{};
  bool _isGroupMode = false;
  bool _isDoubleMode = false;
  final List<_LocalDraftForm> _localDrafts = <_LocalDraftForm>[];
  int _activeDraftIndex = 0;
  int _nextDraftNumber = 2;
  int? _lastAutoScrolledActiveRowIndex;
  int? _lastAutoScrolledSelectedTableCount;
  Timer? _personalDraftPersistDebounce;
  bool _isPersonalPaymentFlowInProgress = false;

  @override
  void didUpdateWidget(covariant LotteryFormPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.personalDraftLoadVersion != oldWidget.personalDraftLoadVersion &&
        widget.personalDraftLoadRequest != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(_loadPersonalDraftRequest(widget.personalDraftLoadRequest!));
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _groupRepository = LotteryGroupRepository();
    _paymentRepository = LotteryFormRepository();
  }

  @override
  void dispose() {
    _personalDraftPersistDebounce?.cancel();
    _tablesScrollController.dispose();
    super.dispose();
  }

  void _ensureInitialDraftRegistered(LotteryFormState state) {
    if (_localDrafts.isNotEmpty) {
      return;
    }
    _localDrafts.add(
      _LocalDraftForm(
        number: 1,
        formState: state.copyWith(clearError: true, clearSuccess: true),
        isGroupMode: _isGroupMode,
        isDoubleMode: _isDoubleMode,
      ),
    );
  }

  void _syncActiveDraftSnapshot(LotteryFormState state) {
    _ensureInitialDraftRegistered(state);
    final bool keepPersistedIds = state.isEditingSavedRecord;
    _localDrafts[_activeDraftIndex] = _localDrafts[_activeDraftIndex].copyWith(
      formState: state.copyWith(clearError: true, clearSuccess: true),
      isGroupMode: _isGroupMode,
      isDoubleMode: _isDoubleMode,
      clearPersistedDraftFormId: !keepPersistedIds,
      clearPersistedDraftBundleId: !keepPersistedIds,
    );
  }

  bool _isPersonalMultiDraftFlow(LotteryFormState state) {
    final List<_LocalDraftForm> drafts = _effectiveLocalDrafts(state);
    return drafts.length > 1 && drafts.every((draft) => !draft.isGroupMode);
  }

  bool _shouldPersistPersonalDrafts(LotteryFormState state) {
    if (_isPersonalMultiDraftFlow(state)) {
      final String reason = _isPersonalPaymentFlowInProgress
          ? 'payment_flow_started'
          : 'personal_multi_local_only';
      debugPrint(
        '[DraftsDebug] autoPersist skipped reason=$reason activeDraft=$_activeDraftIndex drafts=${_effectiveLocalDrafts(state).length}',
      );
      return false;
    }
    return false;
  }

  bool _canPersistDraft(_LocalDraftForm draft) {
    return draft.formState.form.tables.any((table) => !table.isEmpty);
  }

  Future<void> _persistLocalDraftAtIndex(int index) async {
    if (!mounted || index < 0 || index >= _localDrafts.length) {
      return;
    }
    if (_isPersonalPaymentFlowInProgress) {
      debugPrint(
        '[DraftsDebug] autoPersist skipped reason=payment_flow_started index=$index',
      );
      return;
    }
    final _LocalDraftForm draft = _localDrafts[index];
    if (draft.isGroupMode || !_canPersistDraft(draft)) {
      return;
    }

    final LotteryForm candidate = draft.formState.form.copyWith(
      status: LotteryFormStatus.saved,
      mode: LotteryFormMode.personal,
      isComplete: _isDraftComplete(draft),
      savedAt: DateTime.now(),
      clearSubmittedAt: true,
      clearGroupId: true,
      isEditable: true,
    );
    debugPrint(
      '[DraftsDebug] persistLocalDraft start path=users/${candidate.userId}/forms/${candidate.formId ?? '(new)'} localDraft=${draft.number} status=${candidate.status.value} mode=${candidate.mode.value} submissionType=personal userId=${candidate.userId} isComplete=${candidate.isComplete}',
    );
    final LotteryForm saved = await _paymentRepository.upsertForm(candidate);
    debugPrint(
      '[DraftsDebug] persistLocalDraft success path=users/${saved.userId}/forms/${saved.formId ?? 'null'} formId=${saved.formId ?? 'null'} status=${saved.status.value} mode=${saved.mode.value} submissionType=personal userId=${saved.userId} isComplete=${saved.isComplete} createdAt=${saved.createdAt?.toIso8601String() ?? 'null'} updatedAt=${saved.updatedAt?.toIso8601String() ?? 'null'}',
    );
    if (!mounted || index >= _localDrafts.length) {
      return;
    }

    final LotteryForm localEditingForm = saved.copyWith(
      status: LotteryFormStatus.draft,
      clearSavedAt: true,
      clearSubmittedAt: true,
      isEditable: true,
    );
    setState(() {
      _localDrafts[index] = _localDrafts[index].copyWith(
        formState: _localDrafts[index].formState.copyWith(
              form: localEditingForm,
              clearError: true,
              clearSuccess: true,
            ),
      );
    });
  }

  Future<void> _deletePersistedDraftIfNeeded(_LocalDraftForm draft) async {
    final String? formId = draft.formState.form.formId;
    if (formId == null || formId.isEmpty) {
      return;
    }
    await _paymentRepository.deletePersonalDraft(
      userId: draft.formState.form.userId,
      formId: formId,
    );
  }

  void _schedulePersistActivePersonalDraft(LotteryFormState state) {
    _personalDraftPersistDebounce?.cancel();
    if (!_shouldPersistPersonalDrafts(state)) {
      return;
    }
    _personalDraftPersistDebounce = Timer(
      const Duration(milliseconds: 450),
      () => unawaited(_persistLocalDraftAtIndex(_activeDraftIndex)),
    );
  }

  Future<void> _persistAllPersonalDrafts(LotteryFormState state) async {
    _syncActiveDraftSnapshot(state);
    if (!_shouldPersistPersonalDrafts(state)) {
      return;
    }
    for (int index = 0; index < _localDrafts.length; index += 1) {
      await _persistLocalDraftAtIndex(index);
    }
  }

  void _showDraftMixingMessage() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('לא ניתן לשלב טפסים אישיים וקבוצתיים באותה שליחה'),
        ),
      );
  }

  bool _canChangeDraftGroupMode({
    required bool nextIsGroupMode,
    required LotteryFormState state,
  }) {
    final List<_LocalDraftForm> drafts = _effectiveLocalDrafts(state);
    if (drafts.length <= 1) {
      return true;
    }
    return drafts
        .asMap()
        .entries
        .where((entry) => entry.key != _activeDraftIndex)
        .every((entry) => entry.value.isGroupMode == nextIsGroupMode);
  }

  void _handleDraftModeChanged(bool nextIsGroupMode) {
    final LotteryFormState state = context.read<LotteryFormCubit>().state;
    if (!_canChangeDraftGroupMode(
      nextIsGroupMode: nextIsGroupMode,
      state: state,
    )) {
      _showDraftMixingMessage();
      return;
    }

    setState(() {
      _isGroupMode = nextIsGroupMode;
      _syncActiveDraftSnapshot(state);
    });
  }

  Future<void> _createAdditionalLocalDraft() async {
    final LotteryFormCubit cubit = context.read<LotteryFormCubit>();
    final LotteryFormState currentState = cubit.state;
    _syncActiveDraftSnapshot(currentState);
    if (!_isGroupMode && _shouldPersistPersonalDrafts(currentState)) {
      await _persistLocalDraftAtIndex(_activeDraftIndex);
    }
    final bool targetGroupMode =
        _effectiveLocalDrafts(currentState).first.isGroupMode;
    final LotteryFormState draftState = LotteryFormState.initial(
      currentState.form.userId,
    ).copyWith(
      form: LotteryFormState.initial(currentState.form.userId).form.copyWith(
            mode: targetGroupMode
                ? LotteryFormMode.group
                : LotteryFormMode.personal,
          ),
    );
    final _LocalDraftForm draft = _LocalDraftForm(
      number: _nextDraftNumber,
      formState: draftState,
      isGroupMode: targetGroupMode,
      isDoubleMode: false,
    );
    setState(() {
      _localDrafts.add(draft);
      _activeDraftIndex = _localDrafts.length - 1;
      _nextDraftNumber += 1;
      _isGroupMode = draft.isGroupMode;
      _isDoubleMode = draft.isDoubleMode;
    });
    cubit.loadLocalDraftState(draft.formState);
    if (_shouldPersistPersonalDrafts(cubit.state)) {
      await _persistAllPersonalDrafts(cubit.state);
    }
  }

  Future<void> _switchToLocalDraft(int index) async {
    final LotteryFormCubit cubit = context.read<LotteryFormCubit>();
    final LotteryFormState currentState = cubit.state;
    _syncActiveDraftSnapshot(currentState);
    if (_shouldPersistPersonalDrafts(currentState)) {
      await _persistLocalDraftAtIndex(_activeDraftIndex);
    }
    final _LocalDraftForm draft = _localDrafts[index];
    setState(() {
      _activeDraftIndex = index;
      _isGroupMode = draft.isGroupMode;
      _isDoubleMode = draft.isDoubleMode;
    });
    cubit.loadLocalDraftState(draft.formState);
    if (_shouldPersistPersonalDrafts(cubit.state)) {
      await _persistAllPersonalDrafts(cubit.state);
    }
  }

  Future<bool> _deleteLocalDraft(int index) async {
    final _LocalDraftForm draft = _localDrafts[index];
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('מחיקת טופס'),
            content: Text('האם למחוק את טופס ${draft.number}?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('ביטול'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('מחיקה'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) {
      return false;
    }

    final LotteryFormCubit cubit = context.read<LotteryFormCubit>();
    _syncActiveDraftSnapshot(cubit.state);
    if (_localDrafts.length <= 1) {
      await _deletePersistedDraftIfNeeded(draft);
      final LotteryFormState initialState =
          LotteryFormState.initial(draft.formState.form.userId);
      setState(() {
        _localDrafts
          ..clear()
          ..add(
            _LocalDraftForm(
              number: 1,
              formState: initialState,
              isGroupMode: false,
              isDoubleMode: false,
            ),
          );
        _activeDraftIndex = 0;
        _nextDraftNumber = 2;
        _isGroupMode = false;
        _isDoubleMode = false;
      });
      cubit.loadLocalDraftState(initialState);
      return true;
    }
    await _deletePersistedDraftIfNeeded(draft);
    final List<_LocalDraftForm> updatedDrafts =
        List<_LocalDraftForm>.from(_localDrafts)..removeAt(index);
    final List<_LocalDraftForm> renumberedDrafts =
        List<_LocalDraftForm>.generate(
      updatedDrafts.length,
      (draftIndex) =>
          updatedDrafts[draftIndex].copyWith(number: draftIndex + 1),
    );

    final bool deletedActiveDraft = index == _activeDraftIndex;
    int nextActiveDraftIndex = _activeDraftIndex;
    if (_activeDraftIndex > index) {
      nextActiveDraftIndex -= 1;
    } else if (deletedActiveDraft) {
      nextActiveDraftIndex = math.min(index, renumberedDrafts.length - 1);
    }

    final _LocalDraftForm nextActiveDraft =
        renumberedDrafts[nextActiveDraftIndex];
    setState(() {
      _localDrafts
        ..clear()
        ..addAll(renumberedDrafts);
      _activeDraftIndex = nextActiveDraftIndex;
      _nextDraftNumber = renumberedDrafts.length + 1;
      _isGroupMode = nextActiveDraft.isGroupMode;
      _isDoubleMode = nextActiveDraft.isDoubleMode;
    });

    if (deletedActiveDraft) {
      cubit.loadLocalDraftState(nextActiveDraft.formState);
    }
    return true;
  }

  List<_LocalDraftForm> _effectiveLocalDrafts(LotteryFormState state) {
    _ensureInitialDraftRegistered(state);
    return List<_LocalDraftForm>.generate(_localDrafts.length, (index) {
      if (index != _activeDraftIndex) {
        return _localDrafts[index];
      }
      final bool keepPersistedIds = state.isEditingSavedRecord;
      return _localDrafts[index].copyWith(
        formState: state.copyWith(clearError: true, clearSuccess: true),
        isGroupMode: _isGroupMode,
        isDoubleMode: _isDoubleMode,
        clearPersistedDraftFormId: !keepPersistedIds,
        clearPersistedDraftBundleId: !keepPersistedIds,
      );
    });
  }

  bool _isDraftComplete(_LocalDraftForm draft) {
    return _areSelectedTablesComplete(
      draft.formState.visibleTables,
      draft.formState.selectedTableCount,
    );
  }

  num _calculateDraftCost(_LocalDraftForm draft) {
    final List<LotteryTable> selectedTables = draft.formState.form.tables
        .take(draft.formState.selectedTableCount)
        .toList();
    return _paymentRepository.calculateTicketCost(selectedTables);
  }

  num _calculateDraftsTotalCost(List<_LocalDraftForm> drafts) {
    return drafts.fold<num>(
      0,
      (num total, _LocalDraftForm draft) => total + _calculateDraftCost(draft),
    );
  }

  List<PersonalSubmissionDraftPayload> _buildPersonalSubmissionDraftPayloads(
    List<_LocalDraftForm> drafts,
  ) {
    return List<PersonalSubmissionDraftPayload>.generate(drafts.length,
        (index) {
      final _LocalDraftForm draft = drafts[index];
      final int selectedTableCount = draft.formState.selectedTableCount;
      final List<LotteryTable> selectedTables =
          draft.formState.form.tables.take(selectedTableCount).toList();
      final LotteryForm submittedForm = draft.formState.form.copyWith(
        clearId: true,
        tables: selectedTables,
        status: LotteryFormStatus.submitted,
        mode: LotteryFormMode.personal,
        isComplete: true,
        clearSavedAt: true,
        clearGroupId: true,
        isEditable: false,
      );
      return PersonalSubmissionDraftPayload(
        form: submittedForm,
        cost: _calculateDraftCost(draft),
        tableCount: selectedTableCount,
        isDoubleMode: draft.isDoubleMode,
        displayOrder: index + 1,
      );
    });
  }

  List<GroupDraftPayload> _buildGroupDraftPayloads(
    List<_LocalDraftForm> drafts,
  ) {
    return List<GroupDraftPayload>.generate(drafts.length, (index) {
      final _LocalDraftForm draft = drafts[index];
      final int selectedTableCount = draft.formState.selectedTableCount;
      final List<LotteryTable> selectedTables =
          draft.formState.form.tables.take(selectedTableCount).toList();
      final LotteryForm groupedForm = draft.formState.form.copyWith(
        clearId: true,
        tables: selectedTables,
        status: LotteryFormStatus.lockedForGroup,
        mode: LotteryFormMode.group,
        isComplete: true,
        clearSavedAt: true,
        isEditable: false,
      );
      return GroupDraftPayload(
        form: groupedForm,
        cost: _calculateDraftCost(draft),
        tableCount: selectedTableCount,
        isDoubleMode: draft.isDoubleMode,
        displayOrder: index + 1,
        sourceDraftNumber: draft.number,
      );
    });
  }

  Future<void> _cleanupPersistedDraftsAfterSuccessfulSubmit() async {
    for (final _LocalDraftForm draft in _localDrafts) {
      final String? formId = draft.formState.form.formId;
      if (formId == null || formId.isEmpty) {
        continue;
      }
      debugPrint(
        '[DraftsDebug] cleanupPersonalDraftAfterSubmit start path=users/${draft.formState.form.userId}/forms/$formId localDraft=${draft.number}',
      );
      await _deletePersistedDraftIfNeeded(draft);
      debugPrint(
        '[DraftsDebug] cleanupPersonalDraftAfterSubmit success path=users/${draft.formState.form.userId}/forms/$formId localDraft=${draft.number}',
      );
    }
  }

  Future<void> _loadPersonalDraftRequest(
    PersonalDraftLoadRequest request,
  ) async {
    if (request.entries.isEmpty) {
      return;
    }
    final List<PersonalSavedDraftEntry> sortedEntries =
        List<PersonalSavedDraftEntry>.from(request.entries)
          ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    debugPrint(
      '[DraftsDebug] loadPersonalDraft start userId=${sortedEntries.first.form.userId} entries=${sortedEntries.length} bundleId=${sortedEntries.first.draftBundleId ?? 'null'}',
    );
    final List<_LocalDraftForm> loadedDrafts =
        List<_LocalDraftForm>.generate(sortedEntries.length, (index) {
      final PersonalSavedDraftEntry entry = sortedEntries[index];
      final LotteryForm editableForm = entry.form.copyWith(
        status: LotteryFormStatus.draft,
        isEditable: true,
        clearSavedAt: true,
        clearSubmittedAt: true,
        clearParentSubmissionId: true,
      );
      final LotteryFormState draftState =
          LotteryFormState.initial(entry.form.userId).copyWith(
        form: editableForm,
        selectedTableCount: entry.tableCount,
        activeRowIndex: 0,
        maxUnlockedRowIndex: math.max(entry.tableCount - 1, 0),
        isEditingSavedRecord: true,
        clearError: true,
        clearSuccess: true,
      );
      return _LocalDraftForm(
        number: index + 1,
        formState: draftState,
        isGroupMode: false,
        isDoubleMode: entry.isDoubleMode,
        persistedDraftFormId: entry.form.formId,
        persistedDraftBundleId: entry.draftBundleId,
      );
    });
    setState(() {
      _localDrafts
        ..clear()
        ..addAll(loadedDrafts);
      _activeDraftIndex = 0;
      _nextDraftNumber = loadedDrafts.length + 1;
      _isGroupMode = false;
      _isDoubleMode = loadedDrafts.first.isDoubleMode;
      _isPersonalPaymentFlowInProgress = false;
    });
    if (!mounted) {
      return;
    }
    context.read<LotteryFormCubit>().loadLocalDraftState(
          loadedDrafts.first.formState,
        );
    debugPrint(
      '[DraftsDebug] loadPersonalDraft success userId=${sortedEntries.first.form.userId} entries=${sortedEntries.length} activeDraft=0',
    );
  }

  String? _currentPersonalDraftBundleId(LotteryFormState state) {
    final List<_LocalDraftForm> drafts = _effectiveLocalDrafts(state);
    for (final _LocalDraftForm draft in drafts) {
      final String? bundleId = draft.persistedDraftBundleId;
      if (bundleId != null && bundleId.trim().isNotEmpty) {
        return bundleId.trim();
      }
    }
    return null;
  }

  Future<bool> _confirmDeletePersonalDraft() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('מחיקת טיוטה'),
            content: const Text('למחוק את הטיוטה?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('ביטול'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('מחיקה'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deleteCurrentPersonalDraft() async {
    final LotteryFormState currentState =
        context.read<LotteryFormCubit>().state;
    final String? bundleId = _currentPersonalDraftBundleId(currentState);
    final String? formId = currentState.form.formId;
    if ((bundleId == null || bundleId.isEmpty) &&
        (formId == null || formId.isEmpty)) {
      return;
    }
    final bool confirmed = await _confirmDeletePersonalDraft();
    if (!confirmed || !mounted) {
      return;
    }
    await _paymentRepository.deletePersonalDraft(
      userId: currentState.form.userId,
      formId: (bundleId == null || bundleId.isEmpty) ? formId : null,
      bundleId: bundleId,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _resetLocalDraftsAfterSubmit(currentState.form.userId);
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('הטיוטה נמחקה')),
      );
  }

  Future<void> _saveExplicitPersonalDraft() async {
    final LotteryFormState currentState =
        context.read<LotteryFormCubit>().state;
    final List<_LocalDraftForm> drafts = _effectiveLocalDrafts(currentState);
    if (drafts.any((draft) => draft.isGroupMode)) {
      return;
    }
    if (drafts.every((draft) => !_canPersistDraft(draft))) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('לא ניתן לשמור טופס ריק כטיוטה')),
        );
      return;
    }

    if (drafts.length == 1) {
      final _LocalDraftForm draft = drafts.first;
      final bool isEditingExistingDraft =
          draft.persistedDraftFormId?.trim().isNotEmpty == true;
      final String? currentDraftId = draft.persistedDraftFormId;
      final String? currentFormId = draft.formState.form.formId;
      final bool shouldCreateNewDraft = !isEditingExistingDraft;
      final bool shouldUpdateExistingDraft = isEditingExistingDraft;
      debugPrint(
        '[DraftsDebug] singleDraftLifecycle isEditingExistingDraft=$isEditingExistingDraft currentDraftId=${currentDraftId ?? 'null'} currentFormId=${currentFormId ?? 'null'} shouldCreateNewDraft=$shouldCreateNewDraft shouldUpdateExistingDraft=$shouldUpdateExistingDraft',
      );
      final bool isUpdate = isEditingExistingDraft;
      if (!isUpdate) {
        final int draftsCount =
            await _paymentRepository.countSavedPersonalDrafts(
          currentState.form.userId,
        );
        debugPrint(
          '[DraftsDebug] draftsCount check userId=${currentState.form.userId} count=$draftsCount max=3',
        );
        if (draftsCount >= 3) {
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text(
                  'ניתן לשמור עד 3 טיוטות. מחק טיוטה קיימת כדי לשמור חדשה.',
                ),
              ),
            );
          return;
        }
      }
      final LotteryForm candidate = draft.formState.form.copyWith(
        formId: draft.persistedDraftFormId,
        submissionId: draft.persistedDraftBundleId,
        status: LotteryFormStatus.saved,
        mode: LotteryFormMode.personal,
        isComplete: _isDraftComplete(draft),
        savedAt: DateTime.now(),
        clearId: !isEditingExistingDraft,
        clearSubmissionId: !isEditingExistingDraft,
        clearSubmittedAt: true,
        clearParentSubmissionId: true,
        clearGroupId: true,
        isEditable: true,
      );
      debugPrint(
        '[DraftsDebug] explicitSavePersonalDraft start userId=${candidate.userId} drafts=1 bundleId=${candidate.submissionId ?? 'null'}',
      );
      final PersonalSavedDraftEntry saved =
          await _paymentRepository.savePersonalDraft(
        form: candidate,
        tableCount: draft.formState.selectedTableCount,
        cost: _calculateDraftCost(draft),
        isDoubleMode: draft.isDoubleMode,
      );
      if (!mounted) {
        return;
      }
      await _loadPersonalDraftRequest(
        PersonalDraftLoadRequest(entries: <PersonalSavedDraftEntry>[saved]),
      );
      if (!mounted) {
        return;
      }
      debugPrint(
        '[DraftsDebug] explicitSavePersonalDraft success userId=${saved.form.userId} drafts=1 formId=${saved.form.formId ?? 'null'}',
      );
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('הטיוטה נשמרה בהצלחה')),
        );
      return;
    }

    final List<PersonalSubmissionDraftPayload> payloads =
        _buildPersonalSubmissionDraftPayloads(drafts);
    final String? existingBundleId =
        _currentPersonalDraftBundleId(currentState);
    final bool isEditingExistingDraft =
        existingBundleId != null && existingBundleId.isNotEmpty;
    debugPrint(
      '[DraftsDebug] bundleDraftLifecycle isEditingExistingDraft=$isEditingExistingDraft currentDraftId=${existingBundleId ?? 'null'} currentFormId=${drafts.first.persistedDraftFormId ?? drafts.first.formState.form.formId ?? 'null'} shouldCreateNewDraft=${!isEditingExistingDraft} shouldUpdateExistingDraft=$isEditingExistingDraft',
    );
    if (existingBundleId == null || existingBundleId.isEmpty) {
      final int draftsCount = await _paymentRepository.countSavedPersonalDrafts(
        currentState.form.userId,
      );
      debugPrint(
        '[DraftsDebug] draftsCount check userId=${currentState.form.userId} count=$draftsCount max=3',
      );
      if (draftsCount >= 3) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'ניתן לשמור עד 3 טיוטות. מחק טיוטה קיימת כדי לשמור חדשה.',
              ),
            ),
          );
        return;
      }
    }
    debugPrint(
      '[DraftsDebug] explicitSavePersonalDraft start userId=${currentState.form.userId} drafts=${payloads.length} bundleId=${existingBundleId ?? 'new'}',
    );
    final String bundleId = await _paymentRepository.savePersonalDraftBundle(
      userId: currentState.form.userId,
      drafts: payloads,
      existingBundleId: existingBundleId,
    );
    final List<PersonalSavedDraftEntry> savedEntries =
        await _paymentRepository.loadPersonalDraftBundle(
      userId: currentState.form.userId,
      bundleId: bundleId,
    );
    if (!mounted) {
      return;
    }
    await _loadPersonalDraftRequest(
      PersonalDraftLoadRequest(entries: savedEntries),
    );
    if (!mounted) {
      return;
    }
    debugPrint(
      '[DraftsDebug] explicitSavePersonalDraft success userId=${currentState.form.userId} drafts=${savedEntries.length} bundleId=$bundleId',
    );
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('הטיוטה נשמרה בהצלחה')),
      );
  }

  void _resetLocalDraftsAfterSubmit(String userId) {
    final LotteryFormState initialState = LotteryFormState.initial(userId);
    _localDrafts
      ..clear()
      ..add(
        _LocalDraftForm(
          number: 1,
          formState: initialState,
          isGroupMode: false,
          isDoubleMode: false,
        ),
      );
    _activeDraftIndex = 0;
    _nextDraftNumber = 2;
    _isGroupMode = false;
    _isDoubleMode = false;
    context.read<LotteryFormCubit>().loadLocalDraftState(initialState);
  }

  String _formatNisAmount(num amount) {
    final double normalized = amount.toDouble();
    if ((normalized - normalized.roundToDouble()).abs() < 0.0001) {
      return normalized.round().toString();
    }
    return normalized.toStringAsFixed(1);
  }

  int? _firstIncompleteDraftNumber(LotteryFormState state) {
    final List<_LocalDraftForm> drafts = _effectiveLocalDrafts(state);
    for (final _LocalDraftForm draft in drafts) {
      if (!_isDraftComplete(draft)) {
        return draft.number;
      }
    }
    return null;
  }

  Future<void> _promptCreateGroup() async {
    final Stopwatch stopwatch = Stopwatch()..start();
    debugPrint('[CreateGroupFlow] prompt start +0ms');
    final LotteryFormState currentState =
        context.read<LotteryFormCubit>().state;
    if (!currentState.form.isComplete || currentState.isBusy) {
      debugPrint(
        '[CreateGroupFlow] blocked before dialog +${stopwatch.elapsedMilliseconds}ms complete=${currentState.form.isComplete} isBusy=${currentState.isBusy}',
      );
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('יש למלא את כל הטבלאות לפני שליחה'),
          ),
        );
      return;
    }

    final String? groupName = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (context) => const _CreateGroupDialog(),
    );
    debugPrint(
      '[CreateGroupFlow] dialog resolved +${stopwatch.elapsedMilliseconds}ms groupName="${groupName ?? ''}"',
    );

    if (!mounted || groupName == null || groupName.trim().isEmpty) {
      debugPrint(
        '[CreateGroupFlow] cancelled/empty +${stopwatch.elapsedMilliseconds}ms mounted=$mounted',
      );
      return;
    }

    final List<_LocalDraftForm> effectiveDrafts =
        _effectiveLocalDrafts(currentState);
    LotteryGroup? group;
    if (effectiveDrafts.length == 1) {
      debugPrint(
        '[CreateGroupFlow] cubit.createGroup start +${stopwatch.elapsedMilliseconds}ms',
      );
      group = await context.read<LotteryFormCubit>().createGroup(groupName);
      debugPrint(
        '[CreateGroupFlow] cubit.createGroup end +${stopwatch.elapsedMilliseconds}ms groupId=${group?.groupId ?? 'null'}',
      );
    } else {
      final bool allGroupDrafts =
          effectiveDrafts.every((draft) => draft.isGroupMode);
      if (!allGroupDrafts) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('שליחת כמה טפסים קבוצתיים עדיין לא נתמכת'),
            ),
          );
        return;
      }

      debugPrint(
        '[CreateGroupFlow] repository.createGroupFromFormsBundle start +${stopwatch.elapsedMilliseconds}ms draftCount=${effectiveDrafts.length}',
      );
      group = await _paymentRepository.createGroupFromFormsBundle(
        userId: currentState.form.userId,
        groupName: groupName.trim(),
        drafts: _buildGroupDraftPayloads(effectiveDrafts),
      );
      debugPrint(
        '[CreateGroupFlow] repository.createGroupFromFormsBundle end +${stopwatch.elapsedMilliseconds}ms groupId=${group.groupId}',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _resetLocalDraftsAfterSubmit(currentState.form.userId);
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('הקבוצה נוצרה והטפסים ננעלו לעריכה'),
          ),
        );
    }
    if (!mounted || group == null) {
      debugPrint(
        '[CreateGroupFlow] abort after createGroup +${stopwatch.elapsedMilliseconds}ms mounted=$mounted',
      );
      return;
    }
    final LotteryGroup createdGroup = group;

    debugPrint(
      '[CreateGroupFlow] navigation push start +${stopwatch.elapsedMilliseconds}ms groupId=${createdGroup.groupId}',
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GroupDetailsPage(
          groupId: createdGroup.groupId,
          currentUserId: createdGroup.creatorUserId,
          inviteLinkService: widget.inviteLinkService,
          repository: _groupRepository,
        ),
      ),
    );
    debugPrint(
      '[CreateGroupFlow] navigation pop/end +${stopwatch.elapsedMilliseconds}ms groupId=${createdGroup.groupId}',
    );
  }

  Future<void> _confirmClearForm() async {
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('אישור'),
            content: const Text('האם אתה בטוח שאתה רוצה לנקות את הטופס?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('ביטול'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('ניקוי'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) {
      return;
    }

    context.read<LotteryFormCubit>().clearForm();
  }

  Future<void> _showDraftFormsSheet(LotteryFormState state) async {
    final LotteryFormCubit cubit = context.read<LotteryFormCubit>();
    _syncActiveDraftSnapshot(state);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Material(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(28),
                    elevation: 16,
                    child: StatefulBuilder(
                      builder: (context, sheetSetState) {
                        final List<_LocalDraftForm> drafts =
                            _effectiveLocalDrafts(cubit.state);
                        final bool canDeleteDrafts = drafts.length > 1;
                        final num totalDraftsCost =
                            _calculateDraftsTotalCost(drafts);
                        return SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'הטפסים שלי',
                                textAlign: TextAlign.right,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 16),
                              ...List.generate(drafts.length, (index) {
                                final _LocalDraftForm draft = drafts[index];
                                final bool isActive =
                                    index == _activeDraftIndex;
                                final bool isDraftComplete =
                                    _isDraftComplete(draft);
                                final num draftCost =
                                    _calculateDraftCost(draft);
                                return Padding(
                                  padding: EdgeInsets.only(
                                    bottom: index == drafts.length - 1 ? 0 : 10,
                                  ),
                                  child: Material(
                                    color: isActive
                                        ? Theme.of(context)
                                            .colorScheme
                                            .primaryContainer
                                            .withValues(alpha: 0.7)
                                        : Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(18),
                                    child: InkWell(
                                      onTap: () {
                                        Navigator.of(context).pop();
                                        _switchToLocalDraft(index);
                                      },
                                      borderRadius: BorderRadius.circular(18),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 12,
                                        ),
                                        child: Row(
                                          textDirection: TextDirection.rtl,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            IconButton(
                                              onPressed: canDeleteDrafts
                                                  ? () async {
                                                      final bool deleted =
                                                          await _deleteLocalDraft(
                                                              index);
                                                      if (deleted &&
                                                          context.mounted) {
                                                        sheetSetState(() {});
                                                      }
                                                    }
                                                  : null,
                                              tooltip: canDeleteDrafts
                                                  ? 'מחק טופס'
                                                  : 'לא ניתן למחוק את הטופס האחרון',
                                              icon: const Icon(
                                                  Icons.delete_outline),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment.end,
                                                    textDirection:
                                                        TextDirection.rtl,
                                                    children: [
                                                      if (isActive) ...[
                                                        Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                            horizontal: 8,
                                                            vertical: 3,
                                                          ),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: Theme.of(
                                                                    context)
                                                                .colorScheme
                                                                .primary
                                                                .withValues(
                                                                    alpha:
                                                                        0.14),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        999),
                                                          ),
                                                          child: Text(
                                                            'פעיל',
                                                            style: Theme.of(
                                                                    context)
                                                                .textTheme
                                                                .labelMedium
                                                                ?.copyWith(
                                                                  color: Theme.of(
                                                                          context)
                                                                      .colorScheme
                                                                      .primary,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w800,
                                                                ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            width: 8),
                                                      ],
                                                      Text(
                                                        'טופס ${draft.number}',
                                                        textAlign:
                                                            TextAlign.right,
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .titleMedium
                                                            ?.copyWith(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800,
                                                            ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Wrap(
                                                    alignment:
                                                        WrapAlignment.end,
                                                    spacing: 8,
                                                    runSpacing: 4,
                                                    children: [
                                                      _DraftMetaText(
                                                        value: draft.isGroupMode
                                                            ? 'קבוצתי'
                                                            : 'אישי',
                                                      ),
                                                      _DraftMetaText(
                                                        value:
                                                            draft.isDoubleMode
                                                                ? 'דאבל'
                                                                : 'רגיל',
                                                      ),
                                                      _DraftMetaText(
                                                        value:
                                                            '${draft.formState.selectedTableCount} טבלאות',
                                                      ),
                                                      _DraftMetaText(
                                                        value: isDraftComplete
                                                            ? 'מלא'
                                                            : 'לא מלא',
                                                        accent: isDraftComplete
                                                            ? Theme.of(context)
                                                                .colorScheme
                                                                .primary
                                                            : Theme.of(context)
                                                                .colorScheme
                                                                .onSurfaceVariant,
                                                      ),
                                                      _DraftMetaText(
                                                        value:
                                                            'עלות: ${_formatNisAmount(draftCost)} ש״ח',
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  'סה״כ: ${_formatNisAmount(totalDraftsCost)} ש״ח',
                                  textAlign: TextAlign.right,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                              ),
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  _createAdditionalLocalDraft();
                                },
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('+ טופס נוסף'),
                              ),
                              const SizedBox(height: 10),
                              FilledButton.tonal(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('סגירה'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmClearTable(int rowIndex) async {
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('מחיקת טבלה'),
            content: const Text('האם למחוק את המספרים בטבלה זו?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('ביטול'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('אישור'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) {
      return;
    }

    context.read<LotteryFormCubit>().clearSingleTable(rowIndex);
  }

  Future<void> _startPersonalSubmitFlow() async {
    final LotteryFormState currentState =
        context.read<LotteryFormCubit>().state;
    final List<LotteryTable> selectedTables =
        currentState.form.tables.take(currentState.selectedTableCount).toList();
    final num formCost = _paymentRepository.calculateTicketCost(selectedTables);

    final bool? paymentConfirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PaymentOptionsPage(
          userId: currentState.form.userId,
          amount: formCost,
          onWalletPayment: () async {
            await _paymentRepository.chargeUserWallet(
              userId: currentState.form.userId,
              amount: formCost,
            );
            await _submitPersonalFormAndOpenHistory();
          },
          onExternalPayment: _submitPersonalFormAndOpenHistory,
        ),
      ),
    );

    if (!mounted || paymentConfirmed != true) {
      return;
    }
  }

  Future<void> _startPersonalMultiDraftSubmitFlow(
    List<_LocalDraftForm> drafts,
  ) async {
    final LotteryFormState currentState =
        context.read<LotteryFormCubit>().state;
    final List<PersonalSubmissionDraftPayload> payloads =
        _buildPersonalSubmissionDraftPayloads(drafts);
    final num totalCost = _calculateDraftsTotalCost(drafts);
    _isPersonalPaymentFlowInProgress = true;
    final bool? paymentConfirmed = await Navigator.of(context)
        .push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PaymentOptionsPage(
          userId: currentState.form.userId,
          amount: totalCost,
          onWalletPayment: () async {
            await _paymentRepository.chargeUserWallet(
              userId: currentState.form.userId,
              amount: totalCost,
            );
            await _submitPersonalDraftBundleAndOpenHistory(
              userId: currentState.form.userId,
              payloads: payloads,
            );
          },
          onExternalPayment: () => _submitPersonalDraftBundleAndOpenHistory(
            userId: currentState.form.userId,
            payloads: payloads,
          ),
        ),
      ),
    )
        .whenComplete(() {
      _isPersonalPaymentFlowInProgress = false;
    });

    if (!mounted || paymentConfirmed != true) {
      return;
    }
  }

  Future<void> _submitPersonalFormAndOpenHistory() async {
    await context.read<LotteryFormCubit>().submitForm();
    if (!mounted) {
      return;
    }

    final LotteryFormState latestState = context.read<LotteryFormCubit>().state;
    if (latestState.errorMessage == null) {
      await _cleanupPersistedDraftsAfterSuccessfulSubmit();
      widget.onOpenMyForms();
      return;
    }
    throw StateError(latestState.errorMessage ?? 'שליחת הטופס נכשלה');
  }

  Future<void> _submitPersonalDraftBundleAndOpenHistory({
    required String userId,
    required List<PersonalSubmissionDraftPayload> payloads,
  }) async {
    await _paymentRepository.submitPersonalSubmissionBundle(
      userId: userId,
      drafts: payloads,
      totalCost: payloads.fold<num>(
        0,
        (num total, PersonalSubmissionDraftPayload draft) => total + draft.cost,
      ),
    );
    await _cleanupPersistedDraftsAfterSuccessfulSubmit();

    if (!mounted) {
      return;
    }

    setState(() {
      _resetLocalDraftsAfterSubmit(userId);
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('הטפסים האישיים נשלחו בהצלחה'),
        ),
      );

    widget.onOpenMyForms();
  }

  void _handleTableCountChanged(int? count) {
    if (count == null) {
      return;
    }
    context.read<LotteryFormCubit>().setSelectedTableCount(count);
  }

  bool _areSelectedTablesComplete(
    List<LotteryTable> visibleTables,
    int selectedTableCount,
  ) {
    if (visibleTables.length != selectedTableCount || visibleTables.isEmpty) {
      return false;
    }
    return visibleTables.every((table) => table.isComplete);
  }

  Future<void> _handlePrimarySubmit() async {
    final LotteryFormState formState = context.read<LotteryFormCubit>().state;
    final List<_LocalDraftForm> effectiveDrafts =
        _effectiveLocalDrafts(formState);
    final int? firstIncompleteDraftNumber =
        _firstIncompleteDraftNumber(formState);
    if (firstIncompleteDraftNumber != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
                'יש להשלים את טופס $firstIncompleteDraftNumber לפני השליחה'),
          ),
        );
      return;
    }
    if (effectiveDrafts.length > 1) {
      final bool hasAnyGroupDraft =
          effectiveDrafts.any((draft) => draft.isGroupMode);
      if (hasAnyGroupDraft) {
        await _promptCreateGroup();
        return;
      }
      await _startPersonalMultiDraftSubmitFlow(effectiveDrafts);
      return;
    }
    final List<LotteryTable> visibleTables = context
        .read<LotteryFormCubit>()
        .state
        .form
        .tables
        .take(formState.selectedTableCount)
        .toList();
    if (!_areSelectedTablesComplete(
      visibleTables,
      formState.selectedTableCount,
    )) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('יש למלא את כל הטבלאות לפני שליחה'),
          ),
        );
      return;
    }
    if (_isGroupMode) {
      await _promptCreateGroup();
      return;
    }
    await _startPersonalSubmitFlow();
  }

  GlobalKey _tableRowKeyForIndex(int index) {
    return _tableRowKeys.putIfAbsent(index, () => GlobalKey());
  }

  void _scheduleEnsureActiveTableVisible({
    required LotteryFormState state,
  }) {
    final bool activeRowChanged =
        _lastAutoScrolledActiveRowIndex != state.activeRowIndex;
    final bool tableCountChanged =
        _lastAutoScrolledSelectedTableCount != state.selectedTableCount;
    if (!activeRowChanged && !tableCountChanged) {
      return;
    }

    _lastAutoScrolledActiveRowIndex = state.activeRowIndex;
    _lastAutoScrolledSelectedTableCount = state.selectedTableCount;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _ensureTableVisibleAboveKeyboard(
        rowIndex: state.activeRowIndex,
      );
    });
  }

  Future<void> _ensureTableVisibleAboveKeyboard({
    required int rowIndex,
  }) async {
    if (!mounted || !_tablesScrollController.hasClients) {
      return;
    }

    final BuildContext? rowContext =
        _tableRowKeyForIndex(rowIndex).currentContext;
    final BuildContext? listContext = _tablesListKey.currentContext;
    if (rowContext == null ||
        listContext == null ||
        !rowContext.mounted ||
        !listContext.mounted) {
      return;
    }

    final RenderObject? rowRenderObject = rowContext.findRenderObject();
    final RenderObject? listRenderObject = listContext.findRenderObject();
    if (rowRenderObject is! RenderBox || listRenderObject is! RenderBox) {
      return;
    }

    final Offset rowTopLeft = rowRenderObject.localToGlobal(Offset.zero);
    final double rowTop = rowTopLeft.dy;
    final double rowBottom = rowTop + rowRenderObject.size.height;

    final Offset listTopLeft = listRenderObject.localToGlobal(Offset.zero);
    final double listTop = listTopLeft.dy;
    final double listBottom = listTop + listRenderObject.size.height;

    const double visiblePadding = 12;
    final double safeTop = listTop + visiblePadding;
    final double safeBottom = listBottom - visiblePadding;

    double targetOffset = _tablesScrollController.offset;
    if (rowBottom > safeBottom) {
      targetOffset += rowBottom - safeBottom;
    } else if (rowTop < safeTop) {
      targetOffset -= safeTop - rowTop;
    } else {
      return;
    }

    final double clampedTarget = targetOffset.clamp(
      _tablesScrollController.position.minScrollExtent,
      _tablesScrollController.position.maxScrollExtent,
    );
    if ((clampedTarget - _tablesScrollController.offset).abs() < 2) {
      return;
    }

    await _tablesScrollController.animateTo(
      clampedTarget,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  double _calculateKeyboardHeight(
    BuildContext context,
    double availableHeight,
  ) {
    final double compactness =
        ((780.0 - availableHeight) / 260.0).clamp(0.0, 1.0);
    final double minHeight = lerpDouble(
          228.0,
          190.0,
          compactness,
        ) ??
        206.0;
    final double maxHeight = lerpDouble(
          292.0,
          248.0,
          compactness,
        ) ??
        270.0;
    final double ratio = lerpDouble(
          0.315,
          0.275,
          compactness,
        ) ??
        0.295;
    final double desiredHeight = availableHeight * ratio;
    return _safeClamp(desiredHeight, minHeight, maxHeight);
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<LotteryFormCubit, LotteryFormState>(
      listenWhen: (_, __) => true,
      listener: (context, state) {
        _syncActiveDraftSnapshot(state);
        _schedulePersistActivePersonalDraft(state);
        final String? message = state.errorMessage ?? state.successMessage;
        if (message == null) {
          return;
        }

        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        context.read<LotteryFormCubit>().clearMessages();
      },
      builder: (context, state) {
        _ensureInitialDraftRegistered(state);
        final List<LotteryTable> visibleTables = state.visibleTables;
        final int? firstIncompleteDraftNumber =
            _firstIncompleteDraftNumber(state);
        final bool canPrimarySubmit =
            !state.isBusy && firstIncompleteDraftNumber == null;
        final int? gapRowIndex = state.firstGapRowIndex;
        return MediaQuery.removeViewInsets(
          removeBottom: true,
          context: context,
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final _FormPageLayoutMetrics metrics =
                    _FormPageLayoutMetrics.fromAvailableHeight(
                  constraints.maxHeight,
                );
                final double keyboardHeight = _calculateKeyboardHeight(
                  context,
                  constraints.maxHeight,
                );
                _scheduleEnsureActiveTableVisible(
                  state: state,
                );

                return Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        10,
                        metrics.topPadding,
                        10,
                        metrics.topBottomPadding,
                      ),
                      child: Column(
                        children: [
                          const _CompactTopInfoRow(),
                          SizedBox(height: metrics.sectionGap),
                          _CompactControlRow(
                            metrics: metrics,
                            isGroupMode: _isGroupMode,
                            isDoubleMode: _isDoubleMode,
                            selectedTableCount: state.selectedTableCount,
                            isBusy: state.isBusy,
                            onModeChanged: _handleDraftModeChanged,
                            onPlayTypeChanged: (value) => setState(() {
                              _isDoubleMode = value;
                              _syncActiveDraftSnapshot(
                                context.read<LotteryFormCubit>().state,
                              );
                            }),
                            onTableCountChanged: _handleTableCountChanged,
                          ),
                          SizedBox(height: metrics.sectionGap),
                          _PrimarySubmitButton(
                            metrics: metrics,
                            isEnabled: canPrimarySubmit,
                            onPressed: _handlePrimarySubmit,
                          ),
                          SizedBox(height: metrics.sectionGap),
                          _SecondaryActionRow(
                            metrics: metrics,
                            isBusy: state.isBusy,
                            showSaveDraft: !_isGroupMode,
                            showDeleteDraft:
                                !_isGroupMode && state.isEditingSavedRecord,
                            onClearPressed: _confirmClearForm,
                            onSaveDraftPressed: _saveExplicitPersonalDraft,
                            onDeleteDraftPressed: _deleteCurrentPersonalDraft,
                            onManageDraftsPressed: () =>
                                _showDraftFormsSheet(state),
                            onLottomatAction: (action) {
                              if (action == _LottomatAction.completeRemaining) {
                                context
                                    .read<LotteryFormCubit>()
                                    .completeRemainingTables();
                              } else {
                                context
                                    .read<LotteryFormCubit>()
                                    .generateFullRandomForm();
                              }
                            },
                          ),
                          if (gapRowIndex != null) ...[
                            SizedBox(height: metrics.sectionGap),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                'יש להשלים טבלה ${gapRowIndex + 1} לפני המשך',
                                textAlign: TextAlign.right,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          ],
                          if (firstIncompleteDraftNumber != null) ...[
                            SizedBox(height: metrics.sectionGap),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                'יש להשלים את טופס $firstIncompleteDraftNumber לפני השליחה',
                                textAlign: TextAlign.right,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          ],
                          SizedBox(height: metrics.sectionGap),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'החלק ימינה ללוטומט בטבלה אחת, שמאלה לניקוי',
                              textAlign: TextAlign.right,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: ListView.separated(
                          key: _tablesListKey,
                          controller: _tablesScrollController,
                          padding: const EdgeInsets.only(bottom: 8),
                          itemCount: visibleTables.length,
                          separatorBuilder: (_, __) =>
                              SizedBox(height: metrics.listGap),
                          itemBuilder: (context, index) {
                            return _LotteryRowCard(
                              key: _tableRowKeyForIndex(index),
                              table: visibleTables[index],
                              isActive: index == state.activeRowIndex,
                              isEnabled: state.isRowInteractable(index),
                              isGapTarget: gapRowIndex == index,
                              onTap: () => context
                                  .read<LotteryFormCubit>()
                                  .selectRow(index),
                              onSwipeRight: () => context
                                  .read<LotteryFormCubit>()
                                  .randomizeSingleTable(index),
                              onSwipeLeft: () => _confirmClearTable(index),
                            );
                          },
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(top: metrics.keyboardTopGap),
                      child: _LotteryKeyboardSheet(
                        height: keyboardHeight,
                        state: state,
                        visibleTableCount: state.selectedTableCount,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _CreateGroupDialog extends StatefulWidget {
  const _CreateGroupDialog();

  @override
  State<_CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends State<_CreateGroupDialog> {
  late final TextEditingController _controller;
  late final Stopwatch _dialogStopwatch;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _dialogStopwatch = Stopwatch()..start();
    debugPrint('[CreateGroupFlow] dialog shown +0ms');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData mediaQuery = MediaQuery.of(context);
    final double keyboardInset = mediaQuery.viewInsets.bottom;
    final double maxDialogHeight = math.max(
      220,
      mediaQuery.size.height - keyboardInset - 32,
    );

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(16, 24, 16, 16 + keyboardInset),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 420,
            maxHeight: maxDialogHeight,
          ),
          child: Material(
            color: Theme.of(context).dialogTheme.backgroundColor ??
                Theme.of(context).colorScheme.surface,
            elevation: 24,
            borderRadius: BorderRadius.circular(28),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'יצירת קבוצת לוטו',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Directionality(
                    textDirection: TextDirection.rtl,
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(
                        labelText: 'שם קבוצה',
                        hintText: 'למשל: קבוצת שישי',
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            debugPrint(
                              '[CreateGroupFlow] dialog confirm click +${_dialogStopwatch.elapsedMilliseconds}ms value="${_controller.text.trim()}"',
                            );
                            Navigator.of(context).pop(_controller.text.trim());
                          },
                          child: const Text('יצירה'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('ביטול'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UpcomingLotteryMetadata {
  const _UpcomingLotteryMetadata({
    required this.displayDate,
    required this.displayTime,
    required this.regularLottoPrize,
    required this.doubleLottoPrize,
  });

  factory _UpcomingLotteryMetadata.fromMap(Map<String, dynamic> data) {
    return _UpcomingLotteryMetadata(
      displayDate: (data['displayDate'] as String?)?.trim(),
      displayTime: (data['displayTime'] as String?)?.trim(),
      regularLottoPrize: (data['regularLottoPrize'] as String?)?.trim(),
      doubleLottoPrize: (data['doubleLottoPrize'] as String?)?.trim(),
    );
  }

  final String? displayDate;
  final String? displayTime;
  final String? regularLottoPrize;
  final String? doubleLottoPrize;

  String _formatPrize(String? value, {bool includeUntil = false}) {
    final String normalized = (value ?? '').trim();
    if (normalized.isEmpty) {
      return 'טרם פורסם';
    }
    if (includeUntil && !normalized.startsWith('עד')) {
      return 'עד $normalized';
    }
    return normalized;
  }

  String get tickerText {
    final String dateLabel =
        (displayDate?.isNotEmpty ?? false) ? displayDate! : 'תאריך יעדכן בקרוב';
    final String lottoLabel = _formatPrize(regularLottoPrize);
    final String doubleLabel = _formatPrize(
      doubleLottoPrize,
      includeUntil: true,
    );
    return 'ההגרלה הקרובה: $dateLabel | לוטו: $lottoLabel | דאבל: $doubleLabel';
  }
}

class _CompactTopInfoRow extends StatefulWidget {
  const _CompactTopInfoRow();

  @override
  State<_CompactTopInfoRow> createState() => _CompactTopInfoRowState();
}

class _CompactTopInfoRowState extends State<_CompactTopInfoRow> {
  late final Future<_UpcomingLotteryMetadata> _metadataFuture;
  late final ScrollController _scrollController;
  bool _scrollLoopStarted = false;

  @override
  void initState() {
    super.initState();
    _metadataFuture = _loadMetadata();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<_UpcomingLotteryMetadata> _loadMetadata() async {
    final HttpsCallable callable =
        FirebaseFunctions.instanceFor(region: 'us-central1')
            .httpsCallable('getUpcomingLotteryMetadata');
    final HttpsCallableResult<dynamic> result = await callable.call();
    debugPrint(
      '[HomeTopRow] getUpcomingLotteryMetadata raw payload: ${result.data}',
    );
    final Map<String, dynamic> data =
        Map<String, dynamic>.from(result.data as Map<dynamic, dynamic>);
    return _UpcomingLotteryMetadata.fromMap(data);
  }

  void _ensureScrollLoop() {
    if (_scrollLoopStarted) {
      return;
    }
    _scrollLoopStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      while (mounted) {
        if (!_scrollController.hasClients) {
          await Future<void>.delayed(const Duration(seconds: 1));
          continue;
        }
        final double maxExtent = _scrollController.position.maxScrollExtent;
        if (maxExtent <= 4) {
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }
        final int durationMs = (maxExtent * 32).round().clamp(10000, 18000);
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (!mounted || !_scrollController.hasClients) {
          return;
        }
        await _scrollController.animateTo(
          maxExtent,
          duration: Duration(milliseconds: durationMs),
          curve: Curves.easeInOut,
        );
        if (!mounted || !_scrollController.hasClients) {
          return;
        }
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted || !_scrollController.hasClients) {
          return;
        }
        _scrollController.jumpTo(0);
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_UpcomingLotteryMetadata>(
      future: _metadataFuture,
      builder: (context, snapshot) {
        final String tickerText = snapshot.hasData
            ? snapshot.data!.tickerText
            : snapshot.hasError
                ? 'ההגרלה הקרובה: הנתונים אינם זמינים כרגע'
                : 'ההגרלה הקרובה: טוען נתונים...';
        if (snapshot.hasData) {
          _ensureScrollLoop();
        }
        return Row(
          children: [
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.notifications_none_rounded),
              tooltip: 'התראות',
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: ClipRect(
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Text(
                        tickerText,
                        maxLines: 1,
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CompactControlRow extends StatelessWidget {
  const _CompactControlRow({
    required this.metrics,
    required this.isGroupMode,
    required this.isDoubleMode,
    required this.selectedTableCount,
    required this.isBusy,
    required this.onModeChanged,
    required this.onPlayTypeChanged,
    required this.onTableCountChanged,
  });

  final _FormPageLayoutMetrics metrics;
  final bool isGroupMode;
  final bool isDoubleMode;
  final int selectedTableCount;
  final bool isBusy;
  final ValueChanged<bool> onModeChanged;
  final ValueChanged<bool> onPlayTypeChanged;
  final ValueChanged<int?> onTableCountChanged;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        children: [
          Expanded(
            child: _CompactFieldShell(
              metrics: metrics,
              child: _TwoOptionToggle(
                metrics: metrics,
                isBusy: isBusy,
                leftLabel: 'אישי',
                rightLabel: 'קבוצתי',
                selectedRight: isGroupMode,
                onChanged: onModeChanged,
              ),
            ),
          ),
          SizedBox(width: metrics.sectionGap),
          Expanded(
            child: _CompactFieldShell(
              metrics: metrics,
              child: _TwoOptionToggle(
                metrics: metrics,
                isBusy: isBusy,
                leftLabel: 'רגיל',
                rightLabel: 'דאבל',
                selectedRight: isDoubleMode,
                onChanged: onPlayTypeChanged,
              ),
            ),
          ),
          SizedBox(width: metrics.sectionGap),
          Expanded(
            child: _CompactFieldShell(
              metrics: metrics,
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: selectedTableCount,
                  borderRadius: BorderRadius.circular(16),
                  alignment: AlignmentDirectional.centerEnd,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  items: const [2, 4, 6, 8, 10, 12, 14]
                      .map(
                        (count) => DropdownMenuItem<int>(
                          value: count,
                          alignment: Alignment.centerRight,
                          child: Text('$count טבלאות'),
                        ),
                      )
                      .toList(),
                  onChanged: isBusy ? null : onTableCountChanged,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TwoOptionToggle extends StatelessWidget {
  const _TwoOptionToggle({
    required this.metrics,
    required this.isBusy,
    required this.leftLabel,
    required this.rightLabel,
    required this.selectedRight,
    required this.onChanged,
  });

  final _FormPageLayoutMetrics metrics;
  final bool isBusy;
  final String leftLabel;
  final String rightLabel;
  final bool selectedRight;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final Color selectedColor = Theme.of(context).colorScheme.primary;
    final Color selectedText = Theme.of(context).colorScheme.onPrimary;
    final Color unselectedColor = Colors.transparent;
    final Color unselectedText = Theme.of(context).colorScheme.onSurface;

    Widget option({
      required String label,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: GestureDetector(
          onTap: isBusy ? null : onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            height: metrics.toggleHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? selectedColor : unselectedColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? selectedColor
                    : Theme.of(context).dividerColor.withValues(alpha: 0.5),
              ),
              boxShadow: selected
                  ? const [
                      BoxShadow(
                        color: Color(0x26000000),
                        blurRadius: 8,
                        offset: Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? selectedText : unselectedText,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        option(
          label: leftLabel,
          selected: !selectedRight,
          onTap: () => onChanged(false),
        ),
        SizedBox(width: math.max(4, metrics.sectionGap - 1)),
        option(
          label: rightLabel,
          selected: selectedRight,
          onTap: () => onChanged(true),
        ),
      ],
    );
  }
}

class _CompactFieldShell extends StatelessWidget {
  const _CompactFieldShell({
    required this.metrics,
    required this.child,
  });

  final _FormPageLayoutMetrics metrics;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: metrics.fieldShellHeight,
      padding: EdgeInsets.symmetric(
        horizontal: lerpDouble(6.0, 4.0, metrics.compactness) ?? 5.0,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

class _PrimarySubmitButton extends StatelessWidget {
  const _PrimarySubmitButton({
    required this.metrics,
    required this.isEnabled,
    required this.onPressed,
  });

  final _FormPageLayoutMetrics metrics;
  final bool isEnabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            height: metrics.primaryButtonHeight,
            decoration: BoxDecoration(
              color: isEnabled
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Center(
              child: Text(
                'שליחה',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryActionRow extends StatelessWidget {
  const _SecondaryActionRow({
    required this.metrics,
    required this.isBusy,
    required this.showSaveDraft,
    required this.showDeleteDraft,
    required this.onClearPressed,
    required this.onSaveDraftPressed,
    required this.onDeleteDraftPressed,
    required this.onManageDraftsPressed,
    required this.onLottomatAction,
  });

  final _FormPageLayoutMetrics metrics;
  final bool isBusy;
  final bool showSaveDraft;
  final bool showDeleteDraft;
  final VoidCallback onClearPressed;
  final VoidCallback onSaveDraftPressed;
  final VoidCallback onDeleteDraftPressed;
  final VoidCallback onManageDraftsPressed;
  final ValueChanged<_LottomatAction> onLottomatAction;

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = <Widget>[
      Expanded(
        child: PopupMenuButton<_LottomatAction>(
          enabled: !isBusy,
          onSelected: onLottomatAction,
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: _LottomatAction.completeRemaining,
              child: Text('השלם את שאר הטבלאות'),
            ),
            PopupMenuItem(
              value: _LottomatAction.fullRandom,
              child: Text('לוטומט מלא'),
            ),
          ],
          child: _ActionChip(
            metrics: metrics,
            label: 'לוטומט',
            icon: Icons.auto_awesome,
          ),
        ),
      ),
      SizedBox(width: metrics.sectionGap + 2),
      if (showSaveDraft) ...<Widget>[
        Expanded(
          child: _ActionChip(
            metrics: metrics,
            label: 'שמור טיוטה',
            icon: Icons.bookmark_outline,
            onTap: isBusy ? null : onSaveDraftPressed,
          ),
        ),
        SizedBox(width: metrics.sectionGap + 2),
      ],
      if (showDeleteDraft) ...<Widget>[
        Expanded(
          child: _ActionChip(
            metrics: metrics,
            label: 'מחק טיוטה',
            icon: Icons.delete_sweep_outlined,
            onTap: isBusy ? null : onDeleteDraftPressed,
          ),
        ),
        SizedBox(width: metrics.sectionGap + 2),
      ],
      Expanded(
        child: _ActionChip(
          metrics: metrics,
          label: 'ניהול טפסים',
          icon: Icons.layers_outlined,
          onTap: onManageDraftsPressed,
        ),
      ),
      SizedBox(width: metrics.sectionGap + 2),
      Expanded(
        child: _ActionChip(
          metrics: metrics,
          label: 'נקה טופס',
          icon: Icons.delete_outline,
          onTap: isBusy ? null : onClearPressed,
        ),
      ),
    ];
    return Row(children: children);
  }
}

class _DraftMetaText extends StatelessWidget {
  const _DraftMetaText({
    required this.value,
    this.accent,
  });

  final String value;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final Color effectiveAccent =
        accent ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Text(
      value,
      textAlign: TextAlign.right,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: effectiveAccent,
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

class _LocalDraftForm {
  const _LocalDraftForm({
    required this.number,
    required this.formState,
    required this.isGroupMode,
    required this.isDoubleMode,
    this.persistedDraftFormId,
    this.persistedDraftBundleId,
  });

  final int number;
  final LotteryFormState formState;
  final bool isGroupMode;
  final bool isDoubleMode;
  final String? persistedDraftFormId;
  final String? persistedDraftBundleId;

  _LocalDraftForm copyWith({
    int? number,
    LotteryFormState? formState,
    bool? isGroupMode,
    bool? isDoubleMode,
    String? persistedDraftFormId,
    String? persistedDraftBundleId,
    bool clearPersistedDraftFormId = false,
    bool clearPersistedDraftBundleId = false,
  }) {
    return _LocalDraftForm(
      number: number ?? this.number,
      formState: formState ?? this.formState,
      isGroupMode: isGroupMode ?? this.isGroupMode,
      isDoubleMode: isDoubleMode ?? this.isDoubleMode,
      persistedDraftFormId: clearPersistedDraftFormId
          ? null
          : (persistedDraftFormId ?? this.persistedDraftFormId),
      persistedDraftBundleId: clearPersistedDraftBundleId
          ? null
          : (persistedDraftBundleId ?? this.persistedDraftBundleId),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.metrics,
    required this.label,
    required this.icon,
    this.onTap,
  });

  final _FormPageLayoutMetrics metrics;
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: metrics.secondaryButtonHeight,
          padding:
              EdgeInsets.symmetric(horizontal: metrics.actionHorizontalPadding),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20),
              SizedBox(width: metrics.actionLabelSpacing),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LotteryRowCard extends StatefulWidget {
  const _LotteryRowCard({
    super.key,
    required this.table,
    required this.isActive,
    required this.isEnabled,
    required this.isGapTarget,
    required this.onTap,
    required this.onSwipeRight,
    required this.onSwipeLeft,
  });

  final LotteryTable table;
  final bool isActive;
  final bool isEnabled;
  final bool isGapTarget;
  final VoidCallback onTap;
  final VoidCallback onSwipeRight;
  final VoidCallback onSwipeLeft;

  @override
  State<_LotteryRowCard> createState() => _LotteryRowCardState();
}

class _LotteryRowCardState extends State<_LotteryRowCard>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _shakeController;
  late final AnimationController _completionController;
  late final Animation<double> _pulseAnimation;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _shakeOffsetAnimation;
  late final Animation<double> _completionAnimation;
  double _dragOffset = 0;
  bool _thresholdReached = false;
  _SwipeActionVisual _completionAction = _SwipeActionVisual.none;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    );
    _scaleAnimation = Tween<double>(
      begin: 1,
      end: 1.02,
    ).animate(_pulseAnimation);
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _shakeOffsetAnimation = TweenSequence<double>([
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0, end: 3)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 3, end: -3)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: -3, end: 2)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 2, end: 0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
    ]).animate(_shakeController);
    _completionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _completionAnimation = CurvedAnimation(
      parent: _completionController,
      curve: Curves.easeOutCubic,
    );
    _syncAnimationWithActiveState();
  }

  @override
  void didUpdateWidget(covariant _LotteryRowCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      _syncAnimationWithActiveState();
      if (!oldWidget.isActive && widget.isActive) {
        _triggerFocusShake();
      }
    }
  }

  void _syncAnimationWithActiveState() {
    if (widget.isActive) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  void _triggerFocusShake() {
    _shakeController
      ..stop()
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _shakeController.dispose();
    _completionController.dispose();
    super.dispose();
  }

  double _previewThresholdForWidth(double width) {
    return _safeClamp(width * 0.22, 56, 88);
  }

  double _commitThresholdForWidth(double width) {
    return _safeClamp(width * 0.34, 92, 132);
  }

  void _updateDragOffset(double delta, double maxExtent) {
    final double nextOffset =
        (_dragOffset + delta).clamp(-maxExtent, maxExtent);
    final double threshold = _previewThresholdForWidth(maxExtent);
    final bool nextThresholdReached = nextOffset.abs() >= threshold;
    if (nextThresholdReached && !_thresholdReached) {
      HapticFeedback.lightImpact();
    }
    setState(() {
      _dragOffset = nextOffset;
      _thresholdReached = nextThresholdReached;
    });
  }

  Future<void> _triggerSwipeAction(
    _SwipeActionVisual action,
    VoidCallback callback,
  ) async {
    HapticFeedback.selectionClick();
    setState(() {
      _completionAction = action;
      _dragOffset = 0;
      _thresholdReached = false;
    });
    await _completionController.forward(from: 0);
    callback();
    if (!mounted) {
      return;
    }
    setState(() => _completionAction = _SwipeActionVisual.none);
  }

  Future<void> _handleHorizontalDragEnd(
    DragEndDetails details,
    double width,
  ) async {
    final double velocity = details.primaryVelocity ?? 0;
    final double commitThreshold = _commitThresholdForWidth(width);
    final bool triggerRight =
        _dragOffset >= commitThreshold || (velocity > 900 && _dragOffset > 24);
    final bool triggerLeft = _dragOffset <= -commitThreshold ||
        (velocity < -900 && _dragOffset < -24);

    if (triggerRight) {
      await _triggerSwipeAction(
          _SwipeActionVisual.lottomat, widget.onSwipeRight);
      return;
    }
    if (triggerLeft) {
      await _triggerSwipeAction(_SwipeActionVisual.clear, widget.onSwipeLeft);
      return;
    }

    setState(() {
      _dragOffset = 0;
      _thresholdReached = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final ThemeData theme = Theme.of(context);
    final Color rowBackground = widget.isActive
        ? (isDark ? const Color(0xFF243B4E) : const Color(0xFFCAE7FF))
        : theme.colorScheme.surfaceContainerHighest;
    final Color gapHighlightColor = theme.colorScheme.primary;
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        _pulseController,
        _shakeController,
        _completionController,
      ]),
      builder: (context, child) {
        final double pulseValue = _pulseAnimation.value;
        final Color activeBorderColor = theme.colorScheme.primary.withValues(
          alpha: 0.72 + (pulseValue * 0.28),
        );
        final List<BoxShadow>? activeGlow = widget.isActive
            ? <BoxShadow>[
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(
                    alpha: 0.12 + (pulseValue * 0.10),
                  ),
                  blurRadius: 10 + (pulseValue * 6),
                  spreadRadius: 0.4 + (pulseValue * 0.8),
                ),
              ]
            : null;
        final double completionValue = _completionAnimation.value;
        final Color completionOverlayColor = switch (_completionAction) {
          _SwipeActionVisual.lottomat => const Color(0xFFFFE94C)
              .withValues(alpha: 0.24 * (1 - completionValue)),
          _SwipeActionVisual.clear => theme.colorScheme.errorContainer
              .withValues(alpha: 0.22 * (1 - completionValue)),
          _SwipeActionVisual.none => Colors.transparent,
        };

        return Transform.scale(
          scale: (widget.isActive ? _scaleAnimation.value : 1) +
              (_completionAction == _SwipeActionVisual.none
                  ? 0
                  : (0.008 * (1 - completionValue))),
          child: Transform.translate(
            offset: Offset(
              widget.isActive ? _shakeOffsetAnimation.value : 0,
              0,
            ),
            child: Opacity(
              opacity: widget.isEnabled ? 1 : 0.45,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final bool isNarrow = constraints.maxWidth < 380;
                  final double rowHeight = isNarrow ? 40 : 46;
                  final double labelWidth = isNarrow
                      ? _safeClamp(
                          constraints.maxWidth * 0.17,
                          52,
                          64,
                        )
                      : 68;
                  final double strongWidth = isNarrow
                      ? _safeClamp(
                          constraints.maxWidth * 0.095,
                          28,
                          34,
                        )
                      : 36;
                  final double cellGap = isNarrow ? 2 : 3;
                  final double maxSwipeExtent = constraints.maxWidth * 0.38;
                  final double previewThreshold =
                      _previewThresholdForWidth(constraints.maxWidth);
                  final double commitThreshold =
                      _commitThresholdForWidth(constraints.maxWidth);
                  final _SwipeActionVisual swipeVisual = _dragOffset > 0
                      ? _SwipeActionVisual.lottomat
                      : _dragOffset < 0
                          ? _SwipeActionVisual.clear
                          : _SwipeActionVisual.none;
                  final double swipeProgress = _dragOffset == 0
                      ? 0
                      : (_dragOffset.abs() / maxSwipeExtent).clamp(0, 1);
                  final bool armed = _dragOffset.abs() >= previewThreshold;
                  final bool readyToCommit =
                      _dragOffset.abs() >= commitThreshold;

                  return Stack(
                    children: [
                      Positioned.fill(
                        child: _SwipeActionBackground(
                          action: swipeVisual,
                          progress: swipeProgress,
                          armed: armed,
                          readyToCommit: readyToCommit,
                          completionAction: _completionAction,
                        ),
                      ),
                      Transform.translate(
                        offset: Offset(_dragOffset, 0),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragStart: widget.isEnabled
                              ? (_) {
                                  setState(() {
                                    _dragOffset = 0;
                                    _thresholdReached = false;
                                  });
                                }
                              : null,
                          onHorizontalDragUpdate: widget.isEnabled
                              ? (details) => _updateDragOffset(
                                    details.primaryDelta ?? 0,
                                    maxSwipeExtent,
                                  )
                              : null,
                          onHorizontalDragEnd: widget.isEnabled
                              ? (details) => _handleHorizontalDragEnd(
                                    details,
                                    constraints.maxWidth,
                                  )
                              : null,
                          onHorizontalDragCancel: widget.isEnabled
                              ? () {
                                  setState(() {
                                    _dragOffset = 0;
                                    _thresholdReached = false;
                                  });
                                }
                              : null,
                          child: InkWell(
                            onTap: widget.isEnabled ? widget.onTap : null,
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              height: rowHeight,
                              padding: EdgeInsets.symmetric(
                                horizontal: isNarrow ? 5 : 6,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Color.alphaBlend(
                                  completionOverlayColor,
                                  rowBackground,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: widget.isActive
                                      ? activeBorderColor
                                      : widget.isGapTarget
                                          ? gapHighlightColor.withValues(
                                              alpha: 0.7)
                                          : Colors.transparent,
                                  width: widget.isActive
                                      ? 1.5
                                      : (widget.isGapTarget ? 1.1 : 1.4),
                                ),
                                boxShadow: widget.isActive
                                    ? activeGlow
                                    : widget.isGapTarget
                                        ? [
                                            BoxShadow(
                                              color: gapHighlightColor
                                                  .withValues(alpha: 0.12),
                                              blurRadius: 10,
                                              spreadRadius: 1,
                                            ),
                                          ]
                                        : null,
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: labelWidth,
                                    child: _RowLabel(
                                      text: 'טבלה ${widget.table.tableIndex}',
                                      width: labelWidth,
                                      fontSize: isNarrow ? 13.5 : 15,
                                    ),
                                  ),
                                  SizedBox(width: cellGap + 1),
                                  ...List.generate(
                                    6,
                                    (index) => Expanded(
                                      child: Padding(
                                        padding: EdgeInsets.only(
                                          right: index == 5 ? cellGap : 0,
                                          left: index == 0 ? 0 : cellGap,
                                        ),
                                        child: _LotteryCell(
                                          value: index <
                                                  widget.table.regularNumbers
                                                      .length
                                              ? widget
                                                  .table.regularNumbers[index]
                                              : null,
                                          isStrong: false,
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: cellGap + 1),
                                  SizedBox(
                                    width: strongWidth,
                                    child: _LotteryCell(
                                      value: widget.table.strongNumber,
                                      isStrong: true,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

enum _SwipeActionVisual {
  none,
  lottomat,
  clear,
}

class _SwipeActionBackground extends StatelessWidget {
  const _SwipeActionBackground({
    required this.action,
    required this.progress,
    required this.armed,
    required this.readyToCommit,
    required this.completionAction,
  });

  final _SwipeActionVisual action;
  final double progress;
  final bool armed;
  final bool readyToCommit;
  final _SwipeActionVisual completionAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final _SwipeActionVisual effectiveAction =
        action == _SwipeActionVisual.none ? completionAction : action;
    if (effectiveAction == _SwipeActionVisual.none) {
      return const SizedBox.shrink();
    }
    final bool isLottomat = effectiveAction == _SwipeActionVisual.lottomat;
    final Alignment alignment =
        isLottomat ? Alignment.centerLeft : Alignment.centerRight;
    final EdgeInsetsGeometry padding = isLottomat
        ? const EdgeInsetsDirectional.only(start: 14)
        : const EdgeInsetsDirectional.only(end: 14);
    final Color baseColor =
        isLottomat ? const Color(0xFFFFF5A8) : theme.colorScheme.errorContainer;
    final Color iconColor = isLottomat
        ? const Color(0xFF574400)
        : theme.colorScheme.onErrorContainer;
    final IconData icon =
        isLottomat ? Icons.auto_awesome : Icons.delete_outline;
    final String label = isLottomat
        ? (readyToCommit ? 'שחרר ללוטומט' : (armed ? 'המשך ללוטומט' : 'לוטומט'))
        : (readyToCommit
            ? 'שחרר לניקוי'
            : (armed ? 'המשך לניקוי' : 'נקה טבלה'));

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: isLottomat ? Alignment.centerLeft : Alignment.centerRight,
          end: isLottomat ? Alignment.centerRight : Alignment.centerLeft,
          colors: <Color>[
            baseColor.withValues(alpha: 0.82 * math.max(progress, 0.18)),
            baseColor.withValues(alpha: 0.16 * math.max(progress, 0.12)),
          ],
        ),
      ),
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: padding,
          child: Opacity(
            opacity: _safeClamp(progress * 1.35, 0, 1),
            child: Transform.scale(
              scale: 0.94 + (math.min(progress, 1) * 0.08),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                textDirection:
                    isLottomat ? TextDirection.ltr : TextDirection.rtl,
                children: [
                  Icon(icon, color: iconColor, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: iconColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LotteryKeyboardSheet extends StatefulWidget {
  const _LotteryKeyboardSheet({
    required this.height,
    required this.state,
    required this.visibleTableCount,
  });

  final double height;
  final LotteryFormState state;
  final int visibleTableCount;

  @override
  State<_LotteryKeyboardSheet> createState() => _LotteryKeyboardSheetState();
}

class _LotteryKeyboardSheetState extends State<_LotteryKeyboardSheet> {
  late final PageController _pageController;
  bool _ignoreNextPageChange = false;
  double _dragOffset = 0;
  bool _isDragging = false;
  bool _previewThresholdReached = false;
  bool _commitThresholdReached = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.state.activeRowIndex);
  }

  @override
  void didUpdateWidget(covariant _LotteryKeyboardSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.activeRowIndex != widget.state.activeRowIndex &&
        _pageController.hasClients) {
      _ignoreNextPageChange = true;
      _pageController.jumpToPage(widget.state.activeRowIndex);
      if (_dragOffset != 0 || _isDragging) {
        setState(() {
          _dragOffset = 0;
          _isDragging = false;
          _previewThresholdReached = false;
          _commitThresholdReached = false;
        });
      }
    }
  }

  double _maxPullForWidth(double width) {
    return _safeClamp(width * 0.24, 40, 72);
  }

  double _previewThresholdForWidth(double width) {
    return _safeClamp(width * 0.12, 18, 28);
  }

  double _commitThresholdForWidth(double width) {
    return _safeClamp(width * 0.16, 28, 46);
  }

  void _updateKeyboardPull(double delta, double width) {
    final double maxPull = _maxPullForWidth(width);
    final double nextOffset = (_dragOffset + delta).clamp(-maxPull, maxPull);
    final double previewThreshold = _previewThresholdForWidth(width);
    final double commitThreshold = _commitThresholdForWidth(width);
    final bool nextPreviewReached = nextOffset.abs() >= previewThreshold;
    final bool nextCommitReached = nextOffset.abs() >= commitThreshold;
    if (nextPreviewReached && !_previewThresholdReached) {
      HapticFeedback.selectionClick();
    }
    if (nextCommitReached && !_commitThresholdReached) {
      HapticFeedback.lightImpact();
    }
    setState(() {
      _dragOffset = nextOffset;
      _previewThresholdReached = nextPreviewReached;
      _commitThresholdReached = nextCommitReached;
    });
  }

  Future<void> _handleKeyboardPullEnd(
    LotteryFormCubit cubit,
    DragEndDetails details,
    double width,
  ) async {
    final double velocity = details.primaryVelocity ?? 0;
    final bool wantsNext = _dragOffset < 0;
    final bool canTransition =
        wantsNext ? cubit.canSwipeToNextRow() : cubit.canSwipeToPreviousRow();
    final double commitThreshold = _commitThresholdForWidth(width);
    final bool shouldCommit = _dragOffset.abs() >= commitThreshold ||
        (velocity.abs() > 520 && _dragOffset.abs() > 10);

    if (shouldCommit && canTransition) {
      HapticFeedback.selectionClick();
      if (wantsNext) {
        cubit.swipeToNextRow();
      } else {
        cubit.swipeToPreviousRow();
      }
    }

    setState(() {
      _dragOffset = 0;
      _isDragging = false;
      _previewThresholdReached = false;
      _commitThresholdReached = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final LotteryFormCubit cubit = context.read<LotteryFormCubit>();
    final double effectiveHeight = widget.height;
    final double verticalPadding =
        _safeClamp(effectiveHeight * 0.016, 2.0, 6.0);

    return Material(
      elevation: 18,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      color: Theme.of(context).colorScheme.surface,
      child: Container(
        height: effectiveHeight,
        padding: EdgeInsets.fromLTRB(0, verticalPadding, 0, verticalPadding),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double maxPull = _maxPullForWidth(constraints.maxWidth);
            final double pullProgress =
                (_dragOffset.abs() / maxPull).clamp(0, 1);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) {
                setState(() {
                  _isDragging = true;
                  _dragOffset = 0;
                  _previewThresholdReached = false;
                  _commitThresholdReached = false;
                });
              },
              onHorizontalDragUpdate: (details) {
                _updateKeyboardPull(
                  details.primaryDelta ?? 0,
                  constraints.maxWidth,
                );
              },
              onHorizontalDragEnd: (details) =>
                  _handleKeyboardPullEnd(cubit, details, constraints.maxWidth),
              onHorizontalDragCancel: () {
                setState(() {
                  _dragOffset = 0;
                  _isDragging = false;
                  _previewThresholdReached = false;
                  _commitThresholdReached = false;
                });
              },
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: _dragOffset),
                duration: _isDragging
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                builder: (context, animatedOffset, child) {
                  return Transform.translate(
                    offset: Offset(animatedOffset, 0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        boxShadow: pullProgress > 0
                            ? <BoxShadow>[
                                BoxShadow(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(
                                          alpha: 0.06 + (pullProgress * 0.06)),
                                  blurRadius: 8 + (pullProgress * 6),
                                  spreadRadius: pullProgress * 0.5,
                                ),
                              ]
                            : null,
                      ),
                      child: child,
                    ),
                  );
                },
                child: PageView.builder(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: widget.visibleTableCount,
                  onPageChanged: (index) {
                    if (_ignoreNextPageChange) {
                      _ignoreNextPageChange = false;
                      return;
                    }
                    cubit.handleKeyboardPageChanged(index);
                  },
                  itemBuilder: (context, index) {
                    return _LotteryKeyboardPage(
                      table: widget.state.form.tables[index],
                      isActive: index == widget.state.activeRowIndex,
                      rowLabelWidth: LotteryFormPage.rowLabelWidth,
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LotteryKeyboardPage extends StatelessWidget {
  const _LotteryKeyboardPage({
    required this.table,
    required this.isActive,
    required this.rowLabelWidth,
  });

  final LotteryTable table;
  final bool isActive;
  final double rowLabelWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double verticalGap = _safeClamp(
          constraints.maxHeight * 0.022,
          2.0,
          8.0,
        );
        final double horizontalGap = _safeClamp(
          constraints.maxWidth * 0.014,
          3.0,
          8.0,
        );
        const double dividerHeight = 1;
        final double horizontalInset =
            _safeClamp(constraints.maxWidth * 0.012, 3.0, 8.0);
        final double rowHeight =
            ((constraints.maxHeight - (verticalGap * 5) - dividerHeight) / 5)
                .clamp(32.0, 56.0);
        final double innerWidth = math.max(
          0,
          constraints.maxWidth - (horizontalInset * 2),
        );
        final double columnWidth = math.max(
          0,
          (innerWidth - (horizontalGap * 9)) / 10,
        );
        final double keyDiameter = math.max(
          22,
          math.min(rowHeight, columnWidth),
        );
        final double leftLabelWidth = (columnWidth * 3) + (horizontalGap * 2);
        final double strongLabelWidth = leftLabelWidth;

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalInset),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Column(
              children: [
                SizedBox(
                  height: rowHeight,
                  child: Row(
                    children: [
                      SizedBox(
                        width: leftLabelWidth,
                        child: _RowLabel(
                          text: 'טבלה ${table.tableIndex}',
                        ),
                      ),
                      SizedBox(width: horizontalGap),
                      Expanded(
                        child: _ResponsiveKeyboardRow(
                          numbers: List<int>.generate(7, (index) => index + 1),
                          rowHeight: rowHeight,
                          gap: horizontalGap,
                          keyDiameter: keyDiameter,
                          table: table,
                          isActive: isActive,
                        ),
                      )
                    ],
                  ),
                ),
                SizedBox(height: verticalGap),
                _ResponsiveKeyboardRow(
                  numbers: List<int>.generate(10, (index) => index + 8),
                  rowHeight: rowHeight,
                  gap: horizontalGap,
                  keyDiameter: keyDiameter,
                  table: table,
                  isActive: isActive,
                ),
                SizedBox(height: verticalGap),
                _ResponsiveKeyboardRow(
                  numbers: List<int>.generate(10, (index) => index + 18),
                  rowHeight: rowHeight,
                  gap: horizontalGap,
                  keyDiameter: keyDiameter,
                  table: table,
                  isActive: isActive,
                ),
                SizedBox(height: verticalGap),
                _ResponsiveKeyboardRow(
                  numbers: List<int>.generate(10, (index) => index + 28),
                  rowHeight: rowHeight,
                  gap: horizontalGap,
                  keyDiameter: keyDiameter,
                  table: table,
                  isActive: isActive,
                ),
                SizedBox(height: verticalGap),
                Divider(
                  color: Theme.of(context).dividerColor,
                  height: dividerHeight,
                ),
                SizedBox(height: verticalGap),
                SizedBox(
                  height: rowHeight,
                  child: Row(
                    children: [
                      SizedBox(
                        width: (columnWidth * 7) + (horizontalGap * 6),
                        child: _ResponsiveStrongRow(
                          rowHeight: rowHeight,
                          gap: horizontalGap,
                          keyDiameter: keyDiameter,
                          table: table,
                          isActive: isActive,
                        ),
                      ),
                      SizedBox(width: horizontalGap),
                      SizedBox(
                        width: strongLabelWidth,
                        child: Container(
                          height: rowHeight,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF235),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                'המספר החזק',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

double _safeClamp(double value, double min, double max) {
  final double lower = min <= max ? min : max;
  final double upper = max >= min ? max : min;
  if (!value.isFinite) {
    return lower;
  }
  return value.clamp(lower, upper).toDouble();
}

class _ResponsiveKeyboardRow extends StatelessWidget {
  const _ResponsiveKeyboardRow({
    required this.numbers,
    required this.rowHeight,
    required this.gap,
    required this.keyDiameter,
    required this.table,
    required this.isActive,
  });

  final List<int> numbers;
  final double rowHeight;
  final double gap;
  final double keyDiameter;
  final LotteryTable table;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: rowHeight,
      child: Row(
        children: _buildResponsiveKeyCells(
          context: context,
          numbers: numbers,
          rowHeight: rowHeight,
          gap: gap,
          keyDiameter: keyDiameter,
          selectedCheck: (number) => table.regularNumbers.contains(number),
          enabledCheck: (number) =>
              isActive &&
              (table.regularNumbers.length < 6 ||
                  table.regularNumbers.contains(number)),
          onPressed: (number) =>
              context.read<LotteryFormCubit>().toggleRegularNumber(number),
        ),
      ),
    );
  }
}

class _ResponsiveStrongRow extends StatelessWidget {
  const _ResponsiveStrongRow({
    required this.rowHeight,
    required this.gap,
    required this.keyDiameter,
    required this.table,
    required this.isActive,
  });

  final double rowHeight;
  final double gap;
  final double keyDiameter;
  final LotteryTable table;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: rowHeight,
      child: Row(
        children: _buildResponsiveKeyCells(
          context: context,
          numbers: List<int>.generate(7, (index) => index + 1),
          rowHeight: rowHeight,
          gap: gap,
          keyDiameter: keyDiameter,
          selectedCheck: (number) => table.strongNumber == number,
          enabledCheck: (number) =>
              isActive && table.regularNumbers.length == 6,
          onPressed: (number) =>
              context.read<LotteryFormCubit>().toggleStrongNumber(number),
        ),
      ),
    );
  }
}

List<Widget> _buildResponsiveKeyCells({
  required BuildContext context,
  required List<int> numbers,
  required double rowHeight,
  required double gap,
  required double keyDiameter,
  required bool Function(int number) selectedCheck,
  required bool Function(int number) enabledCheck,
  required ValueChanged<int> onPressed,
}) {
  return List<Widget>.generate(numbers.length, (index) {
    return Expanded(
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          end: index == numbers.length - 1 ? 0 : gap,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double slotSize = math.min(
              keyDiameter,
              math.min(constraints.maxWidth, rowHeight),
            );
            return Align(
              alignment: Alignment.center,
              child: _NumberKey(
                label: '${numbers[index]}',
                size: slotSize,
                selected: selectedCheck(numbers[index]),
                enabled: enabledCheck(numbers[index]),
                onPressed: () => onPressed(numbers[index]),
              ),
            );
          },
        ),
      ),
    );
  });
}

class _NumberKey extends StatelessWidget {
  const _NumberKey({
    required this.label,
    required this.size,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final double size;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color background = selected
        ? const Color(0xFFFFE94C)
        : enabled
            ? Theme.of(context).colorScheme.surface
            : (isDark ? const Color(0xFF323340) : const Color(0xFFE3E5EB));

    final Color foreground = selected
        ? Colors.black
        : enabled
            ? Theme.of(context).colorScheme.onSurface
            : Colors.grey;

    return SizedBox(
      width: size,
      height: size,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: EdgeInsets.zero,
          backgroundColor: background,
          foregroundColor: foreground,
          side: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 1.2,
          ),
          shape: const CircleBorder(),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: size * 0.3,
          ),
        ),
      ),
    );
  }
}

class _RowLabel extends StatelessWidget {
  const _RowLabel({
    required this.text,
    this.width = LotteryFormPage.rowLabelWidth,
    this.fontSize = 16,
  });

  final String text;
  final double width;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
        ).copyWith(
          fontSize: fontSize,
        ),
      ),
    );
  }
}

class _LotteryCell extends StatelessWidget {
  const _LotteryCell({
    required this.value,
    required this.isStrong,
  });

  final int? value;
  final bool isStrong;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final double height = constraints.maxHeight;
        final double fontSize = _safeClamp(
          math.min(width, height) * 0.45,
          10,
          17,
        );
        return Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isStrong ? const Color(0xFFDCCB59) : const Color(0xFFE91E63),
            borderRadius: BorderRadius.circular(width < 28 ? 8 : 10),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Text(
                value?.toString() ?? '',
                style: TextStyle(
                  color: isStrong ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: fontSize,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
