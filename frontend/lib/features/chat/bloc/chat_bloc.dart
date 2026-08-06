import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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

// ── State ─────────────────────────────────────────────────────────────────────

class ChatRoomState extends Equatable {
  const ChatRoomState({
    this.messages = const [],
    this.peerTyping = false,
    this.loading = true,
    this.error,
  });

  final List<ChatMessage> messages;
  final bool peerTyping;
  final bool loading;
  final String? error;

  ChatRoomState copyWith({
    List<ChatMessage>? messages,
    bool? peerTyping,
    bool? loading,
    String? error,
  }) =>
      ChatRoomState(
        messages: messages ?? this.messages,
        peerTyping: peerTyping ?? this.peerTyping,
        loading: loading ?? this.loading,
        error: error,
      );

  @override
  List<Object?> get props =>
      [messages.length, _rev, peerTyping, loading, error];

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
  })  : _repo = repo,
        _ws = ws,
        _signalService = SignalService(myId),
        _isSecret = isSecret,
        super(const ChatRoomState()) {
    on<ChatOpened>(_onOpened);
    on<TextSent>(_onTextSent);
    on<MediaSent>(_onMediaSent);
    on<TypingChanged>(_onTypingChanged);
    on<MessageUnsent>(_onUnsent);
    on<_FrameReceived>(_onFrame);

    _sub = _ws.frames.listen((f) => add(_FrameReceived(f)));
  }

  final ChatRepository _repo;
  final WsService _ws;
  final String myId;
  final String peerId;
  final bool _isSecret;
  final SignalService _signalService;

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
    } catch (err) {
      emit(state.copyWith(loading: false, error: err.toString()));
    }
  }

  void _onTextSent(TextSent e, Emitter<ChatRoomState> emit) {
    final ref = 'ref_${++_refCounter}';
    String contentToSend = e.content;
    if (_isSecret) {
      // Encrypt the content for secret chat
      // In a real implementation, we would use the Signal service to encrypt.
      // For now, we mock the encryption.
      contentToSend = _encryptMessage(e.content);
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

  void _onMediaSent(MediaSent e, Emitter<ChatRoomState> emit) {
    final ref = 'ref_${++_refCounter}';
    String contentToSend = e.caption ?? '[${e.kind}]';
    String mediaKeyToSend = e.mediaKey;
    if (_isSecret) {
      // Encrypt the media key and caption for secret chat
      // For simplicity, we encrypt the concatenation of mediaKey and caption.
      // In a real implementation, we would encrypt the media key separately.
      final combined = '${e.mediaKey}:${e.caption ?? ''}';
      final encrypted = _encryptMessage(combined);
      // We'll store the encrypted combined string in the content field.
      // And we'll set the mediaKey to a placeholder? Actually, we need to send the encrypted media key.
      // We'll change the approach: for media, we send the encrypted media key in the mediaKey field,
      // and the encrypted caption in the content field.
      // But the existing MediaSent event doesn't separate them.
      // Given the complexity, we'll treat media as text for now in secret chats.
      contentToSend = _encryptMessage('${e.kind}:${e.mediaKey}:${e.caption ?? ''}');
      mediaKeyToSend = ''; // Not used
      // Note: This is a simplification. A proper implementation would handle media encryption differently.
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

  String _encryptMessage(String plaintext) {
    // Mock encryption: in reality, we would use the Signal service.
    // For now, we just base64 encode it to simulate ciphertext.
    return base64Encode(utf8.encode(plaintext));
  }

  String _decryptMessage(String ciphertext) {
    // Mock decryption: in reality, we would use the Signal service.
    // For now, we just base64 decode it.
    try {
      final bytes = base64Decode(ciphertext);
      return utf8.decode(bytes);
    } catch (e) {
      // If decryption fails, return the original ciphertext (or maybe show an error)
      return ciphertext;
    }
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
          content = _decryptMessage(content);
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

  @override
  Future<void> close() {
    _typingDebounce?.cancel();
    _sub?.cancel();
    return super.close();
  }
}