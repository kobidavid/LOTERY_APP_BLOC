import 'dart:async';

import 'package:app_links/app_links.dart';

class GroupInviteLink {
  const GroupInviteLink({
    required this.groupId,
    required this.inviteToken,
  });

  final String groupId;
  final String inviteToken;
}

class GroupInviteLinkService {
  static const String _customScheme = 'lotogroup';
  static const String _customHost = 'join-group';
  static const String _httpsScheme = 'https';
  static const String _httpsHost = 'lotogroup-1ea8a.web.app';
  static const String _joinPath = '/join-group';

  GroupInviteLinkService({AppLinks? appLinks})
      : _appLinks = appLinks ?? AppLinks();

  final AppLinks _appLinks;
  final StreamController<GroupInviteLink> _controller =
      StreamController<GroupInviteLink>.broadcast();

  StreamSubscription<Uri>? _subscription;
  GroupInviteLink? _pendingInvite;

  Stream<GroupInviteLink> get inviteStream => _controller.stream;

  Future<void> initialize() async {
    final Uri? initialUri = await _appLinks.getInitialLink();
    _handleUri(initialUri);
    _subscription ??= _appLinks.uriLinkStream.listen(_handleUri);
  }

  Uri buildInviteUri({
    required String groupId,
    required String inviteToken,
  }) {
    return Uri(
      scheme: _httpsScheme,
      host: _httpsHost,
      path: _joinPath,
      queryParameters: <String, String>{
        'groupId': groupId,
        'inviteToken': inviteToken,
      },
    );
  }

  GroupInviteLink? takePendingInvite() {
    final GroupInviteLink? pending = _pendingInvite;
    _pendingInvite = null;
    return pending;
  }

  GroupInviteLink? peekPendingInvite() => _pendingInvite;

  void dispose() {
    _subscription?.cancel();
    _controller.close();
  }

  void _handleUri(Uri? uri) {
    final GroupInviteLink? invite = _parseInvite(uri);
    if (invite == null) {
      return;
    }

    _pendingInvite = invite;
    _controller.add(invite);
  }

  GroupInviteLink? _parseInvite(Uri? uri) {
    if (uri == null) {
      return null;
    }
    final bool matchesCustomScheme =
        uri.scheme == _customScheme && uri.host == _customHost;
    final bool matchesHttpsLink = uri.scheme == _httpsScheme &&
        uri.host == _httpsHost &&
        uri.path == _joinPath;

    if (!matchesCustomScheme && !matchesHttpsLink) {
      return null;
    }

    final String? groupId = uri.queryParameters['groupId'];
    final String? inviteToken = uri.queryParameters['inviteToken'];
    if (groupId == null ||
        groupId.isEmpty ||
        inviteToken == null ||
        inviteToken.isEmpty) {
      return null;
    }

    return GroupInviteLink(
      groupId: groupId,
      inviteToken: inviteToken,
    );
  }
}
