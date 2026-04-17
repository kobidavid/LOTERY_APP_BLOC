import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
  });

  static const double rowLabelWidth = 98;
  final GroupInviteLinkService inviteLinkService;
  final VoidCallback onOpenMyForms;

  @override
  State<LotteryFormPage> createState() => _LotteryFormPageState();
}

class _LotteryFormPageState extends State<LotteryFormPage> {
  late final LotteryGroupRepository _groupRepository;
  late final LotteryFormRepository _paymentRepository;
  final ScrollController _tablesScrollController = ScrollController();
  final GlobalKey _tablesListKey = GlobalKey();
  final Map<int, GlobalKey> _tableRowKeys = <int, GlobalKey>{};
  bool _isGroupMode = false;
  bool _isDoubleMode = false;
  int? _lastAutoScrolledActiveRowIndex;
  int? _lastAutoScrolledSelectedTableCount;

  @override
  void initState() {
    super.initState();
    _groupRepository = LotteryGroupRepository();
    _paymentRepository = LotteryFormRepository();
  }

  @override
  void dispose() {
    _tablesScrollController.dispose();
    super.dispose();
  }

  Future<void> _promptCreateGroup() async {
    final LotteryFormState currentState =
        context.read<LotteryFormCubit>().state;
    if (!currentState.form.isComplete || currentState.isBusy) {
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

    if (!mounted || groupName == null || groupName.trim().isEmpty) {
      return;
    }

    final LotteryGroup? group =
        await context.read<LotteryFormCubit>().createGroup(groupName);
    if (!mounted || group == null) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GroupDetailsPage(
          groupId: group.groupId,
          currentUserId: group.creatorUserId,
          inviteLinkService: widget.inviteLinkService,
          repository: _groupRepository,
        ),
      ),
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
    final LotteryFormState currentState = context.read<LotteryFormCubit>().state;
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

  Future<void> _submitPersonalFormAndOpenHistory() async {
    await context.read<LotteryFormCubit>().submitForm();
    if (!mounted) {
      return;
    }

    final LotteryFormState latestState = context.read<LotteryFormCubit>().state;
    if (latestState.errorMessage == null) {
      widget.onOpenMyForms();
      return;
    }
    throw StateError(latestState.errorMessage ?? 'שליחת הטופס נכשלה');
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
    required double keyboardHeight,
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
    if (!_tablesScrollController.hasClients) {
      return;
    }

    final BuildContext? rowContext = _tableRowKeyForIndex(rowIndex).currentContext;
    final BuildContext? listContext = _tablesListKey.currentContext;
    if (rowContext == null || listContext == null) {
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

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<LotteryFormCubit, LotteryFormState>(
      listenWhen: (previous, current) =>
          previous.errorMessage != current.errorMessage ||
          previous.successMessage != current.successMessage,
      listener: (context, state) {
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
        final List<LotteryTable> visibleTables =
            state.visibleTables;
        final bool canPrimarySubmit =
            !state.isBusy &&
            _areSelectedTablesComplete(visibleTables, state.selectedTableCount);
        final int? gapRowIndex = state.firstGapRowIndex;
        return LayoutBuilder(
          builder: (context, constraints) {
            final double keyboardHeight =
                (constraints.maxHeight * 0.275).clamp(194.0, 246.0);
            _scheduleEnsureActiveTableVisible(
              state: state,
              keyboardHeight: keyboardHeight,
            );

            return Stack(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(10, 10, 10, keyboardHeight + 12),
                  child: Column(
                    children: [
                      const _CompactTopInfoRow(),
                      const SizedBox(height: 8),
                      _CompactControlRow(
                        isGroupMode: _isGroupMode,
                        isDoubleMode: _isDoubleMode,
                        selectedTableCount: state.selectedTableCount,
                        isBusy: state.isBusy,
                        onModeChanged: (value) =>
                            setState(() => _isGroupMode = value),
                        onPlayTypeChanged: (value) =>
                            setState(() => _isDoubleMode = value),
                        onTableCountChanged: _handleTableCountChanged,
                      ),
                      const SizedBox(height: 8),
                      _PrimarySubmitButton(
                        isEnabled: canPrimarySubmit,
                        onPressed: _handlePrimarySubmit,
                      ),
                      const SizedBox(height: 8),
                      _SecondaryActionRow(
                        isBusy: state.isBusy,
                        onClearPressed: _confirmClearForm,
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
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'יש להשלים טבלה ${gapRowIndex + 1} לפני המשך',
                            textAlign: TextAlign.right,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'החלק ימינה ללוטומט בטבלה אחת, שמאלה לניקוי',
                          textAlign: TextAlign.right,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView.separated(
                          key: _tablesListKey,
                          controller: _tablesScrollController,
                          padding: EdgeInsets.zero,
                          itemCount: visibleTables.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
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
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                    child: _LotteryKeyboardSheet(
                      height: keyboardHeight,
                      state: state,
                      visibleTableCount: state.selectedTableCount,
                    ),
                  ),
              ],
            );
          },
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

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('יצירת קבוצת לוטו'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'שם קבוצה',
          hintText: 'למשל: קבוצת שישי',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ביטול'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('יצירה'),
        ),
      ],
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
    final String dateLabel = (displayDate?.isNotEmpty ?? false)
        ? displayDate!
        : 'תאריך יעדכן בקרוב';
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
            const SizedBox(width: 6),
            Expanded(
              child: ClipRect(
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        tickerText,
                        maxLines: 1,
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
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
    required this.isGroupMode,
    required this.isDoubleMode,
    required this.selectedTableCount,
    required this.isBusy,
    required this.onModeChanged,
    required this.onPlayTypeChanged,
    required this.onTableCountChanged,
  });

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
              child: _TwoOptionToggle(
                isBusy: isBusy,
                leftLabel: 'אישי',
                rightLabel: 'קבוצתי',
                selectedRight: isGroupMode,
                onChanged: onModeChanged,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _CompactFieldShell(
              child: _TwoOptionToggle(
                isBusy: isBusy,
                leftLabel: 'רגיל',
                rightLabel: 'דאבל',
                selectedRight: isDoubleMode,
                onChanged: onPlayTypeChanged,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _CompactFieldShell(
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
    required this.isBusy,
    required this.leftLabel,
    required this.rightLabel,
    required this.selectedRight,
    required this.onChanged,
  });

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
            height: 34,
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
        const SizedBox(width: 6),
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
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 6),
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
    required this.isEnabled,
    required this.onPressed,
  });

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
            height: 52,
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
    required this.isBusy,
    required this.onClearPressed,
    required this.onLottomatAction,
  });

  final bool isBusy;
  final VoidCallback onClearPressed;
  final ValueChanged<_LottomatAction> onLottomatAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionChip(
            label: 'נקה טופס',
            icon: Icons.delete_outline,
            onTap: isBusy ? null : onClearPressed,
          ),
        ),
        const SizedBox(width: 10),
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
            child: const _ActionChip(
              label: 'לוטומט',
              icon: Icons.auto_awesome,
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.icon,
    this.onTap,
  });

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
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 6),
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _shakeController;
  late final Animation<double> _pulseAnimation;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _shakeOffsetAnimation;

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
    super.dispose();
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

        return Transform.scale(
          scale: widget.isActive ? _scaleAnimation.value : 1,
          child: Transform.translate(
            offset: Offset(
              widget.isActive ? _shakeOffsetAnimation.value : 0,
              0,
            ),
            child: Opacity(
              opacity: widget.isEnabled ? 1 : 0.45,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragEnd: widget.isEnabled
                    ? (details) {
                        final double velocity = details.primaryVelocity ?? 0;
                        if (velocity > 250) {
                          widget.onSwipeRight();
                        } else if (velocity < -250) {
                          widget.onSwipeLeft();
                        }
                      }
                    : null,
                child: InkWell(
                  onTap: widget.isEnabled ? widget.onTap : null,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    height: 56,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    decoration: BoxDecoration(
                      color: rowBackground,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: widget.isActive
                            ? activeBorderColor
                            : widget.isGapTarget
                                ? gapHighlightColor.withValues(alpha: 0.7)
                                : Colors.transparent,
                        width: widget.isActive ? 1.5 : (widget.isGapTarget ? 1.1 : 1.4),
                      ),
                      boxShadow: widget.isActive
                          ? activeGlow
                          : widget.isGapTarget
                              ? [
                                  BoxShadow(
                                    color: gapHighlightColor.withValues(alpha: 0.12),
                                    blurRadius: 10,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                    ),
                    child: Row(
                      children: [
                        _RowLabel(text: 'טבלה ${widget.table.tableIndex}'),
                        const SizedBox(width: 8),
                        ...List.generate(
                          6,
                          (index) => Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(right: index == 5 ? 8 : 6),
                              child: _LotteryCell(
                                value: index < widget.table.regularNumbers.length
                                    ? widget.table.regularNumbers[index]
                                    : null,
                                isStrong: false,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
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
          ),
        );
      },
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final LotteryFormCubit cubit = context.read<LotteryFormCubit>();

    return Material(
      elevation: 18,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      color: Theme.of(context).colorScheme.surface,
      child: Container(
        height: widget.height,
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragEnd: (details) {
            final double velocity = details.primaryVelocity ?? 0;
            if (velocity < -250) {
              cubit.swipeToNextRow();
            } else if (velocity > 250) {
              cubit.swipeToPreviousRow();
            }
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
        const double gap = 8;
        const double dividerHeight = 1;
        const double horizontalInset = 6;
        final double rowHeight =
            (constraints.maxHeight - (gap * 5) - dividerHeight) / 5;
        final double innerWidth = constraints.maxWidth - (horizontalInset * 2);
        final double keyboardLabelWidth =
            (innerWidth * 0.26).clamp(124.0, 158.0);
        final double fullRowKeySize = (innerWidth - (gap * 9)) / 10;
        final double topKeySize = rowHeight.clamp(
          32.0,
          (innerWidth - keyboardLabelWidth - (gap * 7)) / 7,
        );
        final double regularKeySize = rowHeight.clamp(32.0, fullRowKeySize);
        final double strongKeySize = rowHeight.clamp(32.0, regularKeySize);
        final double strongTrackWidth = (strongKeySize * 7) + (gap * 6);
        final double strongLabelWidth = innerWidth - strongTrackWidth;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: horizontalInset),
          child: Column(
            children: [
              SizedBox(
                height: rowHeight,
                child: Row(
                  children: [
                    _RowLabel(
                      text: 'טבלה ${table.tableIndex}',
                      width: keyboardLabelWidth,
                    ),
                    const SizedBox(width: gap),
                    ...List.generate(
                      7,
                      (index) => Padding(
                        padding: EdgeInsets.only(right: index == 6 ? 0 : gap),
                        child: _NumberKey(
                          label: '${index + 1}',
                          size: topKeySize,
                          selected: table.regularNumbers.contains(index + 1),
                          enabled: isActive &&
                              (table.regularNumbers.length < 6 ||
                                  table.regularNumbers.contains(index + 1)),
                          onPressed: () => context
                              .read<LotteryFormCubit>()
                              .toggleRegularNumber(index + 1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: gap),
              _ResponsiveKeyboardRow(
                numbers: List<int>.generate(10, (index) => index + 8),
                rowHeight: rowHeight,
                keySize: regularKeySize,
                gap: gap,
                table: table,
                isActive: isActive,
              ),
              const SizedBox(height: gap),
              _ResponsiveKeyboardRow(
                numbers: List<int>.generate(10, (index) => index + 18),
                rowHeight: rowHeight,
                keySize: regularKeySize,
                gap: gap,
                table: table,
                isActive: isActive,
              ),
              const SizedBox(height: gap),
              _ResponsiveKeyboardRow(
                numbers: List<int>.generate(10, (index) => index + 28),
                rowHeight: rowHeight,
                keySize: regularKeySize,
                gap: gap,
                table: table,
                isActive: isActive,
              ),
              const SizedBox(height: gap),
              Divider(
                color: Theme.of(context).dividerColor,
                height: dividerHeight,
              ),
              const SizedBox(height: gap),
              SizedBox(
                height: rowHeight,
                child: Row(
                  children: [
                    SizedBox(
                      width: strongTrackWidth,
                      child: Row(
                        children: List.generate(
                          7,
                          (index) => Padding(
                            padding: EdgeInsets.only(
                              right: index == 6 ? 0 : gap,
                            ),
                            child: _NumberKey(
                              label: '${index + 1}',
                              size: strongKeySize,
                              selected: table.strongNumber == index + 1,
                              enabled:
                                  isActive && table.regularNumbers.length == 6,
                              onPressed: () => context
                                  .read<LotteryFormCubit>()
                                  .toggleStrongNumber(index + 1),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: gap),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          width: strongLabelWidth - gap,
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
                              padding: EdgeInsets.symmetric(horizontal: 10),
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
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ResponsiveKeyboardRow extends StatelessWidget {
  const _ResponsiveKeyboardRow({
    required this.numbers,
    required this.rowHeight,
    required this.keySize,
    required this.gap,
    required this.table,
    required this.isActive,
  });

  final List<int> numbers;
  final double rowHeight;
  final double keySize;
  final double gap;
  final LotteryTable table;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: rowHeight,
      child: Row(
        children: List.generate(
          numbers.length,
          (index) => Padding(
            padding:
                EdgeInsets.only(right: index == numbers.length - 1 ? 0 : gap),
            child: _NumberKey(
              label: '${numbers[index]}',
              size: keySize,
              selected: table.regularNumbers.contains(numbers[index]),
              enabled: isActive &&
                  (table.regularNumbers.length < 6 ||
                      table.regularNumbers.contains(numbers[index])),
              onPressed: () => context
                  .read<LotteryFormCubit>()
                  .toggleRegularNumber(numbers[index]),
            ),
          ),
        ),
      ),
    );
  }
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
    this.width,
  });

  final String text;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width ?? LotteryFormPage.rowLabelWidth,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 16,
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
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isStrong ? const Color(0xFFDCCB59) : const Color(0xFFE91E63),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        value?.toString() ?? '',
        style: TextStyle(
          color: isStrong ? Colors.black : Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 18,
        ),
      ),
    );
  }
}
