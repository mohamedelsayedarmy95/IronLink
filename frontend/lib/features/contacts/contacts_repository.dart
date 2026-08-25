import 'package:dio/dio.dart' show Options;
import 'package:equatable/equatable.dart';

import '../../core/api_client.dart';

/// Who may find this user by phone number.
enum Discoverability {
  everyone('everyone'),
  contactsOfContacts('contacts_of_contacts'),
  nobody('nobody');

  const Discoverability(this.wire);
  final String wire;

  static Discoverability fromWire(String value) =>
      Discoverability.values.firstWhere(
        (d) => d.wire == value,
        // The narrower setting is the safe fallback: an unrecognised value
        // must not silently make someone more findable than they chose.
        orElse: () => Discoverability.contactsOfContacts,
      );
}

class DiscoveredContact extends Equatable {
  const DiscoveredContact({
    required this.userId,
    required this.fullName,
    this.username,
    this.isNew = false,
  });

  final String userId;
  final String fullName;
  final String? username;

  /// True until the user has seen this match, so "X joined IronLink" is
  /// announced once rather than on every sync.
  final bool isNew;

  factory DiscoveredContact.fromJson(Map<String, dynamic> json) =>
      DiscoveredContact(
        userId: json['user_id'] as String,
        fullName: json['full_name'] as String? ?? '',
        username: json['username'] as String?,
        isNew: json['is_new'] as bool? ?? false,
      );

  @override
  List<Object?> get props => [userId, isNew];
}

class ContactSyncState extends Equatable {
  const ContactSyncState({
    required this.syncEnabled,
    required this.contactCount,
    required this.discoverability,
    this.syncedAt,
  });

  final bool syncEnabled;

  /// How many hashes the server holds. Shown back to the user so "we store N
  /// entries" is checkable rather than asserted.
  final int contactCount;
  final Discoverability discoverability;
  final DateTime? syncedAt;

  factory ContactSyncState.fromJson(Map<String, dynamic> json) =>
      ContactSyncState(
        syncEnabled: json['sync_enabled'] as bool? ?? false,
        contactCount: (json['contact_count'] as num?)?.toInt() ?? 0,
        discoverability:
            Discoverability.fromWire(json['discoverability'] as String? ?? ''),
        syncedAt: json['synced_at'] == null
            ? null
            : DateTime.tryParse(json['synced_at'] as String),
      );

  @override
  List<Object?> get props =>
      [syncEnabled, contactCount, discoverability, syncedAt];
}

class SyncResult extends Equatable {
  const SyncResult({
    required this.stored,
    required this.matched,
    required this.newMatches,
  });

  final int stored;
  final int matched;
  final int newMatches;

  factory SyncResult.fromJson(Map<String, dynamic> json) => SyncResult(
        stored: (json['stored'] as num?)?.toInt() ?? 0,
        matched: (json['matched'] as num?)?.toInt() ?? 0,
        newMatches: (json['new_matches'] as num?)?.toInt() ?? 0,
      );

  @override
  List<Object?> get props => [stored, matched, newMatches];
}

class ContactsRepository {
  ContactsRepository(this._api);

  final ApiClient _api;

  Future<Options> _auth() async {
    final token = await _api.accessToken;
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  /// Uploads digests. The signature takes hashes rather than numbers on
  /// purpose — there is no path through this class that could send a raw
  /// phone number to the server.
  Future<SyncResult> sync(Set<String> hashes, {bool replace = true}) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/contacts/sync',
      data: {'hashes': hashes.toList(), 'replace': replace},
      options: await _auth(),
    );
    return SyncResult.fromJson(res.data ?? const {});
  }

  Future<List<DiscoveredContact>> matches() async {
    final res = await _api.dio.get<List<dynamic>>(
      '/contacts/matches',
      options: await _auth(),
    );
    return [
      for (final j in res.data ?? [])
        DiscoveredContact.fromJson(j as Map<String, dynamic>)
    ];
  }

  /// Clears the "new" flag. Separate from [matches] so that merely loading
  /// the screen in the background does not consume the notification.
  Future<void> markSeen() async {
    await _api.dio.post<void>(
      '/contacts/matches/seen',
      options: await _auth(),
    );
  }

  Future<ContactSyncState> state() async {
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/contacts/state',
      options: await _auth(),
    );
    return ContactSyncState.fromJson(res.data ?? const {});
  }

  Future<void> setDiscoverability(Discoverability level) async {
    await _api.dio.put<void>(
      '/contacts/privacy',
      data: {'discoverability': level.wire},
      options: await _auth(),
    );
  }

  /// Returns the deep link to share.
  ///
  /// This is the one call that carries a raw number, because the invitation
  /// has to reach it. The server hashes and discards it.
  Future<String> invite(String phoneNumber) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/contacts/invite',
      data: {'phone_number': phoneNumber},
      options: await _auth(),
    );
    return (res.data ?? const {})['deep_link'] as String? ?? '';
  }

  /// Erases everything derived from this user's address book, server-side.
  Future<void> deleteAll() async {
    await _api.dio.delete<void>(
      '/contacts/delete-all',
      options: await _auth(),
    );
  }
}
