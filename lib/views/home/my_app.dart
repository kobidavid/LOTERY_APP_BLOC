import 'dart:math';

import 'package:flutter/material.dart';

import 'printing/lottery_print_preview_page.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LotoGroup',
      themeMode: ThemeMode.system,
      theme: _buildLotteryTheme(Brightness.light),
      darkTheme: _buildLotteryTheme(Brightness.dark),
      home: const NumberInputScreen(),
    );
  }

  ThemeData _buildLotteryTheme(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      brightness: brightness,
      seedColor: const Color(0xFFE91E63),
      surface: isDark ? const Color(0xFF17171B) : const Color(0xFFF8F3F7),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        elevation: 0,
        backgroundColor:
            isDark ? const Color(0xFF33212A) : const Color(0xFFF3B7CC),
        foregroundColor: isDark ? Colors.white : Colors.black,
        titleTextStyle: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w900,
          color: isDark ? Colors.white : Colors.black,
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}

class NumberInputScreen extends StatefulWidget {
  const NumberInputScreen({super.key});

  @override
  State<NumberInputScreen> createState() => _NumberInputScreenState();
}

class _NumberInputScreenState extends State<NumberInputScreen> {
  static const int _rowCount = 14;
  static const int _regularCount = 6;
  static const int _strongIndex = 6;
  static const double _rowLabelWidth = 92;

  final Random _random = Random();
  final List<List<int?>> _rows =
      List.generate(_rowCount, (_) => List<int?>.filled(7, null));
  final ScrollController _rowsScrollController = ScrollController();
  late final PageController _keyboardPageController;

  int _activeRowIndex = 0;
  int _maxUnlockedRowIndex = 0;

  @override
  void initState() {
    super.initState();
    _keyboardPageController = PageController();
  }

  bool _rowRegularComplete(int rowIndex) {
    return _rows[rowIndex].take(_regularCount).every((value) => value != null);
  }

  bool _rowComplete(int rowIndex) {
    return _rows[rowIndex].every((value) => value != null);
  }

  int _firstEmptyRegularIndex(int rowIndex) {
    return _rows[rowIndex]
        .take(_regularCount)
        .toList()
        .indexWhere((value) => value == null);
  }

  void _compactRegularNumbers(int rowIndex) {
    final List<int?> compacted =
        _rows[rowIndex].take(_regularCount).whereType<int>().toList()..sort();
    final List<int?> normalized = compacted.cast<int?>().toList();
    while (normalized.length < _regularCount) {
      normalized.add(null);
    }
    for (int index = 0; index < _regularCount; index++) {
      _rows[rowIndex][index] = normalized[index];
    }
  }

