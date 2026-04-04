import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/app_user.dart';
import '../models/lottery_form.dart';
import '../repositories/auth_repository.dart';
import '../repositories/lottery_form_repository.dart';
import '../services/lottery_form_service.dart';
import '../services/lottery_randomizer_service.dart';
import 'auth/auth_cubit.dart';
import 'history/history_cubit.dart';
import 'history/history_tab.dart';
import 'lottery_form/lottery_form_cubit.dart';
import 'lottery_form/lottery_form_page.dart';

class MainShellPage extends StatefulWidget {
  const MainShellPage({
    super.key,
    required this.user,
    required this.authRepository,
  });

  final AppUser user;
  final AuthRepository authRepository;

  @override
  State<MainShellPage> createState() => _MainShellPageState();
}

class _MainShellPageState extends State<MainShellPage> {
  late final LotteryFormRepository _formRepository;
  late final LotteryFormService _formService;
  late final LotteryRandomizerService _randomizerService;
  late final LotteryFormCubit _formCubit;
  late final HistoryCubit _historyCubit;

  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _formRepository = LotteryFormRepository();
    _formService = const LotteryFormService();
    _randomizerService = LotteryRandomizerService();
    _formCubit = LotteryFormCubit(
      formRepository: _formRepository,
      formService: _formService,
      randomizerService: _randomizerService,
      userId: widget.user.uid,
    );
    _historyCubit = HistoryCubit();
  }

  @override
  void dispose() {
    _formCubit.close();
    _historyCubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<LotteryFormCubit>.value(value: _formCubit),
        BlocProvider<HistoryCubit>.value(value: _historyCubit),
      ],
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: _TopTabButton(
                        label: 'היסטוריה',
                        selected: _selectedTabIndex == 1,
                        onTap: () => setState(() => _selectedTabIndex = 1),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TopTabButton(
                        label: 'שליחה',
                        selected: _selectedTabIndex == 0,
                        onTap: () => setState(() => _selectedTabIndex = 0),
                      ),
                    ),
                    const SizedBox(width: 10),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'logout') {
                          context.read<AuthCubit>().signOut();
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'logout',
                          child: Text('התנתקות'),
                        ),
                      ],
                      child: CircleAvatar(
                        radius: 22,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        child: Text(
                          (widget.user.displayName ?? widget.user.email ?? 'U')
                              .trim()
                              .substring(0, 1)
                              .toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: IndexedStack(
                  index: _selectedTabIndex,
                  children: [
                    const LotteryFormPage(),
                    HistoryTab(
                      userId: widget.user.uid,
                      repository: _formRepository,
                      onFormSelected: _handleHistoryFormSelected,
                      onDeleteSavedForm: _handleDeleteSavedForm,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleHistoryFormSelected(LotteryForm form) {
    _formCubit.loadForm(form);
    setState(() => _selectedTabIndex = 0);
  }

  Future<bool> _handleDeleteSavedForm(LotteryForm form) async {
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('אישור'),
            content: const Text('אתה בטוח שאתה רוצה למחוק את הטופס?'),
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

    if (!confirmed) {
      return false;
    }

    await _formCubit.deleteSavedForm(form);
    return true;
  }
}

class _TopTabButton extends StatelessWidget {
  const _TopTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        height: 44,
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
      ),
    );
  }
}
