import 'package:dio/dio.dart' show Options;

import '../../core/api_client.dart';
import '../../core/crypto/attachment_crypto.dart';

enum MessageTick { sent, delivered, read }

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.senderId,
    required this.content,
    required this.createdAt,
    required this.isMine,
    this.kind = 'text',
    this.tick = MessageTick.sent,
    this.deleted = false,
    this.pending = false,
    this.failed = false,
    this.replyToId,
    this.mediaKey,
    this.attachmentKey,
    this.encrypted = false,
    this.duration,
    this.waveform,
  });

  final String id;
  final String senderId;
  String? content;
  final DateTime createdAt;
  final bool isMine;
  String kind; // 'text' | 'voice' | 'image' | ...

  /// Where the body is stored. For a secret chat this arrives inside the
  /// encrypted envelope rather than as a field on the wire.
  String? mediaKey;

  /// Set when the stored body is encrypted.
  ///
  /// Persisted with the cached message. That is not a weakening: the cache
  /// already holds the decrypted message text, so withholding the key would
  /// protect nothing while making attachments unreadable after a restart —
  /// the ratchet cannot re-derive them. Secret chats are never cached at all,
  /// which is the case where keeping nothing on the device is the point.
  AttachmentKey? attachmentKey;

  /// Whether this message actually arrived end-to-end encrypted and was
  /// verified.
  ///
  /// Not "was this chat encrypted" but "was this message" — during the
  /// transition to encryption-by-default a conversation can hold both, and
  /// the bubble marks the ones that were not protected. Defaults to false so
  /// that anything which forgets to set it is treated as unprotected rather
  /// than claiming a guarantee it never had.
  final bool encrypted;

  /// Voice notes only: length in seconds, and the bars to draw under it.
  final double? duration;
  final List<double>? waveform;
  MessageTick tick;
  bool deleted;
  bool pending; // optimistic — awaiting server ack

  /// The outbox gave up on this one.
  ///
  /// Set when the server refuses the frame, or when it survives too many
  /// reconnects unacknowledged, or when it is trimmed from a full queue. It
  /// exists because the alternative is what this product used to do: leave the
  /// bubble sitting in the conversation looking sent, which is a lie the
  /// sender has no way to detect.
  bool failed;

  /// The message this one answers, by id.
  ///
  /// An id and never the quoted text. The server has never held the text —
  /// it stores ciphertext and has no key — so the quotation is resolved from
  /// this device's own decrypted history when the bubble is drawn. On a fresh
  /// install the original is simply not here, and the bubble says so rather
  /// than rendering an empty quote.
  final String? replyToId;

  factory ChatMessage.fromJson(Map<String, dynamic> json,
      {required String myId}) {
    final status = json['status'] as String? ?? 'sent';
    return ChatMessage(
      id: json['id'] as String,
      senderId: (json['sender_id'] ?? '') as String,
      content: json['content_ciphertext'] as String?,
      replyToId: json['reply_to_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      isMine: json['sender_id'] == myId,
      kind: json['kind'] as String? ?? 'text',
      tick: switch (status) {
        'read' => MessageTick.read,
        'delivered' => MessageTick.delivered,
        _ => MessageTick.sent,
      },
      deleted: (json['deleted_for_everyone'] as bool?) ?? false,
      mediaKey: json['media_object_key'] as String?,
    );
  }
}

class Conversation {
  const Conversation({
    required this.peerId,
    required this.peerName,
    required this.isOnline,
    this.lastMessagePreview,
    this.lastMessageAt,
    this.unreadCount = 0,
  });

  final String peerId;
  final String peerName;
  final bool isOnline;
  final String? lastMessagePreview;
  final DateTime? lastMessageAt;
  final int unreadCount;

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        peerId: json['peer_id'] as String,
        peerName: json['peer_name'] as String,
        isOnline: (json['is_online'] as bool?) ?? false,
        lastMessagePreview: json['last_message_preview'] as String?,
        lastMessageAt: json['last_message_at'] != null
            ? DateTime.parse(json['last_message_at'] as String)
            : null,
        unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      );
}

class ChatRepository {
  ChatRepository(this._api);

  final ApiClient _api;

  Future<Options> _auth() async {
    final token = await _api.accessToken;
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  Future<List<Conversation>> conversations() async {
    final res = await _api.dio.get<List<dynamic>>(
      '/chats',
      options: await _auth(),
    );
    return [
      for (final j in res.data ?? [])
        Conversation.fromJson(j as Map<String, dynamic>)
    ];
  }

  Future<List<ChatMessage>> history(String peerId,
      {required String myId, int limit = 100}) async {
    final res = await _api.dio.get<List<dynamic>>(
      '/chats/$peerId/messages',
      queryParameters: {'limit': limit},
      options: await _auth(),
    );
    return [
      for (final j in res.data ?? [])
        ChatMessage.fromJson(j as Map<String, dynamic>, myId: myId)
    ];
  }

  Future<void> sendTyping(String chatId, bool typing) async {
    await _api.dio.post<void>(
      '/chats/$chatId/typing',
      data: {'typing': typing},
      options: await _auth(),
    );
  }
}