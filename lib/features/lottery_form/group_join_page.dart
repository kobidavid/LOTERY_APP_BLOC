import 'package:flutter/material.dart';

import '../../repositories/lottery_group_repository.dart';
import '../../services/group_invite_link_service.dart';
import 'group_details_page.dart';

class GroupJoinPage extends StatefulWidget {
  const GroupJoinPage({
    super.key,
    required this.userId,
    required this.invite,
    required this.repository,
  });

  final String userId;
  final GroupInviteLink invite;
  final LotteryGroupRepository repository;

  @override
  State<GroupJoinPage> createState() => _GroupJoinPageState();
}

class _GroupJoinPageState extends State<GroupJoinPage> {
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final LotteryGroupInviteBundle bundle =
          await widget.repository.loadInvite(
        groupId: widget.invite.groupId,
        inviteToken: widget.invite.inviteToken,
        userId: widget.userId,
      );

      if (!mounted) {
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => GroupDetailsPage(
              groupId: bundle.group.groupId,
              currentUserId: widget.userId,
              inviteLinkService: GroupInviteLinkService(),
              repository: widget.repository,
            ),
          ),
        );
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString().replaceFirst('Bad state: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('הצטרפות לקבוצה')),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _errorMessage ?? 'אירעה שגיאה.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
      ),
    );
  }
}
