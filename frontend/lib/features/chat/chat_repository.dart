import 'package:dio/dio.dart' show Options;

import '../../core/api_client.dart';

enum MessageTick { sent, delivered, read }

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.senderId,
    required this.content,
    required this.createdAt,
    required this.isMine,
    this.tick = MessageTick.sent,
    this.deleted = false,
    this.pending = false,
  });

  final String id;
  final String senderId;
  String? content;
  final DateTime createdAt;
  final bool isMine;
  MessageTick tick;
  bool deleted;
  bool pending; // optimistic — awaiting server ack

  factory ChatMessage.fromJson(Map<String, dynamic> json,
      {required String myId}) {
    final status = json['status'] as String? ?? 'sent';
    return ChatMessage(
      id: json['id'] as String,
      senderId: (json['sender_id'] ?? '') as String,
      content: json['content_ciphertext'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      isMine: json['sender_id'] == myId,
      tick: switch (status) {
        'read' => MessageTick.read,
        'delivered' => MessageTick.delivered,
        _ => MessageTick.sent,
      },
      deleted: (json['deleted_for_everyone'] as bool?) ?? false,
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
      {required String myId}) async {
    final res = await _api.dio.get<List<dynamic>>(
      '/chats/$peerId/messages',
      options: await _auth(),
    );
    return [
      for (final j in res.data ?? [])
        ChatMessage.fromJson(j as Map<String, dynamic>, myId: myId)
    ];
  }
}
