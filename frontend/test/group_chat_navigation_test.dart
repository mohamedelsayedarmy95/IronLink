import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/core/crypto/group_signal.dart';
import 'package:ironlink/core/crypto/signal.dart';
import 'package:ironlink/core/media_service.dart';
import 'package:ironlink/core/ws_service.dart';
import 'package:ironlink/features/groups/groups_repository.dart';
import 'package:ironlink/features/groups/groups_screen.dart';
import 'package:ironlink/l10n/app_localizations.dart';

const _group = GroupInfo(
  id: 'synthetic-group',
  name: 'Navigation test group',
  isAnnouncement: false,
  memberCount: 1,
  myRole: 'owner',
);

class _Groups extends Fake implements GroupsRepository {
  @override
  Future<List<GroupInfo>> myGroups() async => [_group];

  @override
  Future<GroupInfo?> group(String groupId) async => _group;

  @override
  Future<List<GroupMemberInfo>> members(String groupId) async => [];

  @override
  Future<List<GroupChatMessage>> history(String groupId,
          {required String myId, int limit = 50}) async =>
      [];
}

class _Ws extends Fake implements WsService {
  @override
  Stream<Map<String, dynamic>> get frames => const Stream.empty();
}

class _Pairwise extends Fake implements SignalService {}
class _Media extends Fake implements MediaService {}

class _GroupCrypto extends Fake implements GroupSignalService {
  @override
  Future<void> pruneOldEpochs(String groupId, int currentEpoch) async {}
}

void main() {
  testWidgets('group route receives the account-scoped encryption services',
      (tester) async {
    final groups = _Groups();
    await tester.pumpWidget(MultiRepositoryProvider(
      providers: [
        RepositoryProvider<GroupsRepository>.value(value: groups),
        RepositoryProvider<WsService>.value(value: _Ws()),
        RepositoryProvider<MediaService>.value(value: _Media()),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L.localizationsDelegates,
        supportedLocales: L.supportedLocales,
        home: MultiRepositoryProvider(
          providers: [
            RepositoryProvider<SignalService>.value(value: _Pairwise()),
            RepositoryProvider<GroupSignalService>.value(value: _GroupCrypto()),
          ],
          child: Scaffold(body: GroupsScreen(repo: groups, myId: 'owner')),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_group.name));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsOneWidget);
  });
}