  void _scrollToActiveRow() {
    if (!_rowsScrollController.hasClients) {
      return;
    }

    final double targetOffset = (_activeRowIndex * 60).toDouble().clamp(
          0,
          _rowsScrollController.position.maxScrollExtent,
        );

    _rowsScrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _setActiveRow(int rowIndex, {bool animateKeyboard = true}) {
    setState(() {
      _activeRowIndex = rowIndex;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToActiveRow();
      if (animateKeyboard && _keyboardPageController.hasClients) {
        _keyboardPageController.animateToPage(
          rowIndex,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _toggleRegularNumber(int number) {
    final int selectedIndex =
        _rows[_activeRowIndex].take(_regularCount).toList().indexWhere(
              (value) => value == number,
            );

    setState(() {
      if (selectedIndex != -1) {
        _rows[_activeRowIndex][selectedIndex] = null;
        _compactRegularNumbers(_activeRowIndex);
        return;
      }

      final int emptyIndex = _firstEmptyRegularIndex(_activeRowIndex);
      if (emptyIndex == -1) {
        return;
      }

      _rows[_activeRowIndex][emptyIndex] = number;
      _compactRegularNumbers(_activeRowIndex);
    });
  }

  void _toggleStrongNumber(int number) {
    if (!_rowRegularComplete(_activeRowIndex)) {
      return;
    }

    setState(() {
      _rows[_activeRowIndex][_strongIndex] =
          _rows[_activeRowIndex][_strongIndex] == number ? null : number;
    });

    if (_rowComplete(_activeRowIndex) && _activeRowIndex < _rowCount - 1) {
      _maxUnlockedRowIndex = max(_maxUnlockedRowIndex, _activeRowIndex + 1);
      _setActiveRow(_activeRowIndex + 1);
    }
  }

  void _handleRowTap(int rowIndex) {
    final bool canOpen = rowIndex <= _maxUnlockedRowIndex;
    if (!canOpen || rowIndex == _activeRowIndex) {
      return;
    }

    _setActiveRow(rowIndex);
  }

  void _handleKeyboardPageChanged(int rowIndex) {
    if (rowIndex == _activeRowIndex) {
      return;
    }

    final bool canMoveBackward = rowIndex < _activeRowIndex;
    final bool canMoveForward = rowIndex <= _maxUnlockedRowIndex;

    if (canMoveBackward || canMoveForward) {
      _setActiveRow(rowIndex, animateKeyboard: false);
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_keyboardPageController.hasClients) {
        _keyboardPageController.animateToPage(
          _activeRowIndex,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<bool> _showConfirmationDialog(String message) async {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor:
                isDark ? const Color(0xFF23232A) : const Color(0xFFFFFBFD),
            title: Text(
              'אישור',
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
            ),
            content: Text(
              message,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
                fontSize: 17,
              ),
            ),
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
  }

  Future<void> _showActionsSheet() async {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor:
          isDark ? const Color(0xFF202028) : const Color(0xFFFFFBFD),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  leading: const Icon(Icons.auto_awesome),
                  title: const Text('מילוי אוטומטי'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    final bool confirmed = await _showConfirmationDialog(
                      'האם אתה בטוח שאתה רוצה למלא טופס אוטומטי?',
                    );
                    if (confirmed) {
                      _autoFillForm();
                    }
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('נקה טופס'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    final bool confirmed = await _showConfirmationDialog(
                      'האם אתה בטוח שאתה רוצה לנקות את הטופס?',
                    );
                    if (confirmed) {
                      _clearForm();
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _autoFillForm() {
    setState(() {
      for (int rowIndex = 0; rowIndex < _rowCount; rowIndex++) {
        final List<int> regulars = List<int>.generate(37, (index) => index + 1)
          ..shuffle(_random);
        final List<int> selected = regulars.take(6).toList()..sort();
        for (int i = 0; i < _regularCount; i++) {
          _rows[rowIndex][i] = selected[i];
        }
        _rows[rowIndex][_strongIndex] = _random.nextInt(7) + 1;
      }
      _activeRowIndex = 0;
      _maxUnlockedRowIndex = _rowCount - 1;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rowsScrollController.jumpTo(0);
      if (_keyboardPageController.hasClients) {
        _keyboardPageController.jumpToPage(0);
      }
    });
  }

  void _clearForm() {
    setState(() {
      for (final row in _rows) {
        for (int index = 0; index < row.length; index++) {
          row[index] = null;
        }
      }
      _activeRowIndex = 0;
      _maxUnlockedRowIndex = 0;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rowsScrollController.jumpTo(0);
      if (_keyboardPageController.hasClients) {
        _keyboardPageController.jumpToPage(0);
      }
    });
  }

  void _openPrintPreview() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LotteryPrintPreviewPage(
          rows: _rows.map((row) => List<int?>.from(row)).toList(),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _rowsScrollController.dispose();
    _keyboardPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        centerTitle: true,
        title: const Text('LotoGroup'),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double keyboardHeight =
                (constraints.maxHeight * 0.30).clamp(210.0, 252.0);

            return Stack(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    10,
                    6,
                    10,
                    keyboardHeight + 10,
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isDark
                                  ? const Color(0xFF111318)
                                  : Colors.black,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () {},
                            child: const Text(
                              'איזור אישי',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          FilledButton(
                            onPressed: _openPrintPreview,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              'Print',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const Spacer(),
                          FloatingActionButton.small(
                            heroTag: 'actions_button',
                            backgroundColor: isDark
                                ? const Color(0xFF5CAACE)
                                : const Color(0xFF8DD0F1),
                            foregroundColor: Colors.white,
                            onPressed: _showActionsSheet,
                            child: const Icon(Icons.add),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton(
                          onPressed: _openPrintPreview,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            side: BorderSide(
                              color: isDark
                                  ? Colors.white24
                                  : colors.primary.withValues(alpha: 0.45),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Open Print Debug Preview',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.separated(
                          controller: _rowsScrollController,
                          padding: EdgeInsets.zero,
                          itemCount: _rowCount,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, rowIndex) {
                            return LotteryRowCard(
                              rowIndex: rowIndex,
                              values: _rows[rowIndex],
                              isActive: rowIndex == _activeRowIndex,
                              isEnabled: rowIndex <= _maxUnlockedRowIndex,
                              onTap: () => _handleRowTap(rowIndex),
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
                  child: LotteryKeyboardSheet(
                    height: keyboardHeight,
                    controller: _keyboardPageController,
                    rows: _rows,
                    activeRowIndex: _activeRowIndex,
                    onPageChanged: _handleKeyboardPageChanged,
                    onRegularTap: _toggleRegularNumber,
                    onStrongTap: _toggleStrongNumber,
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

class LotteryRowCard extends StatelessWidget {
  const LotteryRowCard({
    super.key,
    required this.rowIndex,
    required this.values,
    required this.isActive,
    required this.isEnabled,
    required this.onTap,
  });

  final int rowIndex;
  final List<int?> values;
  final bool isActive;
  final bool isEnabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color rowBackground = isActive
        ? (isDark ? const Color(0xFF274056) : const Color(0xFF80D568))
        : (isDark ? const Color(0xFF090A0F) : Colors.black);

    return Opacity(
      opacity: isEnabled ? 1 : 0.55,
      child: InkWell(
        onTap: isEnabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: rowBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isActive
                  ? (isDark ? Colors.white70 : const Color(0xFF17301F))
                  : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              _RowLabel(
                text: 'טבלה ${rowIndex + 1}',
                width: _NumberInputScreenState._rowLabelWidth,
              ),
              const SizedBox(width: 6),
              ...List.generate(
                values.length,
                (index) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: index == values.length - 1 ? 0 : 5,
                    ),
                    child: _LotteryCell(
                      value: values[index],
                      isStrong: index == 6,
                    ),
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

class LotteryKeyboardSheet extends StatelessWidget {
  const LotteryKeyboardSheet({
    super.key,
    required this.height,
    required this.controller,
    required this.rows,
    required this.activeRowIndex,
    required this.onPageChanged,
    required this.onRegularTap,
    required this.onStrongTap,
  });

  final double height;
  final PageController controller;
  final List<List<int?>> rows;
  final int activeRowIndex;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onRegularTap;
  final ValueChanged<int> onStrongTap;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      elevation: 18,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Container(
        height: height,
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF18181D) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: PageView.builder(
          controller: controller,
          onPageChanged: onPageChanged,
          itemCount: rows.length,
          itemBuilder: (context, rowIndex) {
            return LotteryKeyboardPage(
              rowIndex: rowIndex,
              rowValues: rows[rowIndex],
              isActive: rowIndex == activeRowIndex,
              rowLabelWidth: _NumberInputScreenState._rowLabelWidth,
              onRegularTap: onRegularTap,
              onStrongTap: onStrongTap,
            );
          },
        ),
      ),
    );
  }
}

class LotteryKeyboardPage extends StatelessWidget {
  const LotteryKeyboardPage({
    super.key,
    required this.rowIndex,
    required this.rowValues,
    required this.isActive,
    required this.rowLabelWidth,
    required this.onRegularTap,
    required this.onStrongTap,
  });

  final int rowIndex;
  final List<int?> rowValues;
  final bool isActive;
  final double rowLabelWidth;
  final ValueChanged<int> onRegularTap;
  final ValueChanged<int> onStrongTap;

  bool get _regularComplete =>
      rowValues.take(6).every((value) => value != null);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double gap = 6;
        final double labelWidth = rowLabelWidth;
        final double rowHeight = (constraints.maxHeight - (gap * 5) - 1) / 5;
        final double topKeySize =
            (constraints.maxWidth - labelWidth - (gap * 7) - 16) / 7;
        final double regularKeySize =
            (constraints.maxWidth - (gap * 9) - 16) / 10;
        final double strongKeySize =
            (constraints.maxWidth - (gap * 7) - 140 - 16) / 7;

        return Column(
          children: [
            SizedBox(
              height: rowHeight,
              child: Row(
                children: [
                  SizedBox(
                    width: labelWidth,
                    child: _RowLabel(
                      text: 'טבלה ${rowIndex + 1}',
                      width: rowLabelWidth,
                    ),
                  ),
                  const SizedBox(width: 6),
                  ...List.generate(
                    7,
                    (index) => Padding(
                      padding: EdgeInsets.only(right: index == 6 ? 0 : gap),
                      child: LotteryNumberKey(
                        label: '${index + 1}',
                        size: topKeySize,
                        selected: rowValues.take(6).contains(index + 1),
                        enabled: isActive &&
                            (!_regularComplete ||
                                rowValues.take(6).contains(index + 1)),
                        onPressed: () => onRegularTap(index + 1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            _RegularKeyboardRow(
              numbers: List.generate(10, (index) => index + 8),
              rowValues: rowValues,
              keySize: regularKeySize,
              rowHeight: rowHeight,
              gap: gap,
              isActive: isActive,
              regularComplete: _regularComplete,
              onTap: onRegularTap,
            ),
            const SizedBox(height: 6),
            _RegularKeyboardRow(
              numbers: List.generate(10, (index) => index + 18),
              rowValues: rowValues,
              keySize: regularKeySize,
              rowHeight: rowHeight,
              gap: gap,
              isActive: isActive,
              regularComplete: _regularComplete,
              onTap: onRegularTap,
            ),
            const SizedBox(height: 6),
            _RegularKeyboardRow(
              numbers: List.generate(10, (index) => index + 28),
              rowValues: rowValues,
              keySize: regularKeySize,
              rowHeight: rowHeight,
              gap: gap,
              isActive: isActive,
              regularComplete: _regularComplete,
              onTap: onRegularTap,
            ),
            const SizedBox(height: 6),
            Divider(
              height: 1,
              thickness: 1,
              color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: rowHeight,
              child: Row(
                children: [
                  ...List.generate(
                    7,
                    (index) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: LotteryNumberKey(
                        label: '${index + 1}',
                        size: strongKeySize,
                        selected: rowValues[6] == index + 1,
                        enabled: isActive && _regularComplete,
                        onPressed: () => onStrongTap(index + 1),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.yellow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.pink, width: 1.2),
                      ),
                      child: const Text(
                        'המספר החזק',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
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
}

class _RegularKeyboardRow extends StatelessWidget {
  const _RegularKeyboardRow({
    required this.numbers,
    required this.rowValues,
    required this.keySize,
    required this.rowHeight,
    required this.gap,
    required this.isActive,
    required this.regularComplete,
    required this.onTap,
  });

  final List<int> numbers;
  final List<int?> rowValues;
  final double keySize;
  final double rowHeight;
  final double gap;
  final bool isActive;
  final bool regularComplete;
  final ValueChanged<int> onTap;

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
            child: LotteryNumberKey(
              label: '${numbers[index]}',
              size: keySize,
              selected: rowValues.take(6).contains(numbers[index]),
              enabled: isActive &&
                  (!regularComplete ||
                      rowValues.take(6).contains(numbers[index])),
              onPressed: () => onTap(numbers[index]),
            ),
          ),
        ),
      ),
    );
  }
}

class LotteryNumberKey extends StatelessWidget {
  const LotteryNumberKey({
    super.key,
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
        ? Colors.yellow
        : enabled
            ? (isDark ? const Color(0xFF1F2027) : Colors.white)
            : (isDark ? const Color(0xFF2E2F37) : const Color(0xFFE7E7EC));

    final Color foreground = selected
        ? Colors.black
        : enabled
            ? (isDark ? Colors.white : Colors.black)
            : Colors.black38;

    return SizedBox(
      width: size,
      height: size,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          elevation: selected ? 0 : 1,
          padding: EdgeInsets.zero,
          backgroundColor: background,
          foregroundColor: foreground,
          side: BorderSide(
            color: isDark ? const Color(0xFFFF5A8D) : Colors.pink,
            width: 1.2,
          ),
          shape: const CircleBorder(),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: size * 0.34,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _RowLabel extends StatelessWidget {
  const _RowLabel({
    required this.text,
    required this.width,
  });

  final String text;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w900,
          color: Colors.white,
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
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isStrong
            ? (isDark ? const Color(0xFFD8C857) : Colors.yellow)
            : Colors.pink,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        value?.toString() ?? '',
        style: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w900,
          color: isStrong ? Colors.black87 : Colors.white,
        ),
      ),
    );
  }
}
