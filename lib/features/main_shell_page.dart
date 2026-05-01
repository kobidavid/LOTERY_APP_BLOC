import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/app_user.dart';
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
  int _personalDraftLoadVersion = 0;
  bool _handlingInvite = false;
  PersonalDraftLoadRequest? _personalDraftLoadRequest;

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
        resizeToAvoidBottomInset: false,
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
                personalDraftLoadRequest: _personalDraftLoadRequest,
                personalDraftLoadVersion: _personalDraftLoadVersion,
              ),
              HistoryTab(
                userId: widget.user.uid,
                repository: _formRepository,
                groupRepository: _groupRepository,
                inviteLinkService: widget.inviteLinkService,
                onPersonalDraftSelected: _handlePersonalDraftSelected,
                onPersonalDraftBundleSelected:
                    _handlePersonalDraftBundleSelected,
                onCancelGroupDraft: _handleCancelGroupDraft,
              ),
              _PersonalAreaTab(user: widget.user),
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

  void _handlePersonalDraftSelected(PersonalSavedDraftEntry entry) {
    setState(() {
      _personalDraftLoadRequest = PersonalDraftLoadRequest(
        entries: <PersonalSavedDraftEntry>[entry],
      );
      _personalDraftLoadVersion += 1;
      _selectedTabIndex = 0;
    });
  }

  void _handlePersonalDraftBundleSelected(
    List<PersonalSavedDraftEntry> entries,
  ) {
    setState(() {
      _personalDraftLoadRequest = PersonalDraftLoadRequest(entries: entries);
      _personalDraftLoadVersion += 1;
      _selectedTabIndex = 0;
    });
  }

  Future<bool> _handleCancelGroupDraft(String groupId) async {
    try {
      await _groupRepository.cancelGroupDraft(
        groupId: groupId,
        cancelledByUserId: widget.user.uid,
      );
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
      return false;
    }
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

class _PersonalAreaTab extends StatelessWidget {
  const _PersonalAreaTab({
    required this.user,
  });

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final Map<String, dynamic> data =
            snapshot.data?.data() ?? const <String, dynamic>{};
        final String? displayName = _normalizedText(
          data['displayName'] as String?,
          fallback: user.displayName,
        );
        final String? email = _normalizedText(
          data['email'] as String?,
          fallback: user.email,
        );
        final num balance = (data['balance'] as num?) ?? 0;
        final String avatarLabel =
            (displayName ?? email ?? 'U').trim().substring(0, 1).toUpperCase();

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  children: [
                    _PersonalAreaCard(
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 38,
                            backgroundColor:
                                Theme.of(context).colorScheme.primary,
                            backgroundImage:
                                _normalizedText(user.photoUrl) != null
                                    ? NetworkImage(user.photoUrl!)
                                    : null,
                            child: _normalizedText(user.photoUrl) == null
                                ? Text(
                                    avatarLabel,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 24,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            displayName ?? 'משתמש',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            email ?? 'ללא אימייל',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _PersonalAreaCard(
                      child: Column(
                        children: [
                          Text(
                            'יתרה נוכחית',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            '$balance ש״ח',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .displaySmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _PersonalAreaCard(
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => context.read<AuthCubit>().signOut(),
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('התנתקות'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
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
  }

  String? _normalizedText(String? value, {String? fallback}) {
    final String? primary = value?.trim();
    if (primary != null && primary.isNotEmpty) {
      return primary;
    }
    final String? fallbackValue = fallback?.trim();
    if (fallbackValue != null && fallbackValue.isNotEmpty) {
      return fallbackValue;
    }
    return null;
  }
}

class _PersonalAreaCard extends StatelessWidget {
  const _PersonalAreaCard({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
      ),
      child: child,
    );
  }
}
