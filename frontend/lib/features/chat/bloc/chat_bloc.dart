import 'dart:async';
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;

import '../../../core/api_client.dart';
import '../../../core/crypto/attachment_crypto.dart';
import '../../../core/ws_service.dart';
import '../chat_repository.dart';
import '../local/message_store.dart';
import '../../../core/crypto/key_repository.dart';
import '../../../core/crypto/signal.dart';

// ── Events ─────────────────────────────────────────────────────────────────────

sealed class ChatEvent extends Equatable {
  const ChatEvent();
  @override
  List<Object?> get props => [];
}

class ChatOpened extends ChatEvent {
  const ChatOpened();
}

class TextSent extends ChatEvent {
  const TextSent(this.content, {this.replyTo});
  final String content;

  /// The message being answered, by id.
  final String? replyTo;

  @override
  List<Object?> get props => [content, replyTo];
}

/// The user picked a message to reply to, or dismissed the composer preview.
class ReplyTargetChanged extends ChatEvent {
  const ReplyTargetChanged(this.messageId);
  final String? messageId;
  @override
  List<Object?> get props => [messageId];
}

class MediaSent extends ChatEvent {
  const MediaSent({
    required this.kind,
    required this.mediaKey,
    required this.mimeType,
    this.caption,
    this.attachmentKey,
    this.duration,
    this.waveform,
  });

  final String kind;
  final String mediaKey;
  final String mimeType;
  final String? caption;

  /// Present when the body was encrypted before upload. Carried inside the
  /// Signal envelope, never as a field on the wire.
  final AttachmentKey? attachmentKey;

  /// Voice notes only: length in seconds and the bars to draw. Both are
  /// metadata about the recording, so they travel inside the envelope rather
  /// than as wire fields the server could read.
  final double? duration;
  final List<double>? waveform;

  @override
  List<Object?> get props => [kind, mediaKey];
}

class TypingChanged extends ChatEvent {
  const TypingChanged(this.typing);
  final bool typing;
  @override
  List<Object?> get props => [typing];
}

class MessageUnsent extends ChatEvent {
  const MessageUnsent(this.messageId);
  final String messageId;
  @override
  List<Object?> get props => [messageId];
}

/// The transport gave up on a queued send — refused by the server, or out of
/// retries, or trimmed from a full queue.
class _SendGaveUp extends ChatEvent {
  const _SendGaveUp(this.clientRef);
  final String clientRef;
  @override
  List<Object?> get props => [clientRef];
}

class _FrameReceived extends ChatEvent {
  const _FrameReceived(this.frame);
  final Map<String, dynamic> frame;
  @override
  List<Object?> get props => [frame];
}

// AI Events
class ChatFetchSummaryStarted extends ChatEvent {}
class ChatFetchSummarySuccess extends ChatEvent {
  final String summary;
  const ChatFetchSummarySuccess(this.summary);
  @override
  List<Object?> get props => [summary];
}
class ChatFetchSummaryFailure extends ChatEvent {
  final String error;
  const ChatFetchSummaryFailure(this.error);
  @override
  List<Object?> get props => [error];
}

class ChatGenerateSmartRepliesStarted extends ChatEvent {
  final String context;
  const ChatGenerateSmartRepliesStarted(this.context);
  @override
  List<Object?> get props => [context];
}
class ChatGenerateSmartRepliesSuccess extends ChatEvent {
  final List<String> replies;
  const ChatGenerateSmartRepliesSuccess(this.replies);
  @override
  List<Object?> get props => [replies];
}
class ChatGenerateSmartRepliesFailure extends ChatEvent {
  final String error;
  const ChatGenerateSmartRepliesFailure(this.error);
  @override
  List<Object?> get props => [error];
}

class ChatTranslateMessageStarted extends ChatEvent {
  final String messageId;
  final String text;
  final String targetLang;
  const ChatTranslateMessageStarted({
    required this.messageId,
    required this.text,
    required this.targetLang,
  });
  @override
  List<Object?> get props => [messageId, text, targetLang];
}
class ChatTranslateMessageSuccess extends ChatEvent {
  final String messageId;
  final String translation;
  const ChatTranslateMessageSuccess({
    required this.messageId,
    required this.translation,
  });
  @override
  List<Object?> get props => [messageId, translation];
}
class ChatTranslateMessageFailure extends ChatEvent {
  final String messageId;
  final String error;
  const ChatTranslateMessageFailure({
    required this.messageId,
    required this.error,
  });
  @override
  List<Object?> get props => [messageId, error];
}

