import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api_client.dart';
import '../../../core/crypto/signal.dart';
import '../../../core/env.dart';
import '../../../core/failure.dart';
import '../../../core/media_service.dart';
import '../../../core/theme.dart';
import '../../../core/ws_service.dart';
import '../../../core/widgets/ticker.dart';
import '../../../l10n/app_localizations.dart';
import '../bloc/chat_bloc.dart';
import '../chat_repository.dart';
import '../local/message_store.dart';
import '../widgets/attach_flow.dart';
import '../widgets/encrypted_image.dart';
import '../widgets/smart_replies.dart';
import '../widgets/summary_banner.dart';
import '../widgets/voice_player.dart';
import '../widgets/voice_recorder.dart';
import '../../../core/icons.dart';
import '../../moderation/moderation_repository.dart';
import '../../moderation/screens/blocked_users_screen.dart' show confirmBlock;
import '../../moderation/widgets/report_sheet.dart';
import '../../settings/ocr_settings_page.dart' show failureMessage;

class ChatRoomScreen extends StatelessWidget {
  const ChatRoomScreen({
    super.key,
    required this.repo,
    required this.ws,
    required this.myId,
    required this.peerId,
    required this.peerName,
    required this.peerOnline,
    // Encrypted unless a caller deliberately says otherwise. A protection
    // that has to be switched on is one most people never get.
    this.isSecret = false,
    this.encrypted = true,
  });

  final ChatRepository repo;
  final WsService ws;
  final String myId;
  final String peerId;
  final String peerName;
  final bool peerOnline;

  /// Additionally keeps nothing on the device. Encryption is independent of
  /// this and is on either way.
  final bool isSecret;

  final bool encrypted;

  @override
  Widget build(BuildContext context) {
    final baseUrl = Env.apiBaseUrl;

    return BlocProvider(
      create: (_) => ChatBloc(
        repo: repo,
        ws: ws,
        myId: myId,
        peerId: peerId,
        peerName: peerName,
        isSecret: isSecret,
        encrypted: encrypted,
        baseUrl: baseUrl,
        api: context.read<ApiClient>(),
        store: context.read<MessageStore>(),
        // The one provided at Home, so every chat shares a single key store
        // and session state rather than each screen building its own.
        signalService: context.read<SignalService>(),
      )..add(const ChatOpened()),
      child: _ChatRoomView(
        isSecret: isSecret,
        encrypted: encrypted,
        peerId: peerId,
        peerName: peerName,
        peerOnline: peerOnline,
      ),
    );
  }
}

class _ChatRoomView extends StatefulWidget {
  const _ChatRoomView({
    required this.isSecret,
    required this.encrypted,
    required this.peerId,
    required this.peerName,
    required this.peerOnline,
  });

  final bool isSecret;
  final bool encrypted;
  final String peerId;
  final String peerName;
  final bool peerOnline;

  @override
  State<_ChatRoomView> createState() => _ChatRoomViewState();
}

