import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/core/api_client.dart';
import 'package:ironlink/core/crypto/attachment_crypto.dart';
import 'package:ironlink/core/crypto/group_signal.dart';
import 'package:ironlink/core/crypto/signal.dart';
import 'package:ironlink/core/ws_service.dart';
import 'package:ironlink/features/chat/bloc/chat_bloc.dart';
import 'package:ironlink/features/chat/chat_repository.dart';
import 'package:ironlink/features/chat/local/message_store.dart';
import 'package:ironlink/features/groups/bloc/group_chat_bloc.dart';
import 'package:ironlink/features/groups/groups_repository.dart';

/// Behavioural checks for the client_ref fix, at the level of the producers.
///
/// These do not inspect the generator in isolation: each one drives a real
/// bloc and reads the frame that would go on the wire. That is the only place
/// the collision mattered — one reference for two conversations means the
/// server returns the first message instead of storing the second.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('two ChatBloc instances for one sender and one peer cannot collide',
      () async {
    final ws = WsService.forTest();
    final first = _directBloc(ws, peerId: 'bob');
    final second = _directBloc(ws, peerId: 'bob');

    await _sendText(first, 'first');
    await _sendText(second, 'second');

    final refs = _refs(await _frames(ws), type: 'text');
    expect(refs, hasLength(2));
    expect(refs.toSet(), hasLength(2),
        reason: 'both blocs started their old counters at zero');

    await first.close();
    await second.close();
    await ws.dispose();
  });

  test('two direct conversations for one sender cannot collide', () async {
    final ws = WsService.forTest();
    final withBob = _directBloc(ws, peerId: 'bob');
    final withCarol = _directBloc(ws, peerId: 'carol');

    await _sendText(withBob, 'to bob');
    await _sendText(withCarol, 'to carol');

    final refs = _refs(await _frames(ws), type: 'text');
    expect(refs, hasLength(2));
    expect(refs.toSet(), hasLength(2));

    await withBob.close();
    await withCarol.close();
    await ws.dispose();
  });

  test('direct, media, reaction, group, and sender-key refs are all distinct',
      () async {
    final ws = WsService.forTest();
    final direct = _directBloc(ws, peerId: 'bob');
    final group = _groupBloc(
      ws,
      distributions: [
        const PendingDistribution(
          groupId: 'group-1',
          epoch: 1,
          recipientId: 'bob',
          payload: 'pairwise-encrypted-sender-key',
        ),
      ],
    );

    await _sendText(direct, 'direct text');

    final mediaArrived = direct.stream.firstWhere(
        (s) => s.messages.any((m) => m.kind == 'image'));
    direct.add(const MediaSent(
      kind: 'image',
      mediaKey: 'media-key',
      mimeType: 'image/jpeg',
    ));
    await mediaArrived.timeout(const Duration(seconds: 5));

    direct.add(const ReactionToggled('message-1', '👍'));
    await pumpEventQueue();

    await _sendGroupText(group, 'group text');

    final mediaArrivedInGroup = group.stream.firstWhere(
        (s) => s.messages.any((m) => m.kind == 'image'));
    group.add(GroupMediaSent(
      kind: 'image',
      mediaKey: 'group-media-key',
      mimeType: 'image/jpeg',
      attachmentKey: AttachmentKey(
        key: Uint8List(16),
        nonce: Uint8List(12),
        mimeType: 'image/jpeg',
        sizeBytes: 10,
      ),
    ));
    await mediaArrivedInGroup.timeout(const Duration(seconds: 5));

    final frames = await _frames(ws);
    final textRefs = _refs(frames, type: 'text');
    final mediaRefs = _refs(frames, type: 'image');
    final groupTextRefs = _refs(frames, type: 'group_text');
    final groupMediaRefs = _refs(frames, type: 'group_image');
    final skdmRefs = _refs(frames, type: 'skdm');
    final reactionRefs = _refs(frames, type: 'reaction');

    expect(textRefs, hasLength(1));
    expect(mediaRefs, hasLength(1));
    expect(groupTextRefs, hasLength(1));
    expect(groupMediaRefs, hasLength(1));
    expect(skdmRefs, hasLength(1));
    expect(reactionRefs, hasLength(1));

    final all = {
      ...textRefs,
      ...mediaRefs,
      ...groupTextRefs,
      ...groupMediaRefs,
      ...skdmRefs,
      ...reactionRefs,
    };
    expect(all, hasLength(6),
        reason: 'every producer must mint its own idempotency key');

    expect(textRefs.single, startsWith('ref_'));
    expect(mediaRefs.single, startsWith('ref_'));
    expect(groupTextRefs.single, startsWith('ref_'));
    expect(groupMediaRefs.single, startsWith('ref_'));
    expect(skdmRefs.single, startsWith('skdm_'));
    expect(reactionRefs.single, startsWith('rx_'));

    await direct.close();
    await group.close();
    await ws.dispose();
  });
}

