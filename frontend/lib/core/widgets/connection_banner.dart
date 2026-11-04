import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme.dart';
import '../ws_service.dart';

/// Tells the user when what they are looking at is not live.
///
/// THE GAP THIS CLOSES
///
/// Not one screen in the product distinguished cached data from live data.
/// `WsStatus` existed and had no consumer outside the transport, which meant a
/// user reading a conversation on a dead connection saw exactly what they would
/// see on a good one — and a user whose build the server had refused was simply
/// told nothing at all, forever.
///
/// WHY IT WAITS BEFORE SAYING ANYTHING
///
/// A phone reconnects constantly. Moving between rooms, switching from WiFi to
/// mobile, coming back from the lock screen — each of those is a brief drop and
/// recovery. A banner that appears on every one of them makes a working app
/// feel broken, and it trains people to ignore the banner by the time it means
/// something.
///
/// So a reconnect has [_settleDelay] to succeed before anything is drawn.
/// Below that threshold the user was never disconnected in any sense they would
/// recognise.
///
/// WHAT IT NEVER DOES
///
/// It never shows a "connected" state. A persistent green badge saying the
/// thing that is true 99% of the time is decoration that costs a row of pixels
/// on every screen and tells nobody anything. Silence is the healthy state.
///
/// It never blocks. The conversation renders underneath, the composer still
/// works, and messages written during an outage are queued by the outbox rather
/// than refused — so the banner is information, not a gate.
class ConnectionBanner extends StatefulWidget {
  const ConnectionBanner({super.key, required this.ws});

  final WsService ws;

  /// How long a drop may last before the user is told about it.
  ///
  /// Two seconds is long enough to cover an ordinary handover and short enough
  /// that a real outage does not go unmentioned while somebody waits for a
  /// message to send.
  static const settleDelay = Duration(seconds: 2);

  @override
  State<ConnectionBanner> createState() => _ConnectionBannerState();
}

class _ConnectionBannerState extends State<ConnectionBanner> {
  WsStatus _status = WsStatus.connected;
  bool _settled = true;
  StreamSubscription<WsStatus>? _sub;
  Timer? _settleTimer;

  @override
  void initState() {
    super.initState();
    _sub = widget.ws.status.listen(_onStatus);
  }

  void _onStatus(WsStatus status) {
    _settleTimer?.cancel();

    if (status == WsStatus.connected) {
      // Recovery is immediate and silent. Making the user watch a banner
      // disappear on a delay would be drawing attention to the moment things
      // started working again, which nobody needs.
      setState(() {
        _status = status;
        _settled = true;
      });
      return;
    }

    // An outdated client is terminal — the transport has stopped retrying,
    // because the server will refuse this build every time. There is nothing
    // to wait out, so it is said at once.
    if (status == WsStatus.outdated) {
      setState(() {
        _status = status;
        _settled = false;
      });
      return;
    }

    setState(() => _status = status);
    _settleTimer = Timer(ConnectionBanner.settleDelay, () {
      if (mounted) setState(() => _settled = false);
    });
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_settled || _status == WsStatus.connected) {
      return const SizedBox.shrink();
    }

    final t = L.of(context);
    final outdated = _status == WsStatus.outdated;

    final message = switch (_status) {
      WsStatus.outdated => t.connectionOutdated,
      WsStatus.offline => t.connectionOffline,
      WsStatus.connecting => t.connectionConnecting,
      WsStatus.connected => '',
    };

    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        color: (outdated ? IronColors.semanticError : IronColors.semanticWarning)
            .withValues(alpha: 0.14),
        child: Row(
          children: [
            Icon(
              // Two different icons rather than one in two colours: the
              // difference between "wait" and "act" must survive a screenshot
              // in greyscale and a reader who cannot distinguish the hues.
              outdated ? Icons.system_update_alt : Icons.cloud_off_rounded,
              size: 16,
              color:
                  outdated ? IronColors.semanticError : IronColors.semanticWarning,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: IronTypography.labelSmall(color: IronColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
