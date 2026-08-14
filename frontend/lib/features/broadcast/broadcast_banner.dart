import 'dart:async';

import 'package:dio/dio.dart' show Options;
import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/ws_service.dart';
import '../../l10n/app_localizations.dart';

class BroadcastItem {
  const BroadcastItem({
    required this.id,
    required this.title,
    required this.body,
  });

  final String id;
  final String title;
  final String body;
}

/// Persistent urgent-broadcast banner stack. Sits above all conversations and
/// each banner stays until the user taps it (server-side ack).
class BroadcastBannerHost extends StatefulWidget {
  const BroadcastBannerHost({
    super.key,
    required this.api,
    required this.ws,
    required this.child,
  });

  final ApiClient api;
  final WsService ws;
  final Widget child;

  @override
  State<BroadcastBannerHost> createState() => _BroadcastBannerHostState();
}

class _BroadcastBannerHostState extends State<BroadcastBannerHost> {
  final List<BroadcastItem> _pending = [];
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _loadUnacked();
    _sub = widget.ws.frames.listen((f) {
      if (f['type'] == 'broadcast') {
        setState(() => _pending.insert(
              0,
              BroadcastItem(
                id: f['broadcast_id'] as String,
                title: f['title'] as String,
                body: f['body'] as String,
              ),
            ));
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _loadUnacked() async {
    try {
      final token = await widget.api.accessToken;
      final res = await widget.api.dio.get<List<dynamic>>(
        '/broadcasts/unacked',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (!mounted) return;
      setState(() {
        _pending
          ..clear()
          ..addAll([
            for (final j in res.data ?? [])
              BroadcastItem(
                id: j['id'] as String,
                title: j['title'] as String,
                body: j['body'] as String,
              ),
          ]);
      });
    } catch (_) {
      // Fetched again on next app open
    }
  }

  Future<void> _ack(BroadcastItem item) async {
    setState(() => _pending.removeWhere((b) => b.id == item.id));
    try {
      final token = await widget.api.accessToken;
      await widget.api.dio.post<void>(
        '/broadcasts/${item.id}/ack',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (_) {
      // Unacked server-side → reappears next launch; acceptable
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final item in _pending)
          _UrgentBanner(item: item, onTap: () => _showAndAck(item)),
        Expanded(child: widget.child),
      ],
    );
  }

  void _showAndAck(BroadcastItem item) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: IronColors.navySurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: IronColors.gold),
        ),
        title: Row(
          children: [
            const Icon(Icons.campaign, color: IronColors.gold),
            const SizedBox(width: 10),
            Expanded(
              child: Text(item.title,
                  style: const TextStyle(color: IronColors.gold)),
            ),
          ],
        ),
        content: Text(item.body,
            style: const TextStyle(color: IronColors.textHi)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _ack(item);
            },
            child: Text(L.of(context).acknowledged,
                style: const TextStyle(color: IronColors.gold)),
          ),
        ],
      ),
    );
  }
}

class _UrgentBanner extends StatelessWidget {
  const _UrgentBanner({required this.item, required this.onTap});

  final BroadcastItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: IronColors.errorRed,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            border: BorderDirectional(
              bottom: BorderSide(color: IronColors.gold, width: 1.5),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.campaign, color: IronColors.gold, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: IronColors.textHi,
                            fontWeight: FontWeight.w800,
                            fontSize: 14)),
                    Text(item.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: IronColors.textHi, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.touch_app_outlined,
                  color: IronColors.gold, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