class _ChatRoomViewState extends State<_ChatRoomView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  /// Null until the block state is known. The composer is not disabled while
  /// it is unknown — guessing "blocked" would silently stop a normal
  /// conversation on a slow network.
  bool? _blocked;

  @override
  void initState() {
    super.initState();
    _loadBlockState();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  ModerationRepository get _moderation => context.read<ModerationRepository>();

  Future<void> _loadBlockState() async {
    try {
      final blocked = await _moderation.isBlocked(widget.peerId);
      if (!mounted) return;
      setState(() => _blocked = blocked);
    } catch (_) {
      // Left unknown on purpose. A failed status check must not decide that
      // someone is blocked.
    }
  }

  Future<void> _toggleBlock() async {
    final t = L.of(context);
    final blocked = _blocked ?? false;

    if (!blocked && !await confirmBlock(context, widget.peerName)) return;
    if (!mounted) return;

    try {
      if (blocked) {
        await _moderation.unblock(widget.peerId);
      } else {
        await _moderation.block(widget.peerId);
      }
      if (!mounted) return;
      setState(() => _blocked = !blocked);
      _toast(blocked
          ? t.userUnblocked(widget.peerName)
          : t.userBlocked(widget.peerName));
    } catch (e) {
      if (!mounted) return;
      _toast(failureMessage(t, NetworkFailureClassifier.from(e)));
    }
  }

  Future<void> _report({String? messageId, String? snapshot}) async {
    final outcome = await showReportSheet(
      context,
      repository: _moderation,
      reportedUserId: widget.peerId,
      reportedUserName: widget.peerName,
      messageId: messageId,
      contentSnapshot: snapshot,
    );
    if (outcome == null || !mounted) return;

    if (outcome.alsoBlocked) setState(() => _blocked = true);
    _toast(L.of(context).reportSubmitted);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: IronColors.navySurface),
    );
  }

  /// Tells the user a message was refused, and why.
  ///
  /// A send that silently does nothing is barely better than a silent
  /// downgrade — in both cases the user believes something happened that did
  /// not. A changed identity gets a dialog rather than a toast because it is
  /// the one case that needs a decision.
  void _showSecureError(SecureChatError error) {
    final t = L.of(context);
    switch (error) {
      case SecureChatError.identityChanged:
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: IronColors.navySurface,
            title: Text(t.secureIdentityChanged,
                style: const TextStyle(color: IronColors.textHi)),
            content: Text(t.secureIdentityChangedBody,
                style: const TextStyle(color: IronColors.textTertiary)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(t.cancel,
                    style: const TextStyle(color: IronColors.textTertiary)),
              ),
            ],
          ),
        );
      case SecureChatError.peerHasNoKeys:
        _toast(t.securePeerHasNoKeys);
      case SecureChatError.encryptFailed:
        _toast(t.secureEncryptFailed);
      case SecureChatError.decryptFailed:
        _toast(t.secureDecryptFailed);
    }
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: IronColors.navySurface,
        elevation: 0,
        shape: const Border(
          bottom: BorderSide(color: IronColors.navyBorder),
        ),
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: IronColors.navyDeep,
                border: Border.all(color: IronColors.navyBorder),
                boxShadow: widget.peerOnline
                    ? [
                        BoxShadow(
                          color: IronColors.gold.withValues(alpha: 0.25),
                          blurRadius: 10,
                        ),
                      ]
                    : null,
              ),
              child: Text(
                widget.peerName.characters.first,
                style: const TextStyle(
                    color: IronColors.gold, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.peerName,
                    style: const TextStyle(
                        fontSize: 16, color: IronColors.textHi)),
                if (widget.peerOnline)
                  Text(t.onlineNow,
                      style: const TextStyle(
                          fontSize: 11, color: IronColors.gold)),
              ],
            ),
          ],
        ),
        actions: [
          // Reports the actual state of this conversation rather than
          // offering a toggle. Switching mid-conversation would leave half
          // the history unencrypted while still claiming to be secret, so
          // the mode is fixed when the chat is opened.
          IconButton(
            tooltip: widget.encrypted ? t.secretChatOn : t.secretChatOff,
            icon: Icon(
              widget.encrypted ? IronIcons.lock : IronIcons.unlock,
              color: widget.encrypted
                  ? IronColors.accentText
                  : IronColors.textTertiary,
            ),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: IronColors.navySurface,
                title: Text(
                  widget.encrypted ? t.secretChatOn : t.secretChatOff,
                  style: const TextStyle(color: IronColors.textHi),
                ),
                content: Text(
                  widget.encrypted
                      ? t.secretChatNotice
                      : t.chatNotEncryptedNotice,
                  style: const TextStyle(color: IronColors.textTertiary),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(t.done,
                        style: const TextStyle(color: IronColors.accentText)),
                  ),
                ],
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(IronIcons.more, color: IronColors.textHi),
            color: IronColors.navySurface,
            onSelected: (value) {
              if (value == 'block') {
                _toggleBlock();
              } else if (value == 'report') {
                // Reporting the person rather than one message: no id and no
                // snapshot, because there is nothing specific to attach.
                _report();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'report',
                child: Row(
                  children: [
                    const Icon(IronIcons.report,
                        size: IronIcons.sizeCompact,
                        color: IronColors.textTertiary),
                    const SizedBox(width: 10),
                    Text(t.reportUser,
                        style: const TextStyle(color: IronColors.textHi)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'block',
                child: Row(
                  children: [
                    const Icon(IronIcons.blocked,
                        size: IronIcons.sizeCompact,
                        color: IronColors.errorRed),
                    const SizedBox(width: 10),
                    Text(
                      (_blocked ?? false) ? t.unblockUser : t.blockUser,
                      style: const TextStyle(color: IronColors.textHi),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // News Ticker for OCR alerts
          const NewsTicker(),
          Expanded(
            child: BlocConsumer<ChatBloc, ChatRoomState>(
              listener: (context, state) {
                _jumpToBottom();
                final secureError = state.secureError;
                if (secureError != null) _showSecureError(secureError);
              },
              builder: (context, state) {
                if (state.loading) {
                  return const Center(
                      child: CircularProgressIndicator(color: IronColors.gold));
                }
                return Column(
                  children: [
                    // AI Summary Banner
                    if (state.summaryLoading)
                      SummaryBanner(
                        summary: '',
                        isLoading: true,
                        onRefresh: () {
                          context.read<ChatBloc>().add(ChatFetchSummaryStarted());
                        },
                      )
                    else if (state.summary.isNotEmpty)
                      SummaryBanner(
                        summary: state.summary,
                        isLoading: false,
                        onRefresh: () {
                          context.read<ChatBloc>().add(ChatFetchSummaryStarted());
                        },
                      )
                    else
                      const SizedBox.shrink(),

                    Expanded(
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(16),
                        itemCount: state.messages.length,
                        itemBuilder: (context, i) {
                          final message = state.messages[i];
                          return _MessageBubble(
                            message: message,
                            onTranslatePressed: (text, targetLang) {
                              // Trigger translation for this message
                              // We need the message ID - we'll pass it via the message object
                              // For simplicity, we'll add a translate method to ChatBloc that takes messageId
                              // But we don't have access to messageId here easily
                              // Let's modify the approach: we'll add a method to the bloc state to translate
                              // For now, we'll just call the bloc event with the text and targetLang
                              // and assume we can get the messageId from somewhere
                              // This is a limitation - in a real implementation we'd pass messageId
                              context.read<ChatBloc>().add(ChatTranslateMessageStarted(
                                messageId: message.id,
                                text: text,
                                targetLang: targetLang,
                              ));
                            },
                            onModeratePressed: (text) {
                              context.read<ChatBloc>().add(ChatModerateMessageStarted(
                                messageId: message.id,
                                text: text,
                              ));
                            },
                            onReportPressed: (messageId, snapshot) =>
                                _report(messageId: messageId, snapshot: snapshot),
                          );
                        },
                      ),
                    ),

                    if (state.peerTyping)
                      _TypingIndicator(peerName: widget.peerName),

                    // Smart Replies
                    if (state.smartReplies.isNotEmpty && !state.smartRepliesLoading)
                      SmartReplies(
                        suggestions: state.smartReplies,
                        onTap: (suggestion) {
                          context.read<ChatBloc>().add(TextSent(suggestion));
                        },
                      ),

                    // The composer is replaced rather than merely disabled:
                    // a greyed-out text field invites the user to keep
                    // tapping it without saying why nothing happens.
                    if (_blocked ?? false)
                      _BlockedBanner(onUnblock: _toggleBlock)
                    else
                      _InputBar(
                        encrypted: widget.encrypted,
                        controller: _input,
                        onChanged: (text) => context
                            .read<ChatBloc>()
                            .add(TypingChanged(text.isNotEmpty)),
                        onSend: () {
                          final text = _input.text.trim();
                          if (text.isEmpty) return;
                          context.read<ChatBloc>().add(TextSent(text));
                          _input.clear();
                        },
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown where the composer would be while this user has the peer blocked.
class _BlockedBanner extends StatelessWidget {
  const _BlockedBanner({required this.onUnblock});

  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: const BoxDecoration(
        color: IronColors.navySurface,
        border: Border(top: BorderSide(color: IronColors.navyBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(IronIcons.blocked,
                    size: IronIcons.sizeCompact, color: IronColors.textTertiary),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    t.blockedBannerTitle,
                    style: const TextStyle(
                        color: IronColors.textHi,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              t.blockedBannerBody,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: IronColors.textTertiary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onUnblock,
              child: Text(t.unblockUser,
                  style: const TextStyle(color: IronColors.accentText)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Message bubble with translate/moderate callbacks ───────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    super.key,
    required this.message,
    required this.onTranslatePressed,
    required this.onModeratePressed,
    required this.onReportPressed,
  });

  final ChatMessage message;
  final void Function(String text, String targetLang) onTranslatePressed;
  final void Function(String text) onModeratePressed;

  /// Carries the decrypted text along with the id: the server holds only
  /// ciphertext it cannot read, so this device is the only place the evidence
  /// exists in a readable form.
  final void Function(String messageId, String? snapshot) onReportPressed;

  static const _slateGrey = Color(0xFF3E4A5C);

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final mine = message.isMine;

    return Align(
      alignment:
          mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: GestureDetector(
        // Available on the peer's messages too. Gating this on `mine` made
        // reporting unreachable for exactly the messages worth reporting.
        onLongPress:
            message.deleted ? null : () => _showMessageOptions(context),
        child: Container(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75),
          margin: const EdgeInsets.only(bottom: 10),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: mine && !message.deleted
                ? const LinearGradient(
                    colors: [IronColors.goldBright, IronColors.gold],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: mine
                ? (message.deleted ? IronColors.navySurface : null)
                : _slateGrey,
            borderRadius: BorderRadiusDirectional.only(
              topStart: const Radius.circular(16),
              topEnd: const Radius.circular(16),
              bottomStart: Radius.circular(mine ? 16 : 4),
              bottomEnd: Radius.circular(mine ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.deleted)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(IronIcons.blocked, size: IronIcons.sizeCompact, color: IronColors.textLo),
                    const SizedBox(width: 6),
                    Text(t.messageDeleted,
                        style: const TextStyle(
                            color: IronColors.textLo,
                            fontStyle: FontStyle.italic,
                            fontSize: 13)),
                  ],
                )
              else
                if (message.kind == 'voice') ...[
                  VoicePlayer(
                    mediaKey: (jsonDecode(message.content ?? '{}') as Map<String, dynamic>)['mediaKey'] as String? ?? '',
                    duration: ((jsonDecode(message.content ?? '{}') as Map<String, dynamic>)['duration'] as num?)?.toDouble() ?? 0,
                    waveform: ((jsonDecode(message.content ?? '{}') as Map<String, dynamic>)['waveform'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList() ?? [],
                  )
                ] else if (message.attachmentKey != null &&
                    message.mediaKey != null) ...[
                  // Fetched and decrypted on the device: the stored object is
                  // ciphertext, so there is no URL that renders directly.
                  EncryptedImage(
                    media: context.read<MediaService>(),
                    mediaKey: message.mediaKey!,
                    attachmentKey: message.attachmentKey!,
                  ),
                  if ((message.content ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      message.content!,
                      style: TextStyle(
                        color: mine ? IronColors.navyDeep : IronColors.textHi,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ] else if (message.content == null) ...[
                  // Content is null on a message that failed to decrypt.
                  // Rendering an empty bubble would read as an empty message
                  // rather than as something that could not be verified.
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(IronIcons.lock,
                          size: IronIcons.sizeCompact,
                          color: IronColors.textLo),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          t.secureMessageUnreadable,
                          style: const TextStyle(
                              color: IronColors.textLo,
                              fontStyle: FontStyle.italic,
                              fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Text(
                    message.content ?? '',
                    style: TextStyle(
                      // Dark bold text on the bright cyan bubble for readability.
                      color: mine ? IronColors.navyDeep : IronColors.textHi,
                      fontWeight: mine ? FontWeight.w600 : FontWeight.w400,
                      fontSize: 15,
                    ),
                  ),
                ],
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Marks a message that did not arrive encrypted. Only the
                  // exception is labelled — badging every protected message
                  // trains people to ignore the badge, which is precisely
                  // when the missing one stops being noticed.
                  if (!message.encrypted && !message.deleted) ...[
                    Tooltip(
                      message: t.messageNotEncrypted,
                      child: Icon(
                        IronIcons.unlock,
                        size: 11,
                        semanticLabel: t.messageNotEncrypted,
                        color: mine
                            ? IronColors.navyDeep.withValues(alpha: 0.6)
                            : IronColors.textLo,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    _time(message.createdAt),
                    style: TextStyle(
                      fontSize: 10,
                      color: mine
                          ? IronColors.navyDeep.withValues(alpha: 0.6)
                          : IronColors.textLo,
                    ),
                  ),
                  if (mine && !message.deleted) ...[
                    const SizedBox(width: 5),
                    _Ticks(tick: message.tick, pending: message.pending),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMessageOptions(BuildContext context) {
    final t = L.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: IronColors.navySurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(IronIcons.translate, color: IronColors.gold),
              title: Text(t.translate),
              onTap: () {
                Navigator.pop(context);
                // For translation, we need to ask for target language
                // For simplicity, we'll use English as default
                final text = message.content ?? '';
                if (text.isNotEmpty) {
                  onTranslatePressed(text, 'eng_Latn'); // English
                }
              },
            ),
            // This runs the AI classifier and shows scores — it never
            // reaches a person. It was previously labelled "report", which
            // told the user they had filed a complaint when they had not.
            ListTile(
              leading: const Icon(IronIcons.info, color: IronColors.gold),
              title: Text(t.analyzeContent),
              onTap: () {
                Navigator.pop(context);
                final text = message.content ?? '';
                if (text.isNotEmpty) {
                  onModeratePressed(text);
                }
              },
            ),
            // Reporting your own message would only report yourself, which
            // the server rejects anyway.
            if (!message.isMine)
              ListTile(
                leading:
                    const Icon(IronIcons.report, color: IronColors.errorRed),
                title: Text(t.reportMessage,
                    style: const TextStyle(color: IronColors.textHi)),
                onTap: () {
                  Navigator.pop(context);
                  onReportPressed(message.id, message.content);
                },
              ),
            if (message.isMine && !message.deleted) ...[
              const Divider(color: IronColors.navyDeep),
              ListTile(
                leading: const Icon(IronIcons.delete,
                    color: IronColors.errorRed),
                title: Text(t.deleteForEveryone,
                    style: const TextStyle(color: IronColors.textHi)),
                subtitle: Text(t.deleteForEveryoneHint,
                    style: const TextStyle(color: IronColors.textLo, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  // Find the bloc and send unsend event
                  context.read<ChatBloc>().add(MessageUnsent(message.id));
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

// ── One grey ����� ��� ��� � ��� � � ✓ (sent) → two grey ����� ��� ��� � ��� � � ✓��������������✓ (delivered) → two GOLD ����� ��� ��� � ��� � � ✓��������������✓ (read).
class _Ticks extends StatelessWidget {
  const _Ticks({required this.tick, required this.pending});

  final MessageTick tick;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final onBubble = IronColors.navyDeep;
    if (pending) {
      return Icon(IronIcons.pending, size: IronIcons.sizeCompact, color: onBubble.withValues(alpha: 0.6));
    }
    final read = tick == MessageTick.read;
    final double single = tick == MessageTick.sent ? 1 : 2;
    return Icon(
      single == 1 ? IronIcons.sent : IronIcons.delivered,
      size: 14,
      color: onBubble.withValues(alpha: read ? 0.85 : 0.6),
      shadows: read
          ? [Shadow(color: IronColors.goldBright.withValues(alpha: 0.5), blurRadius: 4)]
          : null,
    );
  }
}

// ── "typing…" indicator with 3 animated gold dots ─────────────────────────────
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator({required this.peerName});

  final String peerName;

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 20, bottom: 6),
      child: Row(
        children: [
          Text(
            L.of(context).typingIndicator(widget.peerName),
            style: const TextStyle(color: IronColors.gold, fontSize: 13),
          ),
          const SizedBox(width: 6),
          AnimatedBuilder(
            animation: _c,
            builder: (_, __) => Row(
              children: [
                for (var i = 0; i < 3; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: Opacity(
                      opacity: _dotOpacity(i),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: IronColors.gold,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          )
        ]
      ),
    );
  }

  double _dotOpacity(int i) {
    final phase = (_c.value + i * 0.2) % 1.0;
    return 0.25 + 0.75 * (1 - (phase - 0.5).abs() * 2).clamp(0.0, 1.0);
  }
}

// ── Input bar: mic + attach sheet + send ─────────────────────────────────────
class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.onChanged,
    required this.onSend,
    required this.encrypted,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;

  /// Decides whether an attachment is encrypted before upload.
  final bool encrypted;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<ChatBloc>();
    final t = L.of(context);
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: const BoxDecoration(
          color: IronColors.navySurface,
          border: Border(top: BorderSide(color: IronColors.navyBorder)),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: t.attach,
              icon: const Icon(IronIcons.attach, color: IronColors.gold),
              onPressed: () async {
                final media = context.read<MediaService>();
                final result = await showAttachFlow(
                  context,
                  media: media,
                  encrypted: encrypted,
                );
                if (result != null) {
                  bloc.add(MediaSent(
                    kind: 'image',
                    mediaKey: result.mediaKey,
                    mimeType: result.mimeType,
                    caption: result.caption,
                    attachmentKey: result.key,
                  ));
                }
              },
            ),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: t.messageHint,
                  fillColor: IronColors.navyDeep,
                ),
              ),
            ),
            const SizedBox(width: 8),
            VoiceRecorder(
              onSend: (mediaKey, duration, waveform) => bloc.add(MediaSent(
                kind: 'voice',
                mediaKey: mediaKey,
                mimeType: 'audio/opus',
                caption: jsonEncode({
                  'mediaKey': mediaKey,
                  'duration': duration,
                  'waveform': waveform,
                }),
              )),
              onCancel: () {},
            ),
            CircleAvatar(
              backgroundColor: IronColors.gold,
              child: IconButton(
                tooltip: t.send,
                icon: const Icon(IronIcons.send,
                    color: IronColors.navyDeep, size: IronIcons.sizeInline),
                onPressed: onSend,
              ),
            ),
          ],
        ),
      ),
    );
  }
}