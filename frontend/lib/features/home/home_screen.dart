import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api_client.dart';
import '../../core/crypto/group_signal.dart';
import '../../core/crypto/key_repository.dart';
import '../../core/crypto/signal.dart';
import '../../core/push_service.dart';
import '../../core/theme.dart';
import '../../core/ws_service.dart';
import '../../core/widgets/ticker.dart';
import '../../l10n/app_localizations.dart';
import '../auth/auth_repository.dart';
import '../broadcast/broadcast_banner.dart';
import '../chat/chat_repository.dart';
import '../chat/local/message_store.dart';
import '../chat/screens/chat_room_screen.dart';
import '../chat/screens/message_search_screen.dart';
import '../chat/screens/chats_list_screen.dart';
import '../moderation/moderation_repository.dart';
import '../moderation/screens/blocked_users_screen.dart';
import '../contacts/contact_sync_service.dart';
import '../contacts/contacts_repository.dart';
import '../contacts/screens/contacts_discovery_screen.dart';
import '../groups/groups_repository.dart';
import '../groups/groups_screen.dart';
import '../settings/ocr_settings_page.dart';
import '../../core/icons.dart';

/// Home: live chats list in tab 0; other tabs land in later sprints.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.user});

  final AuthUser user;

  @override
  Widget build(BuildContext context) {
    // Provided here rather than in main.dart because the service is scoped to
    // a signed-in user: its key material belongs to this account, and the
    // store refuses to hand another account's identity to it.
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider(
          create: (ctx) => SignalService(
            user.id,
            keys: KeyRepository(ctx.read<ApiClient>()),
          ),
        ),
        // Shares the pairwise service, because sender keys are distributed
        // over its one-to-one sessions.
        RepositoryProvider(
          create: (ctx) => GroupSignalService(
            userId: user.id,
            pairwise: ctx.read<SignalService>(),
          ),
        ),
      ],
      child: _HomeView(user: user),
    );
  }
}

class _HomeView extends StatefulWidget {
  const _HomeView({required this.user});

  final AuthUser user;

  @override
  State<_HomeView> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<_HomeView> {
  int _tab = 0;

  List<({IconData icon, String label})> _tabs(L t) => [
        (icon: IronIcons.chats, label: t.tabChats),
        (icon: IronIcons.groups, label: t.tabGroups),
        (icon: IronIcons.broadcasts, label: t.tabBroadcasts),
        (icon: IronIcons.settings, label: t.tabSettings),
      ];

  @override
  void initState() {
    super.initState();
    // Open the real WebSocket as soon as the user lands on Home
    context.read<WsService>().connect();
    // FCM: register token + wire notification-tap routing
    context.read<PushService>().init();
    _publishEncryptionKeys();
  }

  /// Generates this device's Signal keys on first launch and publishes the
  /// public half.
  ///
  /// Has to happen here rather than lazily on the first secret chat: a peer
  /// cannot start an encrypted conversation with someone whose bundle the
  /// directory has never seen, so waiting until this user needs it would make
  /// them unreachable until they happened to open a secret chat themselves.
  Future<void> _publishEncryptionKeys() async {
    try {
      await context.read<SignalService>().ensureInstalled();
    } catch (e) {
      // Not fatal and not worth a dialog: normal messaging is unaffected, and
      // the next launch retries. Secret chats surface their own error if the
      // keys really are missing when one is opened.
      debugPrint('[signal] key publish deferred: $e');
    }
  }

  /// Opens the conversation a search hit belongs to.
  ///
  /// Falls back to the peer id when the cached row predates the stored name.
  /// Showing an id is poor, but refusing to open the conversation the user
  /// just tapped would be worse.
  void _openChatWithPeer(String peerId, String? peerName) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatRoomScreen(
          repo: context.read<ChatRepository>(),
          ws: context.read<WsService>(),
          myId: widget.user.id,
          peerId: peerId,
          peerName: peerName ?? peerId,
          peerOnline: false,
          isSecret: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final tabs = _tabs(t);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: IronColors.navyDeep,
        elevation: 0,
        title: Text(
          tabs[_tab].label,
          style: const TextStyle(
              color: IronColors.gold, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (_tab == 0)
            IconButton(
              tooltip: t.searchMessages,
              icon: const Icon(IronIcons.search, size: IronIcons.sizeNav),
              color: IronColors.gold,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MessageSearchScreen(
                    store: context.read<MessageStore>(),
                    onOpenConversation: _openChatWithPeer,
                  ),
                ),
              ),
            ),
          // The settings tab itself is the OCR keyword list, so the blocked
          // list gets its own action rather than being wedged into a page
          // about something else.
          if (_tab == 3)
            IconButton(
              tooltip: t.blockedUsers,
              icon: const Icon(IronIcons.blocked, size: IronIcons.sizeNav),
              color: IronColors.gold,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BlockedUsersScreen(
                    repository: context.read<ModerationRepository>(),
                  ),
                ),
              ),
            ),
          // Finding people belongs beside the conversation list rather than
          // buried in settings — it is what you reach for when the list is
          // empty, which is exactly when it is most needed.
          if (_tab == 0)
            IconButton(
              tooltip: t.contactsTitle,
              icon: const Icon(IronIcons.contacts, size: IronIcons.sizeNav),
              color: IronColors.gold,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ContactsDiscoveryScreen(
                    repository: context.read<ContactsRepository>(),
                    service: context.read<ContactSyncService>(),
                    onOpenChat: (contact) => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatRoomScreen(
                          repo: context.read<ChatRepository>(),
                          ws: context.read<WsService>(),
                          myId: widget.user.id,
                          peerId: contact.userId,
                          peerName: contact.fullName,
                          peerOnline: false,
                          isSecret: false,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 16),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: IronColors.navySurface,
              backgroundImage: widget.user.avatarUrl != null
                  ? NetworkImage(widget.user.avatarUrl!)
                  : null,
              child: widget.user.avatarUrl == null
                  ? Text(
                      widget.user.fullName.characters.first,
                      style: const TextStyle(
                          color: IronColors.gold,
                          fontWeight: FontWeight.w700),
                    )
                  : null,
            ),
          ),
        ],
      ),
      // Urgent broadcasts stack above whatever tab is showing and stay
      // until tapped (server-side ack).
      body: Column(
        children: [
          // News Ticker for OCR alerts
          const NewsTicker(),
          Expanded(
            child: BroadcastBannerHost(
              api: context.read<ApiClient>(),
              ws: context.read<WsService>(),
              child: switch (_tab) {
                0 => ChatsListScreen(
                    repo: context.read<ChatRepository>(),
                    ws: context.read<WsService>(),
                    myId: widget.user.id,
                  ),
                1 => GroupsScreen(
                    repo: context.read<GroupsRepository>(),
                    myId: widget.user.id,
                  ),
                2 => Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(tabs[_tab].icon,
                              size: 64, color: IronColors.goldDim),
                          const SizedBox(height: 16),
                          Text(
                            t.comingSoon,
                            style: const TextStyle(color: IronColors.textLo),
                          ),
                        ],
                      ),
                    ),
                3 => const OcrSettingsPage(),
                _ => const SizedBox.shrink(),
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: IronColors.navySurface,
        indicatorColor: IronColors.gold.withValues(alpha: 0.15),
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          for (final tab in tabs)
            NavigationDestination(
              icon: Icon(tab.icon, color: IronColors.textLo),
              selectedIcon: Icon(tab.icon, color: IronColors.gold),
              label: tab.label,
            ),
        ],
      ),
    );
  }
}