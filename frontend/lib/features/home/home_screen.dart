import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api_client.dart';
import '../../core/push_service.dart';
import '../../core/theme.dart';
import '../../core/ws_service.dart';
import '../../core/widgets/ticker.dart';
import '../auth/auth_repository.dart';
import '../broadcast/broadcast_banner.dart';
import '../chat/chat_repository.dart';
import '../chat/screens/chats_list_screen.dart';
import '../groups/groups_repository.dart';
import '../groups/groups_screen.dart';
import '../settings/ocr_settings_page.dart';

/// Home: live chats list in tab 0; other tabs land in later sprints.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.user});

  final AuthUser user;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  static const _tabs = [
    (icon: Icons.chat_bubble_outline, label: 'المحادثات'),
    (icon: Icons.groups_outlain, label: 'المجموعات'),
    (icon: Icons.campaign_outlined, label: 'التعميمات'),
    (icon: Icons.settings_outlined, label: 'الإعدادات'),
  ];

  @override
  void initState() {
    super.initState();
    // Open the real WebSocket as soon as the user lands on Home
    context.read<WsService>().connect();
    // FCM: register token + wire notification-tap routing
    context.read<PushService>().init();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: MilColors.navyDeep,
        elevation: 0,
        title: Text(
          _tabs[_tab].label,
          style: const TextStyle(
              color: MilColors.gold, fontWeight: FontWeight.w700),
        ),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 16),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: MilColors.navySurface,
              backgroundImage: widget.user.avatarUrl != null
                  ? NetworkImage(widget.user.avatarUrl!)
                  : null,
              child: widget.user.avatarUrl == null
                  ? Text(
                      widget.user.fullName.characters.first,
                      style: const TextStyle(
                          color: MilColors.gold,
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
                1 => GroupsScreen(repo: context.read<GroupsRepository>()),
                2 => const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(_tabs[_tab].icon,
                              size: 64, color: MilColors.goldDim),
                          const SizedBox(height: 16),
                          const Text(
                            'قريباً',
                            style: TextStyle(color: MilColors.textLo),
                          ),
                        ],
                      ),
                    ),
                3 => const OcrSettingsPage(),
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: MilColors.navySurface,
        indicatorColor: MilColors.gold.withValues(alpha: 0.15),
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          for (final t in _tabs)
            NavigationDestination(
              icon: Icon(t.icon, color: MilColors.textLo),
              selectedIcon: Icon(t.icon, color: MilColors.gold),
              label: t.label,
            ),
        ],
      ),
    );
  }
}