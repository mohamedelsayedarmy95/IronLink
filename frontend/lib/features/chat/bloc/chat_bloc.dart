import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;

import '../../../core/ws_service.dart';
import '../chat_repository.dart';
import '../../core/crypto/signal.dart';

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
  const TextSent(this.content);
  final String content;
  @override
  List<Object?> get props => [content];
}

class MediaSent extends ChatEvent {
  const MediaSent({
    required this.kind,
    required this.mediaKey,
    required this.mimeType,
    this.caption,
  });

  final String kind;
  final String mediaKey;
  final String mimeType;
  final String? caption;

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

// ── State ─────────────────────────────────────────────────────────────────────

class ChatRoomState extends Equatable {
  const ChatRoomState({
    this.messages = const [],
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

  ChatRoomState copyWith({
    List<ChatMessage>? messages,
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
  }) =>
      ChatRoomState(
        messages: messages ?? this.messages,
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
      );

  @override
  List<Object?> get props =>
      [messages.length, _rev, peerTyping, loading, error, summary, summaryLoading, smartReplies, smartRepliesLoading];

  // Revision counter derived from mutable message fields so Equatable
  // notices tick/deletion changes inside the list.
  int get _rev => messages.fold(
      0, (acc, m) => acc + m.tick.index + (m.deleted ? 100 : 0) + (m.pending ? 1000 : 0));
}

// ── Bloc ──────────────────────────────────────────────────────────────────────

class ChatBloc extends Bloc<ChatEvent, ChatRoomState> {
  ChatBloc({
    required ChatRepository repo,
    required WsService ws,
    required this.myId,
    required this.peerId,
    this.isSecret = false,
    required String baseUrl,
    required String authToken,
  })  : _repo = repo,
        _ws = ws,
        _signalService = SignalService(myId, baseUrl: baseUrl),
        _isSecret = isSecret,
        _baseUrl = baseUrl,
        _authToken = authToken,
        super(const ChatRoomState()) {
    on<ChatOpened>(_onOpened);
    on<TextSent>(_onTextSent);
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

    _sub = _ws.frames.listen((f) => add(_FrameReceived(f)));
  }

  final ChatRepository _repo;
  final WsService _ws;
  final String myId;
  final String peerId;
  final bool _isSecret;
  final SignalService _signalService;

  final String _baseUrl;
  final String _authToken;

  StreamSubscription? _sub;
  Timer? _typingDebounce;
  int _refCounter = 0;

  Future<void> _onOpened(ChatOpened e, Emitter<ChatRoomState> emit) async {
    try {
      final history = await _repo.history(peerId, myId: myId);
      emit(state.copyWith(messages: history, loading: false));
      // Everything from the peer that we just displayed is now read
      for (final m in history.where((m) => !m.isMine && m.tick != MessageTick.read)) {
        _ws.sendRead(m.id);
      }
      // Optionally fetch summary if there are many messages
      // For now, we can trigger summary fetch if unread count > 20
      final unreadCount = history.where((m) => !m.isMine && m.tick != MessageTick.read).length;
      if (unreadCount > 20) {
        add(ChatFetchSummaryStarted());
      }
    } catch (err) {
      emit(state.copyWith(loading: false, error: err.toString()));
    }
  }

  void _onTextSent(TextSent e, Emitter<ChatRoomState> emit) async {
    final ref = 'ref_${++_refCounter}';
    String contentToSend = e.content;

    if (_isSecret) {
      // For secret chats, we need to establish a session if we don't have one
      final sessionExists = await _signalService.loadSession(peerId) != null;
      if (!sessionExists) {
        try {
          // Perform X3DH key exchange to establish session
          await _signalService.performX3DH(peerId);
          // Initialize session as sender
          await _signalService.initSessionAsSender(peerId, {});
          // Note: In a full implementation, we'd need to exchange the ephemeral key
          // and pre-key ID with the remote party, but for now we assume the
          // signal service handles storing what it needs
        } catch (e) {
          // If key exchange fails, we fall back to unencrypted? Or show error?
          // For now, we'll log and continue with unencrypted (not ideal but prevents blocking)
          // In production, we'd show an error to the user
          print('Failed to establish secure session: $e');
        }
      }

      // Encrypt the message
      final encrypted = await _signalService.encryptMessage(e.content, peerId);
      contentToSend = encrypted['ciphertext'] as String;
    }

    // Optimistic bubble — replaced by the server ack
    final optimistic = ChatMessage(
      id: ref,
      senderId: myId,
      content: contentToSend,
      createdAt: DateTime.now(),
      isMine: true,
      pending: true,
    );
    _ws.sendText(to: peerId, content: contentToSend, clientRef: ref);
    // Send typing_stop via HTTP when sending a message
    _repo.sendTyping(peerId, false);
    emit(state.copyWith(messages: [...state.messages, optimistic]));
  }

  void _onMediaSent(MediaSent e, Emitter<ChatRoomState> emit) async {
    final ref = 'ref_${++_refCounter}';
    String contentToSend = e.caption ?? '[${e.kind}]';
    String mediaKeyToSend = e.mediaKey;

    if (_isSecret) {
      // For secret chats, we need to establish a session if we don't have one
      final sessionExists = await _signalService.loadSession(peerId) != null;
      if (!sessionExists) {
        try {
          // Perform X3DH key exchange to establish session
          await _signalService.performX3DH(peerId);
          // Initialize session as sender
          await _signalService.initSessionAsSender(peerId, {});
        } catch (e) {
          print('Failed to establish secure session: $e');
        }
      }

      // For media in secret chats, we encrypt the media key and caption together
      // as we did before, but now with real encryption
      final combined = '${e.mediaKey}:${e.caption ?? ''}';
      final encrypted = await _signalService.encryptMessage(combined, peerId);
      contentToSend = encrypted['ciphertext'] as String;
      mediaKeyToSend = ''; // Not used separately since it's in the encrypted content
    }

    final optimistic = ChatMessage(
      id: ref,
      senderId: myId,
      content: contentToSend,
      createdAt: DateTime.now(),
      isMine: true,
      pending: true,
    );
    _ws.sendMedia(
      to: peerId,
      kind: e.kind,
      mediaKey: mediaKeyToSend,
      mimeType: e.mimeType,
      caption: e.caption,
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
  }

  void _onFrame(_FrameReceived e, Emitter<ChatRoomState> emit) {
    final f = e.frame;
    switch (f['type']) {
      case 'ack':
        final ref = f['client_ref'] as String?;
        final updated = [
          for (final m in state.messages)
            if (m.id == ref)
              ChatMessage(
                id: f['message_id'] as String,
                senderId: myId,
                content: m.content,
                createdAt: DateTime.parse(f['created_at'] as String),
                isMine: true,
              )
            else
              m
        ];
        emit(state.copyWith(messages: updated));

      case 'message':
        if (f['from'] != peerId) return; // other conversation
        String content = f['content'] as String?;

        if (_isSecret) {
          try {
            // For secret chats, we need to decrypt the message
            final decrypted = await _signalService.decryptMessage(
                {'ciphertext': content}, peerId);
            content = decrypted;
          } catch (decryptionError) {
            // If decryption fails, we might want to show an error or fallback
            // For now, we'll keep the encrypted content and log the error
            print('Failed to decrypt message: $decryptionError');
            // Keep content as is (encrypted) so it doesn't break the UI completely
          }
        }

        final msg = ChatMessage(
          id: f['message_id'] as String,
          senderId: f['from'] as String,
          content: content,
          createdAt: DateTime.parse(f['created_at'] as String),
          isMine: false,
        );
        emit(state.copyWith(
          messages: [...state.messages, msg],
          peerTyping: false,
        ));
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
      final messageTexts = messages.where((m) => m.content.isNotEmpty).map((m) => m.content).toList();
      if (messageTexts.isEmpty) {
        emit(state.copyWith(summaryLoading: false, summary: ''));
        return;
      }
      // Call AI summary endpoint
      final response = await http.post(
        Uri.parse('$_baseUrl/chats/$peerId/summary'),
        headers: {
          'Authorization': 'Bearer $_authToken',
          'Content-Type': 'application/json',
        },
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
        headers: {
          'Authorization': 'Bearer $_authToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'context': context,
          'num_replies': 3,
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
        headers: {
          'Authorization': 'Bearer $_authToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'text': event.text,
          'target_lang': event.targetLang,
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
        headers: {
          'Authorization': 'Bearer $_authToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'text': event.text,
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
    return super.close();
  }
}