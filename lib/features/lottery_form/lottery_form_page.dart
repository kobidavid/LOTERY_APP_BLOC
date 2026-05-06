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
import '../form_presentation_utils.dart';
import '../history/personal_form_details_page.dart';
import '../history/personal_submission_bundle_details_page.dart';
import '../payments/payment_options_page.dart';
import 'group_details_page.dart';
import 'lottery_form_cubit.dart';
import 'lottery_form_state.dart';

enum _PersonalDraftMode {
  newForm,
  editingDraft,
  savedCurrentSessionDraft,
}

class LotteryFormPage extends StatefulWidget {
  const LotteryFormPage({
    super.key,
    required this.inviteLinkService,
    required this.onOpenMyForms,
    required this.onOpenActiveForms,
    required this.onOpenDraftForms,
    this.displayName,
    this.dashboardFocusVersion = 0,
    this.personalDraftLoadRequest,
    this.personalDraftLoadVersion = 0,
    this.personalDraftDeletedNotice,
    this.personalDraftDeletedVersion = 0,
  });

  static const double rowLabelWidth = 98;
  final GroupInviteLinkService inviteLinkService;
  final VoidCallback onOpenMyForms;
  final VoidCallback onOpenActiveForms;
  final VoidCallback onOpenDraftForms;
  final String? displayName;
  final int dashboardFocusVersion;
  final PersonalDraftLoadRequest? personalDraftLoadRequest;
  final int personalDraftLoadVersion;
  final PersonalDraftDeletionNotice? personalDraftDeletedNotice;
  final int personalDraftDeletedVersion;

  @override
  State<LotteryFormPage> createState() => _LotteryFormPageState();
}

class PersonalDraftLoadRequest {
  const PersonalDraftLoadRequest({
    required this.entries,
  });

  final List<PersonalSavedDraftEntry> entries;
}

class PersonalDraftDeletionNotice {
  const PersonalDraftDeletionNotice({
    this.formId,
    this.bundleId,
  });

  final String? formId;
  final String? bundleId;
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
  bool _showDashboard = true;
  bool _isKeyboardVisible = false;
  int _draftTabTransitionDirection = 0;
  final List<_LocalDraftForm> _localDrafts = <_LocalDraftForm>[];
  int _activeDraftIndex = 0;
  int _nextDraftNumber = 2;
  int _lastRegularSelectedTableCount = 14;
  int _lastDoubleSelectedTableCount = 10;
  _PersonalDraftMode _personalDraftMode = _PersonalDraftMode.newForm;
  int? _lastAutoScrolledActiveRowIndex;
  int? _lastAutoScrolledSelectedTableCount;
  Timer? _personalDraftPersistDebounce;
  bool _isPersonalPaymentFlowInProgress = false;

