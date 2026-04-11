import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/lottery_group.dart';
import '../../repositories/lottery_group_repository.dart';
import '../../services/group_invite_link_service.dart';
import '../../models/lottery_table.dart';
import '../../views/home/printing/lottery_print_preview_page.dart';
import 'group_details_page.dart';
import 'my_active_groups_page.dart';
import 'lottery_form_cubit.dart';
import 'lottery_form_state.dart';

enum _LottomatAction {
  completeRemaining,
  fullRandom,
}

enum _PersistAction {
  submit,
  save,
}

enum _GroupAction {
  create,
}

class LotteryFormPage extends StatefulWidget {
  const LotteryFormPage({
    super.key,
    required this.inviteLinkService,
    required this.onOpenMyForms,
  });

  static const double rowLabelWidth = 112;
  final GroupInviteLinkService inviteLinkService;
  final VoidCallback onOpenMyForms;

  @override
  State<LotteryFormPage> createState() => _LotteryFormPageState();
}

class _LotteryFormPageState extends State<LotteryFormPage> {
  late final LotteryGroupRepository _groupRepository;

  @override
  void initState() {
    super.initState();
    _groupRepository = LotteryGroupRepository();
  }

  Future<void> _promptCreateGroup() async {
    final LotteryFormState currentState =
        context.read<LotteryFormCubit>().state;
    if (!currentState.form.isComplete || currentState.isBusy) {
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

  Future<void> _startPersonalSubmitFlow() async {
    final bool? paymentConfirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const _TemporaryPaymentPage(),
      ),
    );

    if (!mounted || paymentConfirmed != true) {
      return;
    }

    await context.read<LotteryFormCubit>().submitForm();
    if (!mounted) {
      return;
    }

    final LotteryFormState latestState = context.read<LotteryFormCubit>().state;
    if (latestState.errorMessage == null) {
      widget.onOpenMyForms();
    }
  }

