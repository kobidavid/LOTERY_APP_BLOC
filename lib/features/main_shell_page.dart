import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/app_user.dart';
import '../models/lottery_form.dart';
import '../repositories/auth_repository.dart';
import '../repositories/lottery_form_repository.dart';
import '../repositories/lottery_group_repository.dart';
import '../services/group_invite_link_service.dart';
import '../services/lottery_form_service.dart';
import '../services/lottery_randomizer_service.dart';
import 'auth/auth_cubit.dart';
import 'history/history_cubit.dart';
import 'history/history_tab.dart';
import 'lottery_form/group_join_page.dart';
import 'lottery_form/lottery_form_cubit.dart';
import 'lottery_form/lottery_form_page.dart';
import 'operator/operator_console_page.dart';

class MainShellPage extends StatefulWidget {
  const MainShellPage({
    super.key,
    required this.user,
    required this.authRepository,
    required this.inviteLinkService,
  });

  final AppUser user;
  final AuthRepository authRepository;
  final GroupInviteLinkService inviteLinkService;

  @override
  State<MainShellPage> createState() => _MainShellPageState();
}

class _MainShellPageState extends State<MainShellPage> {
  late final LotteryFormRepository _formRepository;
  late final LotteryFormService _formService;
  late final LotteryRandomizerService _randomizerService;
  late final LotteryFormCubit _formCubit;
  late final HistoryCubit _historyCubit;
  late final LotteryGroupRepository _groupRepository;
  StreamSubscription<GroupInviteLink>? _inviteSubscription;

  int _selectedTabIndex = 0;
  bool _handlingInvite = false;

  @override
  void initState() {
    super.initState();
    _formRepository = LotteryFormRepository();
    _formService = const LotteryFormService();
    _randomizerService = LotteryRandomizerService();
    _groupRepository = LotteryGroupRepository();
    _formCubit = LotteryFormCubit(
      formRepository: _formRepository,
      formService: _formService,
      randomizerService: _randomizerService,
      userId: widget.user.uid,
    );
    _historyCubit = HistoryCubit();
    _inviteSubscription = widget.inviteLinkService.inviteStream
        .listen((_) => _handlePendingInvite());
    WidgetsBinding.instance.addPostFrameCallback((_) => _handlePendingInvite());
  }

  @override
  void dispose() {
    _inviteSubscription?.cancel();
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
                          return;
                        }
                        if (value == 'operator_console') {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => OperatorConsolePage(
                                user: widget.user,
                              ),
                            ),
                          );
                        }
                      },
                      itemBuilder: (context) => [
                        if (kIsWeb && widget.user.operatorAccess)
                          const PopupMenuItem(
                            value: 'operator_console',
                            child: Text('Operator Console'),
                          ),
                        const PopupMenuItem(
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
                    LotteryFormPage(
                      inviteLinkService: widget.inviteLinkService,
                    ),
                    HistoryTab(
                      userId: widget.user.uid,
                      repository: _formRepository,
                      groupRepository: _groupRepository,
                      inviteLinkService: widget.inviteLinkService,
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

  Future<void> _handlePendingInvite() async {
    if (!mounted || _handlingInvite) {
      return;
    }

    final GroupInviteLink? invite =
        widget.inviteLinkService.takePendingInvite();
    if (invite == null) {
      return;
    }

    _handlingInvite = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => GroupJoinPage(
            userId: widget.user.uid,
            invite: invite,
            repository: _groupRepository,
          ),
        ),
      );
    } finally {
      _handlingInvite = false;
      if (mounted && widget.inviteLinkService.peekPendingInvite() != null) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _handlePendingInvite());
      }
    }
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