class ChatModerateMessageStarted extends ChatEvent {
  final String messageId;
  final String text;
  const ChatModerateMessageStarted({
    required this.messageId,
    required this.text,
  });
  @override
  List<Object?> get props => [messageId, text];
}
class ChatModerateMessageSuccess extends ChatEvent {
  final String messageId;
  final Map<String, double> scores;
  const ChatModerateMessageSuccess({
    required this.messageId,
    required this.scores,
  });
  @override
  List<Object?> get props => [messageId, scores];
}
class ChatModerateMessageFailure extends ChatEvent {
  final String messageId;
  final String error;
  const ChatModerateMessageFailure({
    required this.messageId,
    required this.error,
  });
  @override
  List<Object?> get props => [messageId, error];
}

/// Why a secure chat could not carry a message.
///
/// Distinct cases rather than one flag, because the answers differ: a changed
/// identity needs the user to decide, a peer with no keys cannot be messaged
/// at all, and a failed decrypt affects one message rather than the session.
enum SecureChatError {
  identityChanged,
  peerHasNoKeys,
  encryptFailed,
  decryptFailed,
}

// ── State ─────────────────────────────────────────────────────────────────────

class ChatRoomState extends Equatable {
  const ChatRoomState({
    this.messages = const [],
    this.replyingToId,
    this.peerTyping = false,
    this.loading = true,
    this.error,
    // AI state
    this.summary = '',
    this.summaryLoading = false,
    this.smartReplies = const [],
    this.smartRepliesLoading = false,
    this.translations = const {}, // map messageId -> translation
    this.translationLoading = const {}, // map messageId -> bool
    this.moderationScores = const {}, // map messageId -> scores
    this.moderationLoading = const {}, // map messageId -> bool
    this.secureError,
  });

  final List<ChatMessage> messages;
  final bool peerTyping;
  final bool loading;
  final String? error;

  // AI fields
  final String summary;
  final bool summaryLoading;
  final List<String> smartReplies;
  final bool smartRepliesLoading;
  final Map<String, String> translations;
  final Map<String, bool> translationLoading;
  final Map<String, Map<String, double>> moderationScores;
  final Map<String, bool> moderationLoading;

  /// Set when encryption refused to carry a message. Cleared like [error]:
  /// it describes the last attempt, not a lasting condition.
  final SecureChatError? secureError;

  /// The message the composer is currently answering, if any.
  ///
  /// Held as an id rather than a whole message so it cannot go stale: the
  /// original may be edited, deleted, or retracted while the reply is being
  /// typed, and the preview should follow whatever the history now says.
  final String? replyingToId;

  ChatRoomState copyWith({
    List<ChatMessage>? messages,
    String? replyingToId,
    bool clearReplyingTo = false,
    bool? peerTyping,
    bool? loading,
    String? error,
    String? summary,
    bool? summaryLoading,
    List<String>? smartReplies,
    bool? smartRepliesLoading,
    Map<String, String>? translations,
    Map<String, bool>? translationLoading,
    Map<String, Map<String, double>>? moderationScores,
    Map<String, bool>? moderationLoading,
    SecureChatError? secureError,
  }) =>
      ChatRoomState(
        messages: messages ?? this.messages,
        // `clearReplyingTo` rather than relying on a null argument: sending a
        // reply must be able to clear the target, and `?? this.replyingToId`
        // cannot express "set this to nothing".
        replyingToId:
            clearReplyingTo ? null : (replyingToId ?? this.replyingToId),
        peerTyping: peerTyping ?? this.peerTyping,
        loading: loading ?? this.loading,
        error: error,
        summary: summary ?? this.summary,
        summaryLoading: summaryLoading ?? this.summaryLoading,
        smartReplies: smartReplies ?? this.smartReplies,
        smartRepliesLoading: smartRepliesLoading ?? this.smartRepliesLoading,
        translations: translations ?? this.translations,
        translationLoading: translationLoading ?? this.translationLoading,
        moderationScores: moderationScores ?? this.moderationScores,
        moderationLoading: moderationLoading ?? this.moderationLoading,
        // Not `?? this.secureError` — like `error`, it must not persist into
        // the next state or a one-off failure would look permanent.
        secureError: secureError,
      );

  @override
  List<Object?> get props => [
        messages.length,
        _rev,
        replyingToId,
        peerTyping,
        loading,
        error,
        summary,
        summaryLoading,
        smartReplies,
        smartRepliesLoading,
        secureError,
      ];