ChatBloc _directBloc(WsService ws, {required String peerId}) => ChatBloc(
      repo: _ChatRepo(),
      ws: ws,
      myId: 'me',
      peerId: peerId,
      peerName: peerId,
      // Ref generation is independent of encryption. Turning it off keeps the
      // test about the identifier rather than about Signal key material.
      encrypted: false,
      baseUrl: 'http://test.invalid',
      api: ApiClient(baseUrl: 'http://test.invalid'),
      store: const NullMessageStore(),
      signalService: _Signal(),
    );

GroupChatBloc _groupBloc(
  WsService ws, {
  List<PendingDistribution> distributions = const [],
}) =>
    GroupChatBloc(
      groupId: 'group-1',
      myId: 'me',
      repo: _GroupRepo(),
      ws: ws,
      groupCrypto: _GroupCrypto(distributions),
      pairwise: _Signal(),
    );

Future<void> _sendText(ChatBloc bloc, String text) async {
  final next =
      bloc.stream.firstWhere((s) => s.messages.any((m) => m.content == text));
  bloc.add(TextSent(text));
  await next.timeout(const Duration(seconds: 5));
}

Future<void> _sendGroupText(GroupChatBloc bloc, String text) async {
  final next =
      bloc.stream.firstWhere((s) => s.messages.any((m) => m.content == text));
  bloc.add(GroupTextSent(text));
  await next.timeout(const Duration(seconds: 5));
}

Future<List<Map<String, dynamic>>> _frames(WsService ws) async {
  await ws.debugSettled;
  return [
    for (final raw in await ws.debugOutbox)
      jsonDecode(raw) as Map<String, dynamic>,
  ];
}

List<String> _refs(List<Map<String, dynamic>> frames, {required String type}) =>
    [
      for (final frame in frames)
        if (frame['type'] == type) frame['client_ref'] as String,
    ];

class _ChatRepo extends Fake implements ChatRepository {
  @override
  Future<void> sendTyping(String chatId, bool typing) async {}
}

class _GroupRepo extends Fake implements GroupsRepository {
  @override
  Future<GroupInfo?> group(String groupId) async => const GroupInfo(
        id: 'group-1',
        name: 'Synthetic group',
        isAnnouncement: false,
        memberCount: 2,
      );

  @override
  Future<List<GroupMemberInfo>> members(String groupId) async => const [
        GroupMemberInfo(userId: 'me', fullName: 'Me', role: 'owner'),
        GroupMemberInfo(userId: 'bob', fullName: 'Bob', role: 'member'),
      ];
}

class _GroupCrypto extends Fake implements GroupSignalService {
  _GroupCrypto(this._distributions);

  final List<PendingDistribution> _distributions;

  @override
  Future<List<PendingDistribution>> distributionsFor({
    required String groupId,
    required int epoch,
    required List<String> members,
  }) async =>
      _distributions;

  @override
  Future<String> encrypt({
    required String groupId,
    required int epoch,
    required String plaintext,
  }) async =>
      'group-envelope';
}

class _Signal extends Fake implements SignalService {}