  void _openPrintDebugPreview(LotteryFormState state) {
    final List<List<int?>> rows = state.form.tables.map((table) {
      final List<int?> row = List<int?>.filled(7, null);
      for (int index = 0;
          index < table.regularNumbers.length && index < 6;
          index++) {
        row[index] = table.regularNumbers[index];
      }
      row[6] = table.strongNumber;
      return row;
    }).toList();

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LotteryPrintPreviewPage(rows: rows),
      ),
    );
  }

  void _openMyActiveGroups() {
    final String currentUserId =
        context.read<LotteryFormCubit>().state.form.userId;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MyActiveGroupsPage(
          userId: currentUserId,
          repository: _groupRepository,
          inviteLinkService: widget.inviteLinkService,
        ),
      ),
    );
  }

  void _handleGroupAction(_GroupAction action) {
    if (action != _GroupAction.create) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _promptCreateGroup();
    });
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
        final bool canCreateGroup = state.form.isComplete && !state.isBusy;
        return LayoutBuilder(
          builder: (context, constraints) {
            final double keyboardHeight =
                (constraints.maxHeight * 0.275).clamp(194.0, 246.0);

            return Stack(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(12, 12, 12, keyboardHeight + 14),
                  child: Column(
                    children: [
                      _ActionBar(
                        isBusy: state.isBusy,
                        canCreateGroup: canCreateGroup,
                        onClearPressed: _confirmClearForm,
                        onGroupAction: _handleGroupAction,
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
                        onPersistAction: (action) {
                          if (action == _PersistAction.save) {
                            context.read<LotteryFormCubit>().saveForm();
                          } else {
                            _startPersonalSubmitFlow();
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.end,
                          children: [
                            OutlinedButton(
                              onPressed:
                                  state.isBusy ? null : _openMyActiveGroups,
                              child: const Text('My Active Groups'),
                            ),
                            OutlinedButton(
                              onPressed: state.isBusy
                                  ? null
                                  : () => _openPrintDebugPreview(state),
                              child: const Text('Open Print Debug Preview'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView.separated(
                          padding: EdgeInsets.zero,
                          itemCount: state.form.tables.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            return _LotteryRowCard(
                              table: state.form.tables[index],
                              isActive: index == state.activeRowIndex,
                              isEnabled: index <= state.maxUnlockedRowIndex,
                              onTap: () => context
                                  .read<LotteryFormCubit>()
                                  .selectRow(index),
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

class _TemporaryPaymentPage extends StatelessWidget {
  const _TemporaryPaymentPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('תשלום'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'מסך תשלום זמני',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'הטופס האישי יישלח רק לאחר אישור התשלום.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('בצע תשלום'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.isBusy,
    required this.canCreateGroup,
    required this.onClearPressed,
    required this.onGroupAction,
    required this.onLottomatAction,
    required this.onPersistAction,
  });

  final bool isBusy;
  final bool canCreateGroup;
  final VoidCallback onClearPressed;
  final ValueChanged<_GroupAction> onGroupAction;
  final ValueChanged<_LottomatAction> onLottomatAction;
  final ValueChanged<_PersistAction> onPersistAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionChip(
            label: 'ניקוי טבלה',
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
        const SizedBox(width: 10),
        Expanded(
          child: PopupMenuButton<_GroupAction>(
            enabled: canCreateGroup,
            onSelected: onGroupAction,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _GroupAction.create,
                child: Text('יצירת קבוצה מטופס זה'),
              ),
            ],
            child: const _ActionChip(
              label: 'קבוצה',
              icon: Icons.group_outlined,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: PopupMenuButton<_PersistAction>(
            enabled: !isBusy,
            onSelected: onPersistAction,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _PersistAction.submit,
                child: Text('שליחת הטופס'),
              ),
              PopupMenuItem(
                value: _PersistAction.save,
                child: Text('שמירת הטופס'),
              ),
            ],
            child: const _ActionChip(
              label: 'שליחה/שמירה',
              icon: Icons.send_rounded,
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

class _LotteryRowCard extends StatelessWidget {
  const _LotteryRowCard({
    required this.table,
    required this.isActive,
    required this.isEnabled,
    required this.onTap,
  });

  final LotteryTable table;
  final bool isActive;
  final bool isEnabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color rowBackground = isActive
        ? (isDark ? const Color(0xFF243B4E) : const Color(0xFFCAE7FF))
        : Theme.of(context).colorScheme.surfaceContainerHighest;

    return Opacity(
      opacity: isEnabled ? 1 : 0.45,
      child: InkWell(
        onTap: isEnabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: rowBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isActive
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              width: 1.4,
            ),
          ),
          child: Row(
            children: [
              _RowLabel(text: 'טבלה ${table.tableIndex}'),
              const SizedBox(width: 8),
              ...List.generate(
                6,
                (index) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: index == 5 ? 8 : 6),
                    child: _LotteryCell(
                      value: index < table.regularNumbers.length
                          ? table.regularNumbers[index]
                          : null,
                      isStrong: false,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _LotteryCell(
                  value: table.strongNumber,
                  isStrong: true,
                ),
              ),
            ],
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
  });

  final double height;
  final LotteryFormState state;

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
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
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
            itemCount: widget.state.form.tables.length,
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
        const double gap = 4;
        const double dividerHeight = 1;
        final double rowHeight =
            (constraints.maxHeight - (gap * 5) - dividerHeight) / 5;
        final double topKeySize = rowHeight.clamp(
          30.0,
          (constraints.maxWidth - rowLabelWidth - (gap * 7)) / 7,
        );
        final double regularKeySize = rowHeight.clamp(
          30.0,
          (constraints.maxWidth - (gap * 9)) / 10,
        );
        final double strongLabelWidth = (regularKeySize * 3) + (gap * 2);

        return Column(
          children: [
            SizedBox(
              height: rowHeight,
              child: Row(
                children: [
                  _RowLabel(text: 'טבלה ${table.tableIndex}'),
                  const SizedBox(width: gap),
                  ...List.generate(
                    7,
                    (index) => Padding(
                      padding: EdgeInsets.only(right: index == 6 ? 0 : gap),
                      child: _NumberKey(
                        label: '${index + 1}',
                        size: topKeySize,
                        selected: table.regularNumbers.contains(index + 1),
                        enabled:
                            isActive && _canUseRegularNumber(table, index + 1),
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
            _RegularKeyboardRow(
              numbers: List<int>.generate(10, (index) => index + 8),
              rowHeight: rowHeight,
              keySize: regularKeySize,
              gap: gap,
              table: table,
              isActive: isActive,
            ),
            const SizedBox(height: gap),
            _RegularKeyboardRow(
              numbers: List<int>.generate(10, (index) => index + 18),
              rowHeight: rowHeight,
              keySize: regularKeySize,
              gap: gap,
              table: table,
              isActive: isActive,
            ),
            const SizedBox(height: gap),
            _RegularKeyboardRow(
              numbers: List<int>.generate(10, (index) => index + 28),
              rowHeight: rowHeight,
              keySize: regularKeySize,
              gap: gap,
              table: table,
              isActive: isActive,
            ),
            const SizedBox(height: gap),
            Divider(
                color: Theme.of(context).dividerColor, height: dividerHeight),
            const SizedBox(height: gap),
            SizedBox(
              height: rowHeight,
              child: Row(
                children: [
                  ...List.generate(
                    7,
                    (index) => Padding(
                      padding: const EdgeInsets.only(right: gap),
                      child: _NumberKey(
                        label: '${index + 1}',
                        size: rowHeight.clamp(30.0, regularKeySize),
                        selected: table.strongNumber == index + 1,
                        enabled: isActive && table.regularNumbers.length == 6,
                        onPressed: () => context
                            .read<LotteryFormCubit>()
                            .toggleStrongNumber(index + 1),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        width: strongLabelWidth,
                        height: rowHeight,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE94C),
                          borderRadius: BorderRadius.circular(12),
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
        );
      },
    );
  }

  bool _canUseRegularNumber(LotteryTable table, int number) {
    return table.regularNumbers.length < 6 ||
        table.regularNumbers.contains(number);
  }
}

class _RegularKeyboardRow extends StatelessWidget {
  const _RegularKeyboardRow({
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
  const _RowLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: LotteryFormPage.rowLabelWidth,
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