  // Revision counter derived from mutable message fields so Equatable notices
  // changes *inside* the list, which it otherwise cannot see: the list
  // identity is unchanged when a message's tick moves.
  //
  // `failed` was missing from this fold and had to be added. Marking a message
  // failed mutates it in place and emits a state whose props were therefore
  // identical, so Equatable reported no change and the failure marker never
  // rendered — the bubble sat there looking sent, which is precisely the lie
  // the failed flag exists to prevent. A state field that the UI reads and
  // this fold does not mention is invisible, and that is easy to miss because
  // the bug looks like a rendering problem rather than an equality one.
  int get _rev => messages.fold(
      0,
      (acc, m) =>
          acc +
          m.tick.index +
          (m.deleted ? 100 : 0) +
          (m.pending ? 1000 : 0) +
          (m.failed ? 10000 : 0));
}

// ── Bloc ──────────────────────────────────────────────────────────────────────

class ChatBloc extends Bloc<ChatEvent, ChatRoomState> {
  ChatBloc({
    required ChatRepository repo,
    required WsService ws,
    required this.myId,
    required this.peerId,
    this.peerName,
    bool isSecret = false,
    bool encrypted = true,
    required String baseUrl,
    required ApiClient api,
    MessageStore? store,
    SignalService? signalService,
  })  : _repo = repo,
        _api = api,
        _ws = ws,
        _store = store,
        _signalService = signalService ??
            SignalService(myId, keys: KeyRepository(api)),
        _isSecret = isSecret,
        // A secret chat is encrypted by definition; the flag only ever adds
        // to the protection, never removes it.
        _encrypted = encrypted || isSecret,
        _baseUrl = baseUrl,
        super(const ChatRoomState()) {
    on<ChatOpened>(_onOpened);
    on<TextSent>(_onTextSent);
    on<ReplyTargetChanged>(_onReplyTargetChanged);
    on<MediaSent>(_onMediaSent);
    on<TypingChanged>(_onTypingChanged);
    on<MessageUnsent>(_onUnsent);
    on<_FrameReceived>(_onFrame);

    // AI events
    on<ChatFetchSummaryStarted>(_onFetchSummaryStarted);
    on<ChatFetchSummarySuccess>(_onFetchSummarySuccess);
    on<ChatFetchSummaryFailure>(_onFetchSummaryFailure);
    on<ChatGenerateSmartRepliesStarted>(_onGenerateSmartRepliesStarted);
    on<ChatGenerateSmartRepliesSuccess>(_onGenerateSmartRepliesSuccess);
    on<ChatGenerateSmartRepliesFailure>(_onGenerateSmartRepliesFailure);
    on<ChatTranslateMessageStarted>(_onTranslateMessageStarted);
    on<ChatTranslateMessageSuccess>(_onTranslateMessageSuccess);
    on<ChatTranslateMessageFailure>(_onTranslateMessageFailure);
    on<ChatModerateMessageStarted>(_onModerateMessageStarted);
    on<ChatModerateMessageSuccess>(_onModerateMessageSuccess);
    on<ChatModerateMessageFailure>(_onModerateMessageFailure);
    on<_SendGaveUp>(_onSendGaveUp);

    _sub = _ws.frames.listen((f) => add(_FrameReceived(f)));
    // A message the outbox gave up on has to stop looking sent. Nothing else
    // will notice: the frame left the queue, so no ack is coming and no error
    // is coming, and without this the bubble waits on its clock forever.
    _droppedSub = _ws.dropped.listen((ref) => add(_SendGaveUp(ref)));
  }

  final ChatRepository _repo;
  final WsService _ws;
  final String myId;
  final String peerId;

  /// Stored alongside cached messages so a search hit can name the
  /// conversation it came from without a network call.
  final String? peerName;

  /// Whether messages are end-to-end encrypted. On by default for every
  /// direct chat — encryption that has to be switched on is encryption most
  /// people never get.
  final bool _encrypted;

  /// The stricter mode: additionally never written to the local cache, so
  /// nothing survives on the device. Costs search and offline history, which
  /// is why it is not the default rather than encryption being opt-in.
  final bool _isSecret;
  final SignalService _signalService;

  /// Local cache that makes search possible. Null when the device could not
  /// open the database — the chat still works, it just is not searchable.
  final MessageStore? _store;

  /// Writes to the cache never block or break the conversation: a full disk
  /// must not stop a message from being displayed. Secret chats are filtered
  /// inside [MessageStore.upsertAll], which refuses to persist them at all.
  void _cache(List<ChatMessage> messages) {
    final store = _store;
    if (store == null || messages.isEmpty) return;
    unawaited(
      store
          .upsertAll(peerId, messages,
              peerName: peerName, isSecret: _isSecret)
          .catchError((Object e) => debugPrint('[cache] $e')),
    );
  }