  @override
  void didUpdateWidget(covariant LotteryFormPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.dashboardFocusVersion != oldWidget.dashboardFocusVersion) {
      setState(() {
        _showDashboard = true;
      });
    }
    if (widget.personalDraftLoadVersion != oldWidget.personalDraftLoadVersion &&
        widget.personalDraftLoadRequest != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _showDashboard = false;
        });
        unawaited(_loadPersonalDraftRequest(widget.personalDraftLoadRequest!));
      });
    }
    if (widget.personalDraftDeletedVersion !=
            oldWidget.personalDraftDeletedVersion &&
        widget.personalDraftDeletedNotice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _handleDeletedPersonalDraftNotice(widget.personalDraftDeletedNotice!);
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

  String _personalDraftModeValue(_PersonalDraftMode mode) {
    switch (mode) {
      case _PersonalDraftMode.newForm:
        return 'newFormMode';
      case _PersonalDraftMode.editingDraft:
        return 'editingDraftMode';
      case _PersonalDraftMode.savedCurrentSessionDraft:
        return 'savedCurrentSessionDraftMode';
    }
  }

  String _personalDraftSaveButtonLabel() {
    switch (_personalDraftMode) {
      case _PersonalDraftMode.newForm:
        return 'שמור כטיוטה חדשה';
      case _PersonalDraftMode.editingDraft:
      case _PersonalDraftMode.savedCurrentSessionDraft:
        return 'עדכן טיוטה';
    }
  }

  void _setPersonalDraftMode(
    _PersonalDraftMode mode, {
    required String reason,
  }) {
    if (_personalDraftMode == mode) {
      return;
    }
    _personalDraftMode = mode;
    debugPrint(
      '[DraftsDebug] draftMode mode=${_personalDraftModeValue(mode)} draftId=${_currentPersistedDraftFormId() ?? 'null'} bundleId=${_currentPersistedDraftBundleId() ?? 'null'} formId=${context.read<LotteryFormCubit>().state.form.formId ?? 'null'} draftCount=${_localDrafts.length} action=update reason=$reason',
    );
  }

  String? _currentPersistedDraftFormId() {
    if (_localDrafts.isEmpty) {
      return null;
    }
    final String? formId = _localDrafts[_activeDraftIndex].persistedDraftFormId;
    return formId?.trim().isNotEmpty == true ? formId!.trim() : null;
  }

  String? _currentPersistedDraftBundleId() {
    if (_localDrafts.isEmpty) {
      return null;
    }
    final String? bundleId =
        _localDrafts[_activeDraftIndex].persistedDraftBundleId;
    return bundleId?.trim().isNotEmpty == true ? bundleId!.trim() : null;
  }

  void _syncActiveDraftSnapshot(LotteryFormState state) {
    _ensureInitialDraftRegistered(state);
    final bool keepPersistedIds =
        _personalDraftMode != _PersonalDraftMode.newForm;
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

  void _openDashboard() {
    setState(() {
      _showDashboard = true;
      _isKeyboardVisible = false;
    });
  }

  void _openWorkspaceForMode(bool nextIsGroupMode) {
    final LotteryFormState state = context.read<LotteryFormCubit>().state;
    if (_canChangeDraftGroupMode(
      nextIsGroupMode: nextIsGroupMode,
      state: state,
    )) {
      setState(() {
        _showDashboard = false;
        _isKeyboardVisible = false;
        _isGroupMode = nextIsGroupMode;
        _syncActiveDraftSnapshot(state);
      });
      return;
    }
    _showDraftMixingMessage();
  }

  Future<void> _openPersonalDraftFromDashboard(
    PersonalSavedDraftEntry entry,
  ) async {
    setState(() {
      _showDashboard = false;
      _isKeyboardVisible = false;
    });
    await _loadPersonalDraftRequest(
      PersonalDraftLoadRequest(entries: <PersonalSavedDraftEntry>[entry]),
      mode: _PersonalDraftMode.editingDraft,
    );
  }

  Future<void> _openPersonalDraftBundleFromDashboard(
    List<PersonalSavedDraftEntry> entries,
  ) async {
    setState(() {
      _showDashboard = false;
      _isKeyboardVisible = false;
    });
    await _loadPersonalDraftRequest(
      PersonalDraftLoadRequest(entries: entries),
      mode: _PersonalDraftMode.editingDraft,
    );
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
      _draftTabTransitionDirection = 1;
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
    final int previousIndex = _activeDraftIndex;
    setState(() {
      _draftTabTransitionDirection =
          index == previousIndex ? 0 : (index > previousIndex ? 1 : -1);
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
        _personalDraftMode = _PersonalDraftMode.newForm;
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
      _draftTabTransitionDirection = deletedActiveDraft ? -1 : 0;
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
      final bool keepPersistedIds =
          _personalDraftMode != _PersonalDraftMode.newForm;
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
    return _paymentRepository.calculateTicketCost(
      selectedTables,
      isDoubleMode: draft.isDoubleMode,
    );
  }

  num _calculateDraftsTotalCost(List<_LocalDraftForm> drafts) {
    return drafts.fold<num>(
      0,
      (num total, _LocalDraftForm draft) => total + _calculateDraftCost(draft),
    );
  }

  num _calculateActiveWorkspaceCost(LotteryFormState state) {
    final List<LotteryTable> selectedTables =
        state.form.tables.take(state.selectedTableCount).toList();
    return _paymentRepository.calculateTicketCost(
      selectedTables,
      isDoubleMode: _isDoubleMode,
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
    PersonalDraftLoadRequest request, {
    _PersonalDraftMode mode = _PersonalDraftMode.editingDraft,
  }) async {
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
      _draftTabTransitionDirection = 0;
      _activeDraftIndex = 0;
      _nextDraftNumber = loadedDrafts.length + 1;
      _isGroupMode = false;
      _isDoubleMode = loadedDrafts.first.isDoubleMode;
      _isPersonalPaymentFlowInProgress = false;
      _personalDraftMode = mode;
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
    debugPrint(
      '[DraftsDebug] draftMode mode=${_personalDraftModeValue(mode)} draftId=${loadedDrafts.first.persistedDraftFormId ?? 'null'} bundleId=${loadedDrafts.first.persistedDraftBundleId ?? 'null'} formId=${loadedDrafts.first.formState.form.formId ?? 'null'} draftCount=${loadedDrafts.length} action=update reason=loadPersonalDraft',
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
    debugPrint(
      '[DraftsDebug] draftMode mode=${_personalDraftModeValue(_PersonalDraftMode.newForm)} draftId=${formId ?? 'null'} bundleId=${bundleId ?? 'null'} formId=${currentState.form.formId ?? 'null'} draftCount=${_localDrafts.length} action=delete reason=deleteCurrentDraft',
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

  void _handleDeletedPersonalDraftNotice(PersonalDraftDeletionNotice notice) {
    final String? deletedFormId =
        notice.formId?.trim().isNotEmpty == true ? notice.formId!.trim() : null;
    final String? deletedBundleId = notice.bundleId?.trim().isNotEmpty == true
        ? notice.bundleId!.trim()
        : null;
    bool didUpdate = false;
    int? activeReplacementIndex;
    final List<_LocalDraftForm> nextDrafts =
        List<_LocalDraftForm>.generate(_localDrafts.length, (index) {
      final _LocalDraftForm draft = _localDrafts[index];
      final String? draftFormId =
          draft.persistedDraftFormId?.trim().isNotEmpty == true
              ? draft.persistedDraftFormId!.trim()
              : null;
      final String? draftBundleId =
          draft.persistedDraftBundleId?.trim().isNotEmpty == true
              ? draft.persistedDraftBundleId!.trim()
              : null;
      final bool matchesDeletedDraft =
          (deletedBundleId != null && draftBundleId == deletedBundleId) ||
              (deletedFormId != null && draftFormId == deletedFormId);
      if (!matchesDeletedDraft) {
        return draft;
      }
      didUpdate = true;
      if (index == _activeDraftIndex) {
        activeReplacementIndex = index;
      }
      return draft.copyWith(
        formState: draft.formState.copyWith(
          form: draft.formState.form.copyWith(
            clearId: true,
            clearSubmissionId: true,
            clearSavedAt: true,
            clearSubmittedAt: true,
            status: LotteryFormStatus.draft,
            isEditable: true,
          ),
          isEditingSavedRecord: false,
          clearError: true,
          clearSuccess: true,
        ),
        clearPersistedDraftFormId: true,
        clearPersistedDraftBundleId: true,
      );
    });
    if (!didUpdate) {
      return;
    }
    setState(() {
      _localDrafts
        ..clear()
        ..addAll(nextDrafts);
    });
    if (activeReplacementIndex != null && mounted) {
      context.read<LotteryFormCubit>().loadLocalDraftState(
            nextDrafts[activeReplacementIndex!].formState,
          );
    }
    _setPersonalDraftMode(
      _PersonalDraftMode.newForm,
      reason: 'deletedCurrentDraftIdentity',
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
          _personalDraftMode == _PersonalDraftMode.editingDraft ||
              _personalDraftMode == _PersonalDraftMode.savedCurrentSessionDraft;
      final String? currentDraftId = draft.persistedDraftFormId;
      final String? currentFormId = draft.formState.form.formId;
      final bool shouldCreateNewDraft = !isEditingExistingDraft;
      final bool shouldUpdateExistingDraft = isEditingExistingDraft;
      final int savedDraftCount =
          await _paymentRepository.countSavedPersonalDrafts(
        currentState.form.userId,
      );
      final bool blockedByLimit = shouldCreateNewDraft && savedDraftCount >= 3;
      debugPrint(
        '[DraftsDebug] draftDecision savedDraftCount=$savedDraftCount isEditingExistingDraft=$isEditingExistingDraft currentDraftId=${currentDraftId ?? 'null'} persistedDraftFormId=${draft.persistedDraftFormId ?? 'null'} persistedDraftBundleId=${draft.persistedDraftBundleId ?? 'null'} currentFormId=${currentFormId ?? 'null'} shouldCreateNewDraft=$shouldCreateNewDraft shouldUpdateExistingDraft=$shouldUpdateExistingDraft blockedByLimit=$blockedByLimit',
      );
      debugPrint(
        '[DraftsDebug] draftMode mode=${_personalDraftModeValue(_personalDraftMode)} draftId=${currentDraftId ?? 'null'} bundleId=${draft.persistedDraftBundleId ?? 'null'} formId=${currentFormId ?? 'null'} draftCount=$savedDraftCount action=${blockedByLimit ? 'block' : (shouldCreateNewDraft ? 'create' : 'update')} reason=explicitSaveSingleDraft',
      );
      if (blockedByLimit) {
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
        forceCreateNew: shouldCreateNewDraft,
      );
      if (!mounted) {
        return;
      }
      await _loadPersonalDraftRequest(
        PersonalDraftLoadRequest(entries: <PersonalSavedDraftEntry>[saved]),
        mode: shouldCreateNewDraft
            ? _PersonalDraftMode.savedCurrentSessionDraft
            : _PersonalDraftMode.editingDraft,
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
        _personalDraftMode == _PersonalDraftMode.editingDraft ||
            _personalDraftMode == _PersonalDraftMode.savedCurrentSessionDraft;
    final bool shouldCreateNewDraft = !isEditingExistingDraft;
    final bool shouldUpdateExistingDraft = isEditingExistingDraft;
    final int savedDraftCount =
        await _paymentRepository.countSavedPersonalDrafts(
      currentState.form.userId,
    );
    final bool blockedByLimit = shouldCreateNewDraft && savedDraftCount >= 3;
    debugPrint(
      '[DraftsDebug] draftDecision savedDraftCount=$savedDraftCount isEditingExistingDraft=$isEditingExistingDraft currentDraftId=${existingBundleId ?? 'null'} persistedDraftFormId=${drafts.first.persistedDraftFormId ?? 'null'} persistedDraftBundleId=${drafts.first.persistedDraftBundleId ?? 'null'} currentFormId=${drafts.first.formState.form.formId ?? 'null'} shouldCreateNewDraft=$shouldCreateNewDraft shouldUpdateExistingDraft=$shouldUpdateExistingDraft blockedByLimit=$blockedByLimit',
    );
    debugPrint(
      '[DraftsDebug] draftMode mode=${_personalDraftModeValue(_personalDraftMode)} draftId=${drafts.first.persistedDraftFormId ?? 'null'} bundleId=${existingBundleId ?? 'null'} formId=${drafts.first.formState.form.formId ?? 'null'} draftCount=$savedDraftCount action=${blockedByLimit ? 'block' : (shouldCreateNewDraft ? 'create' : 'update')} reason=explicitSaveBundleDraft',
    );
    if (blockedByLimit) {
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
    debugPrint(
      '[DraftsDebug] explicitSavePersonalDraft start userId=${currentState.form.userId} drafts=${payloads.length} bundleId=${existingBundleId ?? 'new'}',
    );
    final String bundleId = await _paymentRepository.savePersonalDraftBundle(
      userId: currentState.form.userId,
      drafts: payloads,
      existingBundleId: existingBundleId,
      forceCreateNew: shouldCreateNewDraft,
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
      mode: shouldCreateNewDraft
          ? _PersonalDraftMode.savedCurrentSessionDraft
          : _PersonalDraftMode.editingDraft,
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
    _personalDraftMode = _PersonalDraftMode.newForm;
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

    if (_localDrafts.isNotEmpty) {
      setState(() {
        _localDrafts[_activeDraftIndex] =
            _localDrafts[_activeDraftIndex].copyWith(
          clearPersistedDraftFormId: true,
          clearPersistedDraftBundleId: true,
        );
        _personalDraftMode = _PersonalDraftMode.newForm;
      });
    }
    debugPrint(
      '[DraftsDebug] draftMode mode=${_personalDraftModeValue(_PersonalDraftMode.newForm)} draftId=${_currentPersistedDraftFormId() ?? 'null'} bundleId=${_currentPersistedDraftBundleId() ?? 'null'} formId=${context.read<LotteryFormCubit>().state.form.formId ?? 'null'} draftCount=${_localDrafts.length} action=update reason=clearForm',
    );
    context.read<LotteryFormCubit>().clearForm();
  }

  Future<void> _showWorkspaceActionsSheet({
    required bool showSaveDraft,
    required bool showDeleteDraft,
    required String saveDraftLabel,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'פעולות',
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 12),
                  _WorkspaceActionSheetTile(
                    icon: Icons.auto_awesome,
                    label: 'לוטומט מלא',
                    onTap: () {
                      Navigator.of(context).pop();
                      _runFullRandomForm();
                    },
                  ),
                  _WorkspaceActionSheetTile(
                    icon: Icons.auto_fix_high_outlined,
                    label: 'השלם טבלאות ריקות',
                    onTap: () {
                      Navigator.of(context).pop();
                      _completeRemainingTables();
                    },
                  ),
                  _WorkspaceActionSheetTile(
                    icon: Icons.delete_outline,
                    label: 'נקה טופס',
                    onTap: () {
                      Navigator.of(context).pop();
                      _confirmClearForm();
                    },
                  ),
                  if (showSaveDraft)
                    _WorkspaceActionSheetTile(
                      icon: Icons.bookmark_outline,
                      label: saveDraftLabel,
                      onTap: () {
                        Navigator.of(context).pop();
                        _saveExplicitPersonalDraft();
                      },
                    ),
                  if (showDeleteDraft)
                    _WorkspaceActionSheetTile(
                      icon: Icons.delete_sweep_outlined,
                      label: 'מחק טיוטה',
                      destructive: true,
                      onTap: () {
                        Navigator.of(context).pop();
                        _deleteCurrentPersonalDraft();
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _runFullRandomForm() {
    context.read<LotteryFormCubit>().generateFullRandomForm();
  }

  void _completeRemainingTables() {
    context.read<LotteryFormCubit>().completeRemainingTables();
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
    final num formCost = _calculateActiveWorkspaceCost(currentState);

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
    if (_isDoubleMode) {
      _lastDoubleSelectedTableCount = count;
    } else {
      _lastRegularSelectedTableCount = count;
    }
    context.read<LotteryFormCubit>().setSelectedTableCount(count);
  }

  void _handlePlayTypeChanged(bool isDoubleMode) {
    final LotteryFormCubit cubit = context.read<LotteryFormCubit>();
    final LotteryFormState state = cubit.state;
    if (_isDoubleMode == isDoubleMode) {
      return;
    }
    if (_isDoubleMode) {
      _lastDoubleSelectedTableCount = state.selectedTableCount;
    } else {
      _lastRegularSelectedTableCount = state.selectedTableCount;
    }
    final int nextCount = isDoubleMode
        ? _lastDoubleSelectedTableCount.clamp(2, 10)
        : _lastRegularSelectedTableCount.clamp(2, 14);
    setState(() {
      _isDoubleMode = isDoubleMode;
    });
    cubit.setSelectedTableCount(nextCount);
  }

  void _showKeyboard() {
    if (_isKeyboardVisible) {
      return;
    }
    setState(() {
      _isKeyboardVisible = true;
    });
  }

  void _hideKeyboard() {
    if (!_isKeyboardVisible) {
      return;
    }
    setState(() {
      _isKeyboardVisible = false;
    });
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
        final List<_LocalDraftForm> effectiveDrafts = _effectiveLocalDrafts(
          state,
        );
        final num totalWorkspaceCost = _calculateDraftsTotalCost(
          effectiveDrafts,
        );
        final int? firstIncompleteDraftNumber =
            _firstIncompleteDraftNumber(state);
        final bool canPrimarySubmit =
            !state.isBusy && firstIncompleteDraftNumber == null;
        final int? gapRowIndex = state.firstGapRowIndex;
        final Widget screenContent = _showDashboard
            ? _HomeDashboardView(
                key: const ValueKey<String>('dashboard-view'),
                userId: state.form.userId,
                displayName: widget.displayName,
                repository: _paymentRepository,
                groupRepository: _groupRepository,
                inviteLinkService: widget.inviteLinkService,
                onStartPersonal: () => _openWorkspaceForMode(false),
                onStartGroup: () => _openWorkspaceForMode(true),
                onOpenActiveForms: widget.onOpenActiveForms,
                onOpenDraftForms: widget.onOpenDraftForms,
                onOpenPersonalDraft: _openPersonalDraftFromDashboard,
                onOpenPersonalDraftBundle:
                    _openPersonalDraftBundleFromDashboard,
              )
            : MediaQuery.removeViewInsets(
                key: const ValueKey<String>('workspace-view'),
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
                          GestureDetector(
                            onTap: _hideKeyboard,
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: EdgeInsetsDirectional.fromSTEB(
                                10,
                                metrics.topPadding,
                                10,
                                metrics.topBottomPadding,
                              ),
                              child: Column(
                                children: [
                                  _WorkspaceHeader(
                                    title: _isGroupMode
                                        ? 'טופס קבוצתי'
                                        : 'טופס אישי',
                                    onBackPressed: _openDashboard,
                                  ),
                                  SizedBox(height: metrics.sectionGap + 1),
                                  Row(
                                    textDirection: TextDirection.rtl,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      _WorkspaceActionsFab(
                                        onTap: () => _showWorkspaceActionsSheet(
                                          showSaveDraft: !_isGroupMode,
                                          showDeleteDraft: !_isGroupMode &&
                                              _personalDraftMode !=
                                                  _PersonalDraftMode.newForm,
                                          saveDraftLabel:
                                              _personalDraftSaveButtonLabel(),
                                        ),
                                      ),
                                      SizedBox(
                                        width: metrics.sectionGap + 4,
                                      ),
                                      Expanded(
                                        child: _WorkspaceDraftTabs(
                                          drafts: effectiveDrafts,
                                          activeDraftIndex: _activeDraftIndex,
                                          showDeleteOnActive:
                                              effectiveDrafts.length > 1,
                                          onDraftSelected: _switchToLocalDraft,
                                          onAddDraft:
                                              _createAdditionalLocalDraft,
                                          onDeleteActiveDraft:
                                              effectiveDrafts.length > 1
                                                  ? () => _deleteLocalDraft(
                                                        _activeDraftIndex,
                                                      )
                                                  : null,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: metrics.sectionGap + 2),
                                  _CompactControlRow(
                                    metrics: metrics,
                                    isDoubleMode: _isDoubleMode,
                                    selectedTableCount:
                                        state.selectedTableCount,
                                    isBusy: state.isBusy,
                                    onPlayTypeChanged: _handlePlayTypeChanged,
                                    onTableCountChanged:
                                        _handleTableCountChanged,
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
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
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
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              reverseDuration:
                                  const Duration(milliseconds: 200),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, animation) {
                                final Offset begin = Offset(
                                  _draftTabTransitionDirection > 0
                                      ? -0.03
                                      : _draftTabTransitionDirection < 0
                                          ? 0.03
                                          : 0,
                                  0,
                                );
                                return ClipRect(
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: begin,
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: FadeTransition(
                                      opacity: animation,
                                      child: child,
                                    ),
                                  ),
                                );
                              },
                              child: KeyedSubtree(
                                key: ValueKey<int>(_activeDraftIndex),
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10),
                                        child: ListView.separated(
                                          key: _tablesListKey,
                                          controller: _tablesScrollController,
                                          padding:
                                              const EdgeInsets.only(bottom: 8),
                                          itemCount: visibleTables.length,
                                          separatorBuilder: (_, __) =>
                                              SizedBox(height: metrics.listGap),
                                          itemBuilder: (context, index) {
                                            return _LotteryRowCard(
                                              key: _tableRowKeyForIndex(index),
                                              table: visibleTables[index],
                                              isActive:
                                                  index == state.activeRowIndex,
                                              isEnabled: state
                                                  .isRowInteractable(index),
                                              isGapTarget: gapRowIndex == index,
                                              onTap: () {
                                                _showKeyboard();
                                                context
                                                    .read<LotteryFormCubit>()
                                                    .selectRow(index);
                                              },
                                              onSwipeRight: () => context
                                                  .read<LotteryFormCubit>()
                                                  .randomizeSingleTable(index),
                                              onSwipeLeft: () =>
                                                  _confirmClearTable(index),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: _hideKeyboard,
                                      behavior: HitTestBehavior.opaque,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                        ),
                                        child: _WorkspaceFooterBar(
                                          metrics: metrics,
                                          totalPrice:
                                              '${_formatNisAmount(totalWorkspaceCost)} ₪',
                                          primaryLabel: _isGroupMode
                                              ? 'המשך לקבוצה'
                                              : 'המשך לתשלום',
                                          canPrimarySubmit: canPrimarySubmit,
                                          onPrimaryPressed:
                                              _handlePrimarySubmit,
                                        ),
                                      ),
                                    ),
                                    if (_isKeyboardVisible) ...[
                                      SizedBox(
                                        height: metrics.keyboardTopGap,
                                      ),
                                      _LotteryKeyboardSheet(
                                        height: keyboardHeight,
                                        state: state,
                                        visibleTableCount:
                                            state.selectedTableCount,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              );
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          reverseDuration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (currentChild, previousChildren) {
            return ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              ),
            );
          },
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              ),
              child: child,
            );
          },
          child: screenContent,
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

  String get compactDateLabel {
    final String value = (displayDate ?? '').trim();
    return value.isEmpty ? 'תאריך יעדכן בקרוב' : value;
  }

  String get compactPrizeLabel {
    final String doubleLabel = _formatPrize(
      doubleLottoPrize,
      includeUntil: true,
    );
    if (doubleLabel != 'טרם פורסם') {
      return doubleLabel;
    }
    return _formatPrize(regularLottoPrize, includeUntil: true);
  }

  DateTime? get _parsedDisplayDate {
    final String raw = (displayDate ?? '').trim();
    if (raw.isEmpty) {
      return null;
    }
    final RegExpMatch? match = RegExp(
      r'(\d{2})\/(\d{2})\/(\d{2,4})',
    ).firstMatch(raw);
    if (match == null) {
      return null;
    }
    final int? day = int.tryParse(match.group(1)!);
    final int? month = int.tryParse(match.group(2)!);
    final int? yearValue = int.tryParse(match.group(3)!);
    if (day == null || month == null || yearValue == null) {
      return null;
    }
    final int year = yearValue < 100 ? 2000 + yearValue : yearValue;
    return DateTime(year, month, day);
  }

  String get dashboardDayLabel {
    const List<String> weekdayLabels = <String>[
      'יום ב׳',
      'יום ג׳',
      'יום ד׳',
      'יום ה׳',
      'יום ו׳',
      'שבת',
      'יום א׳',
    ];
    final DateTime? parsed = _parsedDisplayDate;
    if (parsed == null) {
      return 'יום --';
    }
    return weekdayLabels[parsed.weekday - 1];
  }

  String get dashboardShortDateLabel {
    final DateTime? parsed = _parsedDisplayDate;
    if (parsed == null) {
      return '--/--/--';
    }
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${twoDigits(parsed.day)}/${twoDigits(parsed.month)}/${(parsed.year % 100).toString().padLeft(2, '0')}';
  }

  String get dashboardPrizeLabel {
    final String source = compactPrizeLabel;
    final String digits = source.replaceAll(RegExp(r'[^0-9]'), '');
    final int? numeric = digits.isEmpty ? null : int.tryParse(digits);
    if (numeric != null && numeric >= 1000000) {
      final double millions = numeric / 1000000;
      final bool hasFraction =
          (millions - millions.truncateToDouble()).abs() > 0.001;
      final String displayMillions = hasFraction
          ? millions.toStringAsFixed(1)
          : millions.toStringAsFixed(0);
      return 'עד $displayMillions מיליון ₪';
    }
    return source;
  }
}

class _CompactControlRow extends StatelessWidget {
  const _CompactControlRow({
    required this.metrics,
    required this.isDoubleMode,
    required this.selectedTableCount,
    required this.isBusy,
    required this.onPlayTypeChanged,
    required this.onTableCountChanged,
  });

  final _FormPageLayoutMetrics metrics;
  final bool isDoubleMode;
  final int selectedTableCount;
  final bool isBusy;
  final ValueChanged<bool> onPlayTypeChanged;
  final ValueChanged<int?> onTableCountChanged;

  @override
  Widget build(BuildContext context) {
    final List<int> availableCounts = isDoubleMode
        ? const <int>[10, 8, 6, 4, 2]
        : const <int>[14, 12, 10, 8, 6, 4, 2];
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 7,
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
          SizedBox(width: metrics.sectionGap + 6),
          Expanded(
            flex: 5,
            child: _CompactFieldShell(
              metrics: metrics,
              child: _CompactTableCountSelector(
                value: selectedTableCount,
                availableCounts: availableCounts,
                enabled: !isBusy,
                onChanged: onTableCountChanged,
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

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({
    required this.title,
    required this.onBackPressed,
  });

  final String title;
  final VoidCallback onBackPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        textDirection: TextDirection.rtl,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          const SizedBox(width: 10),
          IconButton.filledTonal(
            onPressed: onBackPressed,
            icon: const Icon(Icons.arrow_forward_rounded),
            tooltip: 'חזרה לדשבורד',
            style: IconButton.styleFrom(
              foregroundColor: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceDraftTabs extends StatelessWidget {
  const _WorkspaceDraftTabs({
    required this.drafts,
    required this.activeDraftIndex,
    required this.onDraftSelected,
    required this.onAddDraft,
    this.onDeleteActiveDraft,
    this.showDeleteOnActive = false,
  });

  final List<_LocalDraftForm> drafts;
  final int activeDraftIndex;
  final ValueChanged<int> onDraftSelected;
  final VoidCallback onAddDraft;
  final VoidCallback? onDeleteActiveDraft;
  final bool showDeleteOnActive;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            textDirection: TextDirection.rtl,
            children: [
              ...List<Widget>.generate(drafts.length, (index) {
                final bool isActive = index == activeDraftIndex;
                return Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: index == drafts.length - 1 ? 0 : 8,
                  ),
                  child: _DraftTabChip(
                    label: 'טופס ${drafts[index].number}',
                    isActive: isActive,
                    onTap: () => onDraftSelected(index),
                    onDelete: isActive && showDeleteOnActive
                        ? onDeleteActiveDraft
                        : null,
                  ),
                );
              }),
              const SizedBox(width: 8),
              _DraftTabAddChip(onTap: onAddDraft),
            ],
          ),
        ),
      ),
    );
  }
}

class _DraftTabChip extends StatelessWidget {
  const _DraftTabChip({
    required this.label,
    required this.isActive,
    required this.onTap,
    this.onDelete,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: isActive
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 10, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            textDirection: TextDirection.rtl,
            children: [
              Text(
                label,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: isActive
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurface,
                    ),
              ),
              if (onDelete != null) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: onDelete,
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: isActive
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DraftTabAddChip extends StatelessWidget {
  const _DraftTabAddChip({
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        minimumSize: const Size(0, 34),
        padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 10, 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      child: const Text('+'),
    );
  }
}

class _CompactTableCountSelector extends StatelessWidget {
  const _CompactTableCountSelector({
    required this.value,
    required this.availableCounts,
    required this.enabled,
    required this.onChanged,
  });

  final int value;
  final List<int> availableCounts;
  final bool enabled;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        value: value,
        isExpanded: true,
        alignment: AlignmentDirectional.centerEnd,
        icon: const Icon(Icons.expand_more_rounded),
        borderRadius: BorderRadius.circular(16),
        items: availableCounts
            .map(
              (count) => DropdownMenuItem<int>(
                value: count,
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  '$count טבלאות',
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}

class _WorkspaceFooterBar extends StatelessWidget {
  const _WorkspaceFooterBar({
    required this.metrics,
    required this.totalPrice,
    required this.primaryLabel,
    required this.canPrimarySubmit,
    required this.onPrimaryPressed,
  });

  final _FormPageLayoutMetrics metrics;
  final String totalPrice;
  final String primaryLabel;
  final bool canPrimarySubmit;
  final VoidCallback onPrimaryPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool stack = constraints.maxWidth < 380;
            final Widget priceText = Text(
              'סה״כ: $totalPrice',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            );
            final Widget primaryButton = FilledButton(
              onPressed: canPrimarySubmit ? onPrimaryPressed : null,
              style: FilledButton.styleFrom(
                minimumSize: Size(0, metrics.primaryButtonHeight),
                padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                primaryLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.w900,
                    ),
              ),
            );

            if (stack) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  priceText,
                  const SizedBox(height: 8),
                  primaryButton,
                ],
              );
            }

            return Row(
              textDirection: TextDirection.rtl,
              children: [
                Expanded(child: priceText),
                const SizedBox(width: 12),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 150),
                    child: primaryButton,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WorkspaceActionsFab extends StatelessWidget {
  const _WorkspaceActionsFab({
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHighest,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            Icons.tune_rounded,
            color: colorScheme.onSurface,
            size: 22,
          ),
        ),
      ),
    );
  }
}

class _WorkspaceActionSheetTile extends StatelessWidget {
  const _WorkspaceActionSheetTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color foreground =
        destructive ? colorScheme.error : colorScheme.onSurface;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: foreground),
      title: Text(
        label,
        textAlign: TextAlign.right,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
      ),
      onTap: onTap,
    );
  }
}

class _HomeDashboardView extends StatelessWidget {
  const _HomeDashboardView({
    super.key,
    required this.userId,
    required this.displayName,
    required this.repository,
    required this.groupRepository,
    required this.inviteLinkService,
    required this.onStartPersonal,
    required this.onStartGroup,
    required this.onOpenActiveForms,
    required this.onOpenDraftForms,
    required this.onOpenPersonalDraft,
    required this.onOpenPersonalDraftBundle,
  });

  final String userId;
  final String? displayName;
  final LotteryFormRepository repository;
  final LotteryGroupRepository groupRepository;
  final GroupInviteLinkService inviteLinkService;
  final VoidCallback onStartPersonal;
  final VoidCallback onStartGroup;
  final VoidCallback onOpenActiveForms;
  final VoidCallback onOpenDraftForms;
  final ValueChanged<PersonalSavedDraftEntry> onOpenPersonalDraft;
  final ValueChanged<List<PersonalSavedDraftEntry>> onOpenPersonalDraftBundle;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final String greetingName = (displayName ?? '').trim().isEmpty
        ? 'שלום'
        : 'שלום, ${(displayName ?? '').trim().split(' ').first}';
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: StreamBuilder<List<LotteryForm>>(
          stream: repository.watchSubmittedForms(userId),
          builder: (context, submittedFormsSnapshot) {
            return StreamBuilder<List<PersonalSubmittedBundle>>(
              stream: repository.watchPersonalSubmissionBundles(userId),
              builder: (context, bundlesSnapshot) {
                return StreamBuilder<List<SubmittedGroupHistoryItem>>(
                  stream: groupRepository.watchSubmittedGroupsForUser(userId),
                  builder: (context, submittedGroupsSnapshot) {
                    return StreamBuilder<List<PersonalSavedDraftEntry>>(
                      stream: repository.watchSavedPersonalDraftEntries(userId),
                      builder: (context, draftsSnapshot) {
                        return StreamBuilder<List<UserGroupListItem>>(
                          stream: groupRepository.watchGroupsForUser(userId),
                          builder: (context, groupDraftsSnapshot) {
                            final List<_HomeDashboardItem> activeItems =
                                _buildDashboardActiveItems(
                              submittedForms: submittedFormsSnapshot.data ??
                                  const <LotteryForm>[],
                              bundles: bundlesSnapshot.data ??
                                  const <PersonalSubmittedBundle>[],
                              groups: submittedGroupsSnapshot.data ??
                                  const <SubmittedGroupHistoryItem>[],
                            );
                            final List<_HomeDashboardItem> draftItems =
                                _buildDashboardDraftItems(
                              personalDrafts: draftsSnapshot.data ??
                                  const <PersonalSavedDraftEntry>[],
                              groupDrafts: groupDraftsSnapshot.data ??
                                  const <UserGroupListItem>[],
                            );

                            return CustomScrollView(
                              slivers: [
                                const SliverPersistentHeader(
                                  pinned: true,
                                  delegate: _DashboardLotteryBarDelegate(),
                                ),
                                SliverPadding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    18,
                                    16,
                                    24,
                                  ),
                                  sliver: SliverList(
                                    delegate: SliverChildListDelegate(
                                      [
                                        Text(
                                          greetingName,
                                          textAlign: TextAlign.right,
                                          style: Theme.of(context)
                                              .textTheme
                                              .headlineSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w900,
                                                color: colorScheme.onSurface,
                                              ),
                                        ),
                                        const SizedBox(height: 18),
                                        LayoutBuilder(
                                          builder: (context, constraints) {
                                            final bool stackCards =
                                                constraints.maxWidth < 620;
                                            final Widget personalCard =
                                                _DashboardActionCard(
                                              title: 'טופס אישי',
                                              subtitle:
                                                  'מילוי מהיר של טופס אישי חדש',
                                              icon: Icons.description_outlined,
                                              onTap: onStartPersonal,
                                            );
                                            final Widget groupCard =
                                                _DashboardActionCard(
                                              title: 'טופס קבוצתי',
                                              subtitle:
                                                  'פתיחה או המשך של טופס קבוצתי',
                                              icon: Icons.groups_2_outlined,
                                              onTap: onStartGroup,
                                            );
                                            return stackCards
                                                ? Column(
                                                    children: [
                                                      personalCard,
                                                      const SizedBox(
                                                        height: 12,
                                                      ),
                                                      groupCard,
                                                    ],
                                                  )
                                                : Row(
                                                    children: [
                                                      Expanded(
                                                        child: personalCard,
                                                      ),
                                                      const SizedBox(
                                                        width: 12,
                                                      ),
                                                      Expanded(
                                                        child: groupCard,
                                                      ),
                                                    ],
                                                  );
                                          },
                                        ),
                                        const SizedBox(height: 24),
                                        _DashboardSection(
                                          title: 'טפסים פעילים',
                                          actionLabel: activeItems.isEmpty
                                              ? null
                                              : 'לכל הטפסים הפעילים שלי',
                                          onActionTap: activeItems.isEmpty
                                              ? null
                                              : onOpenActiveForms,
                                          child: activeItems.isEmpty
                                              ? const _DashboardEmptyState(
                                                  text: 'אין כרגע טפסים פעילים',
                                                )
                                              : Column(
                                                  children: activeItems
                                                      .take(3)
                                                      .map(
                                                        (item) => Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .only(
                                                            bottom: 10,
                                                          ),
                                                          child:
                                                              _DashboardPreviewCard(
                                                            item: item,
                                                            onTap: () =>
                                                                _openDashboardItem(
                                                              context,
                                                              item,
                                                            ),
                                                          ),
                                                        ),
                                                      )
                                                      .toList(),
                                                ),
                                        ),
                                        const SizedBox(height: 24),
                                        _DashboardSection(
                                          title: 'טיוטות',
                                          actionLabel: draftItems.isEmpty
                                              ? null
                                              : 'לכל הטיוטות שלי',
                                          onActionTap: draftItems.isEmpty
                                              ? null
                                              : onOpenDraftForms,
                                          child: draftItems.isEmpty
                                              ? const _DashboardEmptyState(
                                                  text:
                                                      'אין כרגע טיוטות פעילות',
                                                )
                                              : Column(
                                                  children: draftItems
                                                      .take(3)
                                                      .map(
                                                        (item) => Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .only(
                                                            bottom: 10,
                                                          ),
                                                          child:
                                                              _DashboardPreviewCard(
                                                            item: item,
                                                            onTap: () =>
                                                                _openDashboardItem(
                                                              context,
                                                              item,
                                                            ),
                                                          ),
                                                        ),
                                                      )
                                                      .toList(),
                                                ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _openDashboardItem(BuildContext context, _HomeDashboardItem item) {
    switch (item.kind) {
      case _HomeDashboardItemKind.personalActive:
        Navigator.of(context).push<void>(
          _buildDashboardSlideRoute(
            child: PersonalFormDetailsPage(
              ownerUserId: userId,
              formId: item.personalForm!.formId!,
              repository: repository,
              title: 'טופס אישי',
            ),
          ),
        );
        return;
      case _HomeDashboardItemKind.personalBundleActive:
        Navigator.of(context).push<void>(
          _buildDashboardSlideRoute(
            child: PersonalSubmissionBundleDetailsPage(
              ownerUserId: userId,
              bundle: item.personalBundle!,
              repository: repository,
            ),
          ),
        );
        return;
      case _HomeDashboardItemKind.groupActive:
      case _HomeDashboardItemKind.groupDraft:
        Navigator.of(context).push<void>(
          _buildDashboardSlideRoute(
            child: GroupDetailsPage(
              groupId: item.groupId!,
              currentUserId: userId,
              inviteLinkService: inviteLinkService,
              repository: groupRepository,
            ),
          ),
        );
        return;
      case _HomeDashboardItemKind.personalDraft:
        onOpenPersonalDraft(item.personalDraftEntry!);
        return;
      case _HomeDashboardItemKind.personalDraftBundle:
        onOpenPersonalDraftBundle(item.personalDraftBundleEntries!);
        return;
    }
  }
}

PageRoute<T> _buildDashboardSlideRoute<T>({
  required Widget child,
}) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => child,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final CurvedAnimation curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(-0.14, 0),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(
          opacity: Tween<double>(
            begin: 0.92,
            end: 1,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _DashboardLotteryInfoCard extends StatefulWidget {
  const _DashboardLotteryInfoCard();

  @override
  State<_DashboardLotteryInfoCard> createState() =>
      _DashboardLotteryInfoCardState();
}

class _DashboardLotteryInfoCardState extends State<_DashboardLotteryInfoCard> {
  late final Future<_UpcomingLotteryMetadata> _metadataFuture;

  @override
  void initState() {
    super.initState();
    _metadataFuture = _loadMetadata();
  }

  Future<_UpcomingLotteryMetadata> _loadMetadata() async {
    final HttpsCallable callable =
        FirebaseFunctions.instanceFor(region: 'us-central1')
            .httpsCallable('getUpcomingLotteryMetadata');
    final HttpsCallableResult<dynamic> result = await callable.call();
    final Map<String, dynamic> data =
        Map<String, dynamic>.from(result.data as Map<dynamic, dynamic>);
    return _UpcomingLotteryMetadata.fromMap(data);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return FutureBuilder<_UpcomingLotteryMetadata>(
      future: _metadataFuture,
      builder: (context, snapshot) {
        final _UpcomingLotteryMetadata? metadata = snapshot.data;
        final String dayLabel = metadata?.dashboardDayLabel ?? 'יום --';
        final String dateLabel =
            metadata?.dashboardShortDateLabel ?? '--/--/--';
        final String amountLabel =
            metadata?.dashboardPrizeLabel ?? 'סכום יעדכן בקרוב';
        return Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.surface.withValues(alpha: 0.96),
            border: Border(
              bottom: BorderSide(color: colorScheme.outlineVariant),
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: RichText(
              textDirection: TextDirection.rtl,
              maxLines: 1,
              overflow: TextOverflow.visible,
              text: TextSpan(
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                    ),
                children: [
                  TextSpan(
                    text: 'הגרלה הקרובה',
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const TextSpan(text: ' · '),
                  TextSpan(text: dayLabel),
                  const TextSpan(text: ' · '),
                  TextSpan(text: dateLabel),
                  const TextSpan(text: ' · '),
                  TextSpan(
                    text: amountLabel,
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DashboardLotteryBarDelegate extends SliverPersistentHeaderDelegate {
  const _DashboardLotteryBarDelegate();

  static const double _height = 58;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: const _DashboardLotteryInfoCard(),
    );
  }

  @override
  bool shouldRebuild(covariant _DashboardLotteryBarDelegate oldDelegate) =>
      false;
}

class _DashboardSection extends StatelessWidget {
  const _DashboardSection({
    required this.title,
    required this.child,
    this.actionLabel,
    this.onActionTap,
  });

  final String title;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onActionTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          textDirection: TextDirection.rtl,
          children: [
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.right,
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            if (actionLabel != null && onActionTap != null)
              TextButton(
                onPressed: onActionTap,
                child: Text(actionLabel!),
              ),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class _DashboardActionCard extends StatelessWidget {
  const _DashboardActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final double textScale = MediaQuery.textScalerOf(context).scale(1);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colorScheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Directionality(
                textDirection: TextDirection.rtl,
                child: Row(
                  textDirection: TextDirection.rtl,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.primary.withValues(alpha: 0.14),
                            blurRadius: 14,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Icon(
                        icon,
                        color: colorScheme.onPrimaryContainer,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Directionality(
                        textDirection: TextDirection.rtl,
                        child: Column(
                          textDirection: TextDirection.rtl,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              textAlign: TextAlign.right,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                              maxLines: textScale > 1.35 ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              textAlign: TextAlign.right,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                              maxLines: textScale > 1.25 ? 3 : 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '←',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DashboardPreviewCard extends StatelessWidget {
  const _DashboardPreviewCard({
    required this.item,
    required this.onTap,
  });

  final _HomeDashboardItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                textDirection: TextDirection.rtl,
                children: [
                  Expanded(
                    child: Text(
                      item.title,
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    item.icon,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...item.rows
                  .map(
                    (row) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _DashboardInfoRow(
                        label: row.label,
                        value: row.value,
                      ),
                    ),
                  )
                  .toList(),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardInfoRow extends StatelessWidget {
  const _DashboardInfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        textDirection: TextDirection.rtl,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label:',
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardEmptyState extends StatelessWidget {
  const _DashboardEmptyState({
    required this.text,
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

enum _HomeDashboardItemKind {
  personalActive,
  personalBundleActive,
  groupActive,
  personalDraft,
  personalDraftBundle,
  groupDraft,
}

class _DashboardRowValue {
  const _DashboardRowValue({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;
}

class _HomeDashboardItem {
  const _HomeDashboardItem({
    required this.kind,
    required this.title,
    required this.rows,
    required this.sortDate,
    required this.icon,
    this.personalForm,
    this.personalBundle,
    this.groupId,
    this.personalDraftEntry,
    this.personalDraftBundleEntries,
  });

  final _HomeDashboardItemKind kind;
  final String title;
  final List<_DashboardRowValue> rows;
  final DateTime sortDate;
  final IconData icon;
  final LotteryForm? personalForm;
  final PersonalSubmittedBundle? personalBundle;
  final String? groupId;
  final PersonalSavedDraftEntry? personalDraftEntry;
  final List<PersonalSavedDraftEntry>? personalDraftBundleEntries;
}

List<_HomeDashboardItem> _buildDashboardActiveItems({
  required List<LotteryForm> submittedForms,
  required List<PersonalSubmittedBundle> bundles,
  required List<SubmittedGroupHistoryItem> groups,
}) {
  final Set<String> bundleIds =
      bundles.map((bundle) => bundle.submissionId).toSet();
  final List<_HomeDashboardItem> items = <_HomeDashboardItem>[
    ...submittedForms
        .where(
          (form) =>
              form.status == LotteryFormStatus.submitted &&
              (form.submissionId == null ||
                  !bundleIds.contains(form.submissionId)) &&
              !_isDashboardPersonalResultPublished(form),
        )
        .map(
          (form) => _HomeDashboardItem(
            kind: _HomeDashboardItemKind.personalActive,
            title: 'טופס אישי',
            rows: <_DashboardRowValue>[
              _DashboardRowValue(
                label: 'סטטוס',
                value: _dashboardPersonalOperationalStatus(form),
              ),
              if (form.salesCloseAt != null)
                _DashboardRowValue(
                  label: 'תאריך הגרלה',
                  value: formatPresentationDateTime(form.salesCloseAt),
                ),
            ],
            sortDate: form.submittedAt ?? form.updatedAt ?? DateTime(0),
            icon: Icons.description_outlined,
            personalForm: form,
          ),
        ),
    ...bundles
        .where((bundle) => !bundle.forms.any(_isDashboardBundleResultPublished))
        .map(
          (bundle) => _HomeDashboardItem(
            kind: _HomeDashboardItemKind.personalBundleActive,
            title: 'שליחת טפסים אישיים',
            rows: <_DashboardRowValue>[
              _DashboardRowValue(
                label: 'סטטוס',
                value: _dashboardPersonalBundleOperationalStatus(bundle),
              ),
              if (bundle.salesCloseAt != null)
                _DashboardRowValue(
                  label: 'תאריך הגרלה',
                  value: formatPresentationDateTime(bundle.salesCloseAt),
                ),
            ],
            sortDate: bundle.submittedAt ?? DateTime(0),
            icon: Icons.layers_outlined,
            personalBundle: bundle,
          ),
        ),
    ...groups.where((group) => group.resultPublishedAt == null).map(
          (group) => _HomeDashboardItem(
            kind: _HomeDashboardItemKind.groupActive,
            title: group.groupName,
            rows: <_DashboardRowValue>[
              _DashboardRowValue(
                label: 'סטטוס',
                value: _dashboardGroupOperationalStatus(group),
              ),
            ],
            sortDate: group.submittedAt ?? DateTime(0),
            icon: Icons.groups_2_outlined,
            groupId: group.groupId,
          ),
        ),
  ]..sort((a, b) => b.sortDate.compareTo(a.sortDate));
  return items;
}

List<_HomeDashboardItem> _buildDashboardDraftItems({
  required List<PersonalSavedDraftEntry> personalDrafts,
  required List<UserGroupListItem> groupDrafts,
}) {
  final Map<String, List<PersonalSavedDraftEntry>> bundleEntries =
      <String, List<PersonalSavedDraftEntry>>{};
  final List<PersonalSavedDraftEntry> standaloneEntries =
      <PersonalSavedDraftEntry>[];
  for (final PersonalSavedDraftEntry entry in personalDrafts) {
    final String? bundleId = entry.draftBundleId;
    if (bundleId == null || bundleId.isEmpty) {
      standaloneEntries.add(entry);
      continue;
    }
    bundleEntries
        .putIfAbsent(bundleId, () => <PersonalSavedDraftEntry>[])
        .add(entry);
  }

  final List<_HomeDashboardItem> items = <_HomeDashboardItem>[
    ...standaloneEntries.map(
      (entry) => _HomeDashboardItem(
        kind: _HomeDashboardItemKind.personalDraft,
        title: 'טופס אישי',
        rows: <_DashboardRowValue>[
          const _DashboardRowValue(label: 'סטטוס', value: 'טיוטה'),
          _DashboardRowValue(label: 'טבלאות', value: '${entry.tableCount}'),
          _DashboardRowValue(
            label: 'עודכן',
            value: formatPresentationDateTime(entry.savedAt ?? entry.updatedAt),
          ),
        ],
        sortDate: entry.sortDate,
        icon: Icons.bookmark_outline,
        personalDraftEntry: entry,
      ),
    ),
    ...bundleEntries.entries.map((entry) {
      final List<PersonalSavedDraftEntry> entries =
          List<PersonalSavedDraftEntry>.from(entry.value)
            ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
      final DateTime updatedAt =
          entries.map((item) => item.savedAt ?? item.updatedAt).fold<DateTime>(
                DateTime.fromMillisecondsSinceEpoch(0),
                (latest, current) => current.isAfter(latest) ? current : latest,
              );
      return _HomeDashboardItem(
        kind: _HomeDashboardItemKind.personalDraftBundle,
        title: 'שליחת טפסים אישיים',
        rows: <_DashboardRowValue>[
          const _DashboardRowValue(label: 'סטטוס', value: 'טיוטה'),
          _DashboardRowValue(label: 'מספר טפסים', value: '${entries.length}'),
          _DashboardRowValue(
            label: 'עודכן',
            value: formatPresentationDateTime(updatedAt),
          ),
        ],
        sortDate: updatedAt,
        icon: Icons.layers_outlined,
        personalDraftBundleEntries: entries,
      );
    }),
    ...groupDrafts
        .where(
          (group) =>
              group.groupStatus != 'submitted' &&
              group.groupStatus != 'cancelled',
        )
        .map(
          (group) => _HomeDashboardItem(
            kind: _HomeDashboardItemKind.groupDraft,
            title: group.groupName,
            rows: <_DashboardRowValue>[
              const _DashboardRowValue(label: 'סטטוס', value: 'בהקמה'),
              _DashboardRowValue(
                label: 'עודכן',
                value: formatPresentationDateTime(group.updatedAt),
              ),
            ],
            sortDate: group.updatedAt ?? DateTime(0),
            icon: Icons.groups_outlined,
            groupId: group.groupId,
          ),
        ),
  ]..sort((a, b) => b.sortDate.compareTo(a.sortDate));

  return items;
}

bool _isDashboardPersonalResultPublished(LotteryForm form) {
  return form.resultPublishedAt != null ||
      form.resultStatus == LotteryResultStatus.winner ||
      form.resultStatus == LotteryResultStatus.loser ||
      form.resultStatus == LotteryResultStatus.checked;
}

bool _isDashboardBundleResultPublished(PersonalSubmittedBundleForm form) {
  return form.resultPublishedAt != null ||
      form.resultStatus == LotteryResultStatus.winner ||
      form.resultStatus == LotteryResultStatus.loser ||
      form.resultStatus == LotteryResultStatus.checked;
}

String _dashboardPersonalOperationalStatus(LotteryForm form) {
  final String dispatchStatus = (form.dispatchStatus ?? '').trim();
  if ((dispatchStatus == 'queued_for_print' ||
          dispatchStatus == 'ready_for_print' ||
          (form.printReadyGeneratedAt != null && form.printedAt == null)) &&
      form.submittedToStationAt == null) {
    return 'ממתין להדפסה';
  }
  if ((dispatchStatus == 'printed' ||
          dispatchStatus == 'print_ready' ||
          dispatchStatus == 'ready_for_station' ||
          form.printedAt != null) &&
      form.submittedToStationAt == null) {
    return 'ממתין למסירה בתחנה';
  }
  if (dispatchStatus == 'submitted_to_station' ||
      form.submittedToStationAt != null) {
    return 'ממתין להגרלה';
  }
  if (form.resultStatus == LotteryResultStatus.waitingForResults) {
    return 'ממתין לתוצאות';
  }
  return 'ממתין לעיבוד';
}

String _dashboardPersonalBundleOperationalStatus(
    PersonalSubmittedBundle bundle) {
  for (final PersonalSubmittedBundleForm form in bundle.forms) {
    if (_isDashboardBundleResultPublished(form)) {
      continue;
    }
    if (form.receiptUrl != null && form.printedAt == null) {
      return 'ממתין להדפסה';
    }
    if (form.printedAt != null && form.submittedToStationAt == null) {
      return 'ממתין למסירה בתחנה';
    }
    if (form.submittedToStationAt != null) {
      return 'ממתין להגרלה';
    }
    if (form.resultStatus == LotteryResultStatus.waitingForResults) {
      return 'ממתין לתוצאות';
    }
  }
  return 'ממתין לעיבוד';
}

String _dashboardGroupOperationalStatus(SubmittedGroupHistoryItem group) {
  switch (group.dispatchStatus) {
    case LotteryGroupRepository.dispatchStatusQueuedForPrint:
      return 'ממתין להדפסה';
    case LotteryGroupRepository.dispatchStatusPrinted:
      return 'ממתין למסירה בתחנה';
    case LotteryGroupRepository.dispatchStatusSubmittedToStation:
      return 'ממתין להגרלה';
    default:
      return group.groupStatus == 'submitted'
          ? 'ממתין לתוצאות'
          : 'ממתין לעיבוד';
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
