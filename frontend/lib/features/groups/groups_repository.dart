import 'package:dio/dio.dart' show Options;

import '../../core/api_client.dart';

class GroupInfo {
  const GroupInfo({
    required this.id,
    required this.name,
    this.description,
    required this.isAnnouncement,
    required this.memberCount,
    this.myRole,
  });

  final String id;
  final String name;
  final String? description;
  final bool isAnnouncement;
  final int memberCount;
  final String? myRole;

  factory GroupInfo.fromJson(Map<String, dynamic> json) => GroupInfo(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        isAnnouncement: (json['is_announcement_group'] as bool?) ?? false,
        memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
        myRole: json['my_role'] as String?,
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
}