  final String _baseUrl;
  final ApiClient _api;

  /// Read per request rather than captured once when the bloc is built.
  /// The stored token is refreshed while a chat screen stays open, so a
  /// copy taken at construction goes stale — and it was being constructed
  /// from an empty string, which made every AI call a guaranteed 401.
  Future<Map<String, String>> _authHeaders() async => {
        'Authorization': 'Bearer ${await _api.accessToken ?? ''}',
        'Content-Type': 'application/json',
      };

  StreamSubscription? _sub;
  StreamSubscription? _droppedSub;
  Timer? _typingDebounce;
  int _refCounter = 0;

  /// Decrypts a message that came from server history rather than live.
  ///
  /// Most already-delivered messages are NOT recoverable from the server: the
  /// ratchet advances as messages are processed, and a key that has been used
  /// is deleted — that deletion is what forward secrecy means. Messages that
  /// queued while this device was offline are still unprocessed and do
  /// decrypt here, which is how offline delivery works at all.
  ///
  /// Own sent messages never decrypt from the server, because they were
  /// encrypted to the peer and no sender-side copy exists. They are read from
  /// the local cache instead, which is why that cache is the real history.
  Future<ChatMessage> _decryptHistoric(ChatMessage m) async {
    if (!_encrypted || !SignalService.isEnvelope(m.content)) {
      // Predates encryption, or a peer on an older build. Shown, but the
      // bubble marks it as unprotected.
      return m;
    }
    if (m.isMine) {
      m.content = null;
      return m;
    }
    try {
      m.content = await _signalService.decrypt(m.content!, peerId);
      return ChatMessage(
        id: m.id,
        senderId: m.senderId,
        content: m.content,
        createdAt: m.createdAt,
        isMine: m.isMine,
        kind: m.kind,
        tick: m.tick,
        deleted: m.deleted,
        mediaKey: m.mediaKey,
        encrypted: true,
      );
    } catch (_) {
      // Already consumed, or not for this device. Not an error worth
      // shouting about — it is the expected cost of forward secrecy.
      m.content = null;
      return m;
    }
  }

  Future<void> _onOpened(ChatOpened e, Emitter<ChatRoomState> emit) async {
    // The local cache first: it holds already-decrypted plaintext, is the
    // only place own sent messages survive, and works with no network.
    final cached = await _store?.conversation(peerId) ?? const <ChatMessage>[];
    if (cached.isNotEmpty) {
      emit(state.copyWith(messages: cached, loading: false));
    }

    try {
      final remote = await _repo.history(peerId, myId: myId);
      final known = {for (final m in cached) m.id};

      final merged = [...cached];
      for (final m in remote) {
        // Anything already cached was decrypted when it arrived; decrypting
        // it again would fail and would count as a replay.
        if (known.contains(m.id)) continue;
        merged.add(await _decryptHistoric(m));
      }
      merged.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      final history = merged;
      emit(state.copyWith(messages: history, loading: false));
      _cache(history);
      // Everything from the peer that we just displayed is now read
      for (final m in history.where((m) => !m.isMine && m.tick != MessageTick.read)) {
        _ws.sendRead(m.id);
      }
      // Summarising used to fire automatically here whenever more than 20
      // messages were unread — which sent the conversation to a third party
      // on merely opening a chat, with nobody having asked for it and nobody
      // told. It is now something the user requests, and only after everyone
      // in the conversation has agreed.
    } catch (err) {
      // Cached messages stay on screen: being offline should not empty a
      // conversation the device can already display.
      emit(state.copyWith(loading: false, error: err.toString()));
    }
  }

  void _onReplyTargetChanged(
    ReplyTargetChanged e,
    Emitter<ChatRoomState> emit,
  ) {
    emit(state.copyWith(
      replyingToId: e.messageId,
      clearReplyingTo: e.messageId == null,
    ));
  }

