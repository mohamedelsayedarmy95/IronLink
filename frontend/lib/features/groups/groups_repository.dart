import 'package:dio/dio.dart' show Options;

import '../../core/api_client.dart';
import '../../core/crypto/attachment_crypto.dart';

class GroupInfo {
  const GroupInfo({
    required this.id,
    required this.name,
    this.description,
    required this.isAnnouncement,
    required this.memberCount,
    this.myRole,
    this.membersEpoch = 1,
  });

  final String id;
  final String name;
  final String? description;
  final bool isAnnouncement;
  final int memberCount;
  final String? myRole;

  /// Membership version. When this moves, every sender must mint a new
  /// sender key — otherwise whoever just left keeps reading.
  final int membersEpoch;

  bool get canPost => !isAnnouncement || myRole == 'admin' || myRole == 'owner';

  factory GroupInfo.fromJson(Map<String, dynamic> json) => GroupInfo(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        isAnnouncement: (json['is_announcement_group'] as bool?) ?? false,
        memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
        myRole: json['my_role'] as String?,
        membersEpoch: (json['members_epoch'] as num?)?.toInt() ?? 1,
      );
}

class GroupMemberInfo {
  const GroupMemberInfo({
    required this.userId,
    required this.fullName,
    required this.role,
  });

  final String userId;
  final String fullName;
  final String role;

  bool get isAdmin => role == 'admin' || role == 'owner';
  bool get isObserver => role == 'observer';

  factory GroupMemberInfo.fromJson(Map<String, dynamic> json) =>
      GroupMemberInfo(
        userId: json['user_id'] as String,
        fullName: json['full_name'] as String,
        role: json['role'] as String,
      );
}

class GroupsRepository {
  GroupsRepository(this._api);

  final ApiClient _api;

  Future<Options> _auth() async {
    final token = await _api.accessToken;
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  Future<List<GroupInfo>> myGroups() async {
    final res = await _api.dio.get<List<dynamic>>(
      '/groups',
      options: await _auth(),
    );
    return [
      for (final j in res.data ?? [])
        GroupInfo.fromJson(j as Map<String, dynamic>)
    ];
  }

  Future<List<GroupMemberInfo>> members(String groupId) async {
    final res = await _api.dio.get<List<dynamic>>(
      '/groups/$groupId/members',
      options: await _auth(),
    );
    return [
      for (final j in res.data ?? [])
        GroupMemberInfo.fromJson(j as Map<String, dynamic>)
    ];
  }

  /// One group's current state, chiefly so the epoch can be re-checked
  /// before sending. Membership can change while a chat screen is open.
  Future<GroupInfo?> group(String groupId) async {
    final groups = await myGroups();
    for (final g in groups) {
      if (g.id == groupId) return g;
    }
    // Not in the list means no longer a member.
    return null;
  }

  Future<List<GroupChatMessage>> history(String groupId,
      {required String myId, int limit = 50}) async {
    final res = await _api.dio.get<List<dynamic>>(
      '/groups/$groupId/messages',
      queryParameters: {'limit': limit},
      options: await _auth(),
    );
    return [
      for (final j in res.data ?? [])
        GroupChatMessage.fromJson(j as Map<String, dynamic>, myId: myId)
    ];
  }

  Future<void> leave(String groupId) async {
    await _api.dio.delete<void>(
      '/groups/$groupId/members/me',
      options: await _auth(),
    );
  }

  Future<void> removeMember(String groupId, String userId) async {
    await _api.dio.delete<void>(
      '/groups/$groupId/members/$userId',
      options: await _auth(),
    );
  }
}

/// A message in a group, as it arrives from the server.
///
/// Its content is a sender-key ciphertext until the group service opens it.
class GroupChatMessage {
  GroupChatMessage({
    required this.id,
    required this.senderId,
    required this.content,
    required this.createdAt,
    required this.isMine,
    this.kind = 'text',
    this.deleted = false,
    this.pending = false,
    this.encrypted = false,
    this.senderName,
    this.mediaKey,
    this.attachmentKey,
    this.duration,
    this.waveform,
  });

  final String id;
  final String senderId;
  String? content;
  final DateTime createdAt;
  final bool isMine;
  final String kind;
  final bool deleted;
  bool pending;

  /// Whether this message actually arrived encrypted and was verified.
  bool encrypted;

  /// Filled in from the member list. Groups show who is speaking, which a
  /// one-to-one chat does not need.
  String? senderName;

  /// Where an attachment's body is stored.
  ///
  /// Arrives inside the group envelope rather than as a wire field, so the
  /// server cannot tell which stored object a given group message refers to.
  String? mediaKey;

  /// Opens that body. One key per attachment, carried in the same envelope —
  /// which means one attachment encryption for the whole group, not one per
  /// member.
  AttachmentKey? attachmentKey;

  /// Voice notes only.
  double? duration;
  List<double>? waveform;

  factory GroupChatMessage.fromJson(Map<String, dynamic> json,
          {required String myId}) =>
      GroupChatMessage(
        id: json['id'] as String,
        senderId: json['sender_id'] as String,
        content: json['content_ciphertext'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        isMine: json['sender_id'] == myId,
        kind: json['message_type'] as String? ?? 'text',
        deleted: (json['deleted_for_everyone'] as bool?) ?? false,
      );
}
