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
        appBar: _selectedTabIndex == 0
            ? null
            : AppBar(
                title: Text(_titleForIndex(_selectedTabIndex)),
                actions: [
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
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(end: 16),
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        child: Text(
                          _avatarLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
        body: SafeArea(
          top: _selectedTabIndex == 0,
          child: IndexedStack(
            index: _selectedTabIndex,
            children: [
              LotteryFormPage(
                inviteLinkService: widget.inviteLinkService,
                onOpenMyForms: () => setState(() => _selectedTabIndex = 1),
              ),
              HistoryTab(
                userId: widget.user.uid,
                repository: _formRepository,
                groupRepository: _groupRepository,
                inviteLinkService: widget.inviteLinkService,
                onFormSelected: _handleHistoryFormSelected,
                onDeleteSavedForm: _handleDeleteSavedForm,
              ),
              const _PersonalAreaPlaceholder(),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedTabIndex,
          onDestinationSelected: (index) {
            setState(() => _selectedTabIndex = index);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'מסך הבית',
            ),
            NavigationDestination(
              icon: Icon(Icons.description_outlined),
              selectedIcon: Icon(Icons.description_rounded),
              label: 'הטפסים שלי',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'איזור אישי',
            ),
          ],
        ),
      ),
    );
  }

  String get _avatarLabel {
    return (widget.user.displayName ?? widget.user.email ?? 'U')
        .trim()
        .substring(0, 1)
        .toUpperCase();
  }

  String _titleForIndex(int index) {
    switch (index) {
      case 1:
        return 'הטפסים שלי';
      case 2:
        return 'איזור אישי';
      case 0:
      default:
        return 'מסך הבית';
    }
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

class _PersonalAreaPlaceholder extends StatelessWidget {
  const _PersonalAreaPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_outline_rounded,
                size: 42,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'איזור אישי',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'המסך הזה ישמש בהמשך לאזור אישי, פרופיל והעדפות משתמש.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