  void _onTextSent(TextSent e, Emitter<ChatRoomState> emit) async {
    final ref = 'ref_${++_refCounter}';
    String contentToSend = e.content;

    if (_encrypted) {
      try {
        // Opens the session on first use. Encryption failures are NOT
        // swallowed: sending plaintext from a screen the user believes is
        // encrypted is the worst outcome available here, so the send is
        // abandoned and the reason surfaced instead.
        contentToSend = await _signalService.encrypt(e.content, peerId);
      } on IdentityChanged {
        emit(state.copyWith(secureError: SecureChatError.identityChanged));
        return;
      } on PeerHasNoKeys {
        emit(state.copyWith(secureError: SecureChatError.peerHasNoKeys));
        return;
      } catch (err) {
        debugPrint('[signal] encrypt failed: $err');
        emit(state.copyWith(secureError: SecureChatError.encryptFailed));
        return;
      }
    }

    // Optimistic bubble — replaced by the server ack.
    //
    // Shows e.content, not contentToSend: once encryption is on, the latter
    // is the ciphertext envelope, and the sender would watch their own
    // message appear as a blob of JSON.
    final optimistic = ChatMessage(
      id: ref,
      senderId: myId,
      content: e.content,
      createdAt: DateTime.now(),
      isMine: true,
      pending: true,
      encrypted: _encrypted,
      replyToId: e.replyTo,
    );
    _ws.sendText(
      to: peerId,
      content: contentToSend,
      clientRef: ref,
      replyTo: e.replyTo,
    );
    // Send typing_stop via HTTP when sending a message
    _repo.sendTyping(peerId, false);
    emit(state.copyWith(
      messages: [...state.messages, optimistic],
      clearReplyingTo: true,
    ));
  }

  void _onMediaSent(MediaSent e, Emitter<ChatRoomState> emit) async {
    final ref = 'ref_${++_refCounter}';
    String contentToSend = e.caption ?? '[${e.kind}]';
    String mediaKeyToSend = e.mediaKey;

    // What actually goes on the wire as the message body. Kept separate from
    // `contentToSend`, which is what the local bubble shows: the previous
    // code encrypted into `contentToSend` and then handed sendMedia the
    // plaintext caption anyway, so the caption left the device in the clear.
    String? wireContent = e.caption;

    if (_encrypted) {
      // The pointer, the caption, the real MIME type and the attachment's
      // decryption key all travel together inside one envelope. The key in
      // particular must never reach the server: with it, the stored object
      // stops being opaque.
      //
      // JSON rather than the "$mediaKey:$caption" concatenation this used to
      // be — that had no room for key material, and a caption containing a
      // colon split in the wrong place.
      final payload = jsonEncode({
        'media_key': e.mediaKey,
        'caption': e.caption,
        'mime': e.mimeType,
        if (e.attachmentKey != null) 'att': e.attachmentKey!.toJson(),
        if (e.duration != null) 'dur': e.duration,
        if (e.waveform != null) 'wave': e.waveform,
      });
      try {
        wireContent = await _signalService.encrypt(payload, peerId);
      } on IdentityChanged {
        emit(state.copyWith(secureError: SecureChatError.identityChanged));
        return;
      } on PeerHasNoKeys {
        emit(state.copyWith(secureError: SecureChatError.peerHasNoKeys));
        return;
      } catch (err) {
        debugPrint('[signal] media encrypt failed: $err');
        emit(state.copyWith(secureError: SecureChatError.encryptFailed));
        return;
      }
      mediaKeyToSend = ''; // carried inside the envelope instead
    }

    final optimistic = ChatMessage(
      id: ref,
      senderId: myId,
      content: contentToSend,
      createdAt: DateTime.now(),
      isMine: true,
      kind: e.kind,
      pending: true,
      encrypted: _encrypted,
      mediaKey: e.mediaKey,
      attachmentKey: e.attachmentKey,
    );
    _ws.sendMedia(
      to: peerId,
      kind: e.kind,
      mediaKey: mediaKeyToSend,
      mimeType: e.mimeType,
      caption: wireContent,
      clientRef: ref,
    );
    // Send typing_stop via HTTP when sending a message
    _repo.sendTyping(peerId, false);
    emit(state.copyWith(messages: [...state.messages, optimistic]));
  }

  // Fable5-Enhancement: typing_stop auto-fires after 3s of silence via a
  // debounce here, so a user who stops mid-sentence doesn't stay "typing"
  // forever on the peer's screen.
  void _onTypingChanged(TypingChanged e, Emitter<ChatRoomState> emit) {
    // Send typing indicator via HTTP endpoint (not WebSocket)
    _repo.sendTyping(peerId, e.typing);
    _typingDebounce?.cancel();
    if (e.typing) {
      _typingDebounce = Timer(const Duration(seconds: 3),
          () => _repo.sendTyping(peerId, false));
    }
  }

  void _onUnsent(MessageUnsent e, Emitter<ChatRoomState> emit) {
    _ws.unsend(e.messageId);
    // Optimistically tombstone locally; server broadcast confirms for peer
    final updated = [...state.messages];
    for (final m in updated.where((m) => m.id == e.messageId)) {
      m.deleted = true;
      m.content = null;
    }
    emit(state.copyWith(messages: updated));
    // Re-cached so the retracted text stops matching searches. upsertAll
    // stores null content for a deleted message, which is the point.
    _cache([
      for (final m in updated)
        if (m.id == e.messageId) m
    ]);
  }

