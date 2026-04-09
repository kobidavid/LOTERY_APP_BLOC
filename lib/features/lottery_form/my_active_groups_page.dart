import 'package:flutter/material.dart';

import '../../repositories/lottery_group_repository.dart';
import '../../services/group_invite_link_service.dart';
import 'group_details_page.dart';

class MyActiveGroupsPage extends StatelessWidget {
  const MyActiveGroupsPage({
    super.key,
    required this.userId,
    required this.repository,
    required this.inviteLinkService,
  });

  final String userId;
  final LotteryGroupRepository repository;
  final GroupInviteLinkService inviteLinkService;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('הקבוצות שלי'),
      ),
      body: StreamBuilder<List<UserGroupListItem>>(
        stream: repository.watchGroupsForUser(userId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final List<UserGroupListItem> items = snapshot.data!;
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'אין קבוצות פעילות להצגה כרגע.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final UserGroupListItem item = items[index];
              return Material(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  title: Text(
                    item.groupName,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('סטטוס קבוצה: ${item.groupStatus}'),
                        Text('התגובה שלי: ${item.responseStatus}'),
                        Text(
                          'מינימום משתתפים: ${item.minimumParticipantsRequired}',
                        ),
                      ],
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => GroupDetailsPage(
                          groupId: item.groupId,
                          currentUserId: userId,
                          inviteLinkService: inviteLinkService,
                          repository: repository,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