  void _onSendGaveUp(_SendGaveUp e, Emitter<ChatRoomState> emit) {
    emit(state.copyWith(messages: [
      for (final m in state.messages)
        if (m.id == e.clientRef) (m..failed = true) else m,
    ]));
  }

  Future<void> _onFrame(_FrameReceived e, Emitter<ChatRoomState> emit) async {
    final f = e.frame;
    switch (f['type']) {
      case 'ack':
        final ref = f['client_ref'] as String?;
        final updated = [
          for (final m in state.messages)
            if (m.id == ref)
              // Carries the media fields and the encrypted flag across:
              // rebuilding from scratch here used to drop them, which blanked
              // the sender's own attachment the moment the ack arrived.
              ChatMessage(
                id: f['message_id'] as String,
                senderId: myId,
                content: m.content,
                createdAt: DateTime.parse(f['created_at'] as String),
                isMine: true,
                kind: m.kind,
                mediaKey: m.mediaKey,
                attachmentKey: m.attachmentKey,
                encrypted: m.encrypted,
              )
            else
              m
        ];
        emit(state.copyWith(messages: updated));
        // Cached only now, not at send time: before the ack the message has
        // a client ref rather than its real id, and caching that would leave
        // a row search could never match back to the conversation.
        _cache([
          for (final m in updated)
            if (m.id == f['message_id']) m
        ]);

      case 'message':
        if (f['from'] != peerId) return; // other conversation

        // Second line of defence behind the server's idempotency key. A
        // reconnect can redeliver a frame the socket had already carried, and
        // showing the same message twice is the visible symptom users would
        // report. Cheap to check, and it costs nothing when it never happens.
        final incomingId = f['message_id'] as String?;
        if (incomingId != null &&
            state.messages.any((m) => m.id == incomingId)) {
          return;
        }
        String? content = f['content'] as String?;

        // Encrypted unless it demonstrably is not. See _isEnvelope: a message
        // that never went through the ratchet is shown, but marked, rather
        // than silently rendered as though it had been verified.
        var wasEncrypted = false;

        if (_encrypted) {
          if (SignalService.isEnvelope(content)) {
            try {
              content = await _signalService.decrypt(content!, peerId);
              wasEncrypted = true;
            } on DuplicateMessageException {
              // The ratchet already processed this one. Dropping it is the
              // point — showing it twice is what a replay wants.
              return;
            } catch (err) {
              debugPrint('[signal] decrypt failed: $err');
              // Never fall back to the raw bytes: rendering ciphertext, or
              // an attacker's plaintext, as a normal bubble misrepresents
              // what was actually verified.
              content = null;
              emit(state.copyWith(secureError: SecureChatError.decryptFailed));
            }
          }
          // Not an envelope: either a message from before this device had a
          // session, or a peer on an older build. Shown with an explicit
          // "not encrypted" marker on the bubble, so a stripped message can
          // never pass as a protected one.
        }

        final kind = f['kind'] as String? ?? 'text';
        String? mediaKey = f['media_key'] as String?;
        AttachmentKey? attachmentKey;
        double? duration;
        List<double>? waveform;

        // A secret media message carries its pointer and key inside the
        // envelope rather than in wire fields, so they have to be unpacked
        // after decryption before the message means anything.
        if (wasEncrypted && kind != 'text' && content != null) {
          try {
            final payload = jsonDecode(content) as Map<String, dynamic>;
            mediaKey = payload['media_key'] as String?;
            content = payload['caption'] as String?;
            final att = payload['att'];
            if (att != null) {
              attachmentKey =
                  AttachmentKey.fromJson(att as Map<String, dynamic>);
            }
            duration = (payload['dur'] as num?)?.toDouble();
            waveform = [
              for (final v in (payload['wave'] as List<dynamic>? ?? const []))
                (v as num).toDouble()
            ];
          } catch (err) {
            debugPrint('[signal] media envelope malformed: $err');
            content = null;
            emit(state.copyWith(secureError: SecureChatError.decryptFailed));
          }
        }

        final msg = ChatMessage(
          id: f['message_id'] as String,
          senderId: f['from'] as String,
          content: content,
          createdAt: DateTime.parse(f['created_at'] as String),
          isMine: false,
          mediaKey: mediaKey,
          attachmentKey: attachmentKey,
          encrypted: wasEncrypted,
          duration: duration,
          waveform: waveform,
          kind: kind,
        );
        emit(state.copyWith(
          messages: [...state.messages, msg],
          peerTyping: false,
        ));
        _cache([msg]);
        // Chat room is open → delivered AND read immediately
        _ws.sendDelivered(msg.id);
        _ws.sendRead(msg.id);

      case 'receipt':
        // Legacy receipt handling (keep for compatibility)
        final id = f['message_id'] as String;
        final tick = f['status'] == 'read'
            ? MessageTick.read
            : MessageTick.delivered;
        final updated = [...state.messages];
        for (final m in updated.where((m) => m.id == id)) {
          // read never downgrades to delivered
          if (tick == MessageTick.read || m.tick == MessageTick.sent) {
            m.tick = tick;
          }
        }
        emit(state.copyWith(messages: updated));

      case 'delivered':
        final id = f['message_id'] as String;
        final updated = [...state.messages];
        for (final m in updated.where((m) => m.id == id)) {
          if (m.tick == MessageTick.sent) {
            m.tick = MessageTick.delivered;
          }
        }
        emit(state.copyWith(messages: updated));

      case 'read':
        final id = f['message_id'] as String;
        final updated = [...state.messages];
        for (final m in updated.where((m) => m.id == id)) {
          if (m.tick == MessageTick.sent || m.tick == MessageTick.delivered) {
            m.tick = MessageTick.read;
          }
        }
        emit(state.copyWith(messages: updated));

      case 'typing_start':
        if (f['from'] == peerId) emit(state.copyWith(peerTyping: true));

      case 'typing_stop':
        if (f['from'] == peerId) emit(state.copyWith(peerTyping: false));

      case 'unsend':
        final id = f['message_id'] as String;
        final updated = [...state.messages];
        for (final m in updated.where((m) => m.id == id)) {
          m.deleted = true;
          m.content = null;
        }
        emit(state.copyWith(messages: updated));
    }
  }

  // === AI Event Handlers ===

  Future<void> _onFetchSummaryStarted(
      ChatFetchSummaryStarted event, Emitter<ChatRoomState> emit) async {
    emit(state.copyWith(summaryLoading: true));
    try {
      // Fetch recent messages from the chat
      final messages = await _repo.history(peerId, myId: myId, limit: 100);
      final messageTexts = messages
          .where((m) => (m.content ?? '').isNotEmpty)
          .map((m) => m.content!)
          .toList();
      if (messageTexts.isEmpty) {
        emit(state.copyWith(summaryLoading: false, summary: ''));
        return;
      }
      // Call AI summary endpoint
      final response = await http.post(
        Uri.parse('$_baseUrl/chats/$peerId/summary'),
        headers: await _authHeaders(),
        body: jsonEncode({
          'messages': messageTexts,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final summary = data['summary'] as String?;
        emit(state.copyWith(summaryLoading: false, summary: summary ?? ''));
      } else {
        throw Exception('Failed to fetch summary');
      }
    } catch (e) {
      emit(state.copyWith(summaryLoading: false, summary: '', error: e.toString()));
    }
  }

  void _onFetchSummarySuccess(
      ChatFetchSummarySuccess event, Emitter<ChatRoomState> emit) {
    emit(state.copyWith(summaryLoading: false, summary: event.summary));
  }

  void _onFetchSummaryFailure(
      ChatFetchSummaryFailure event, Emitter<ChatRoomState> emit) {
    emit(state.copyWith(summaryLoading: false, error: event.error));
  }

  Future<void> _onGenerateSmartRepliesStarted(
      ChatGenerateSmartRepliesStarted event, Emitter<ChatRoomState> emit) async {
    emit(state.copyWith(smartRepliesLoading: true));
    try {
      // Use the last few messages as context
      final messages = await _repo.history(peerId, myId: myId, limit: 10);
      final context = messages.map((m) => m.content).join(' ');
      if (context.trim().isEmpty) {
        emit(state.copyWith(smartRepliesLoading: false, smartReplies: const []));
        return;
      }
      final response = await http.post(
        Uri.parse('$_baseUrl/ai/smart-replies'),
        headers: await _authHeaders(),
        body: jsonEncode({
          'context': context,
          'num_replies': 3,
          // Tells the server which conversation this text came from, so it
          // can check that everyone in it agreed. Without it there is
          // nothing to enforce.
          'peer_id': peerId,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> repliesJson = data['replies'];
        final List<String> replies = repliesJson.cast<String>();
        emit(state.copyWith(smartRepliesLoading: false, smartReplies: replies));
      } else {
        throw Exception('Failed to generate smart replies');
      }
    } catch (e) {
      emit(state.copyWith(smartRepliesLoading: false, smartReplies: const [], error: e.toString()));
    }
  }

  void _onGenerateSmartRepliesSuccess(
      ChatGenerateSmartRepliesSuccess event, Emitter<ChatRoomState> emit) {
    emit(state.copyWith(smartRepliesLoading: false, smartReplies: event.replies));
  }

  void _onGenerateSmartRepliesFailure(
      ChatGenerateSmartRepliesFailure event, Emitter<ChatRoomState> emit) {
    emit(state.copyWith(smartRepliesLoading: false, error: event.error));
  }

  Future<void> _onTranslateMessageStarted(
      ChatTranslateMessageStarted event, Emitter<ChatRoomState> emit) async {
    // Update translation loading flag for this message
    final updatedLoading = Map<String, bool>.from(state.translationLoading)
      ..[event.messageId] = true;
    emit(state.copyWith(translationLoading: updatedLoading));
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/ai/translate'),
        headers: await _authHeaders(),
        body: jsonEncode({
          'text': event.text,
          'target_lang': event.targetLang,
          'peer_id': peerId,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final translation = data['translation'] as String?;
        final updatedTranslations = Map<String, String>.from(state.translations)
          ..[event.messageId] = translation ?? '';
        final updatedLoading = Map<String, bool>.from(state.translationLoading)
          ..[event.messageId] = false;
        emit(state.copyWith(
          translations: updatedTranslations,
          translationLoading: updatedLoading,
        ));
      } else {
        throw Exception('Failed to translate message');
      }
    } catch (e) {
      final updatedLoading = Map<String, bool>.from(state.translationLoading)
        ..[event.messageId] = false;
      emit(state.copyWith(
        translationLoading: updatedLoading,
        error: e.toString(),
      ));
    }
  }

  void _onTranslateMessageSuccess(
      ChatTranslateMessageSuccess event, Emitter<ChatRoomState> emit) {
    final updatedTranslations = Map<String, String>.from(state.translations)
      ..[event.messageId] = event.translation;
    emit(state.copyWith(translations: updatedTranslations));
  }

  void _onTranslateMessageFailure(
      ChatTranslateMessageFailure event, Emitter<ChatRoomState> emit) {
    final updatedLoading = Map<String, bool>.from(state.translationLoading)
      ..[event.messageId] = false;
    emit(state.copyWith(
      translationLoading: updatedLoading,
      error: event.error,
    ));
  }

  Future<void> _onModerateMessageStarted(
      ChatModerateMessageStarted event, Emitter<ChatRoomState> emit) async {
    final updatedLoading = Map<String, bool>.from(state.moderationLoading)
      ..[event.messageId] = true;
    emit(state.copyWith(moderationLoading: updatedLoading));
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/ai/moderate'),
        headers: await _authHeaders(),
        body: jsonEncode({
          'text': event.text,
          'peer_id': peerId,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final Map<String, dynamic> scoresJson = data['scores'];
        final Map<String, double> scores = scoresJson.map((key, value) => MapEntry(key, (value as num).toDouble()));
        final updatedScores = Map<String, Map<String, double>>.from(state.moderationScores)
          ..[event.messageId] = scores;
        final updatedLoading = Map<String, bool>.from(state.moderationLoading)
          ..[event.messageId] = false;
        emit(state.copyWith(
          moderationScores: updatedScores,
          moderationLoading: updatedLoading,
        ));
      } else {
        throw Exception('Failed to moderate message');
      }
    } catch (e) {
      final updatedLoading = Map<String, bool>.from(state.moderationLoading)
        ..[event.messageId] = false;
      emit(state.copyWith(
        moderationLoading: updatedLoading,
        error: e.toString(),
      ));
    }
  }

  void _onModerateMessageSuccess(
      ChatModerateMessageSuccess event, Emitter<ChatRoomState> emit) {
    final updatedScores = Map<String, Map<String, double>>.from(state.moderationScores)
      ..[event.messageId] = event.scores;
    emit(state.copyWith(moderationScores: updatedScores));
  }

  void _onModerateMessageFailure(
      ChatModerateMessageFailure event, Emitter<ChatRoomState> emit) {
    final updatedLoading = Map<String, bool>.from(state.moderationLoading)
      ..[event.messageId] = false;
    emit(state.copyWith(
      moderationLoading: updatedLoading,
      error: event.error,
    ));
  }

  @override
  Future<void> close() {
    _typingDebounce?.cancel();
    _sub?.cancel();
    _droppedSub?.cancel();
    return super.close();
  }
}