import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/core/api_client.dart';
import 'package:ironlink/core/crypto/signal.dart';
import 'package:ironlink/core/media_service.dart';
import 'package:ironlink/core/ws_service.dart';
import 'package:ironlink/features/chat/ai_consent_repository.dart';
import 'package:ironlink/features/chat/chat_repository.dart';
import 'package:ironlink/features/chat/local/message_store.dart';
import 'package:ironlink/features/chat/screens/chats_list_screen.dart';
import 'package:ironlink/features/keyword_alert/bloc/alert_bloc.dart';
import 'package:ironlink/features/keyword_alert/local/alert_store.dart';
import 'package:ironlink/features/moderation/moderation_repository.dart';
import 'package:ironlink/l10n/app_localizations.dart';

/// The list used to cache its future in `initState` and never reload it.
///
/// Opening a conversation, sending a message in it, and coming back therefore
/// showed the list as it was before the send — and a conversation started from
/// a contact screen could not appear at all without pulling to refresh.
void main() {
  const bob = Conversation(
    peerId: 'bob',
    peerName: 'Bob',
    isOnline: false,
  );
  const carol = Conversation(
    peerId: 'carol',
    peerName: 'Carol',
    isOnline: true,
  );

  testWidgets('returning from a conversation reloads the list once',
      (tester) async {
    final repo = _Repo([bob]);
    final ws = WsService.forTest();

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<MessageStore>.value(
            value: const NullMessageStore(),
          ),
          RepositoryProvider<ApiClient>.value(
            value: ApiClient(baseUrl: 'http://test.invalid'),
          ),
          RepositoryProvider<WsService>.value(value: ws),
          RepositoryProvider<SignalService>.value(value: _Signal()),
          RepositoryProvider<MediaService>.value(value: _Media()),
          RepositoryProvider<AiConsentRepository>.value(value: _AiConsent()),
          RepositoryProvider<ModerationRepository>.value(
            value: _Moderation(),
          ),
          BlocProvider<AlertBloc>(
            create: (_) => AlertBloc(InMemoryAlertStore()),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L.localizationsDelegates,
          supportedLocales: L.supportedLocales,
          home: Scaffold(
            body: ChatsListScreen(repo: repo, ws: ws, myId: 'me'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(repo.calls, 1);
    expect(find.text('Bob'), findsOneWidget);

    // Open the conversation. A message is sent and a new conversation starts
    // while the chat screen is on top.
    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();
    repo.chats = const [bob, carol];

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(repo.calls, 2,
        reason: 'one reload on return, not a polling loop');
    expect(find.text('Carol'), findsOneWidget,
        reason: 'a conversation created while away must become visible');
    expect(find.text('Bob'), findsOneWidget);
  });
}

class _Repo extends Fake implements ChatRepository {
  _Repo(this.chats);

  List<Conversation> chats;
  int calls = 0;

  @override
  Future<List<Conversation>> conversations() async {
    calls++;
    return chats;
  }

  @override
  Future<List<ChatMessage>> history(
    String peerId, {
    required String myId,
    int limit = 100,
  }) async =>
      const [];

  @override
  Future<void> sendTyping(String chatId, bool typing) async {}
}

class _AiConsent extends Fake implements AiConsentRepository {
  @override
  Future<AiConsentState> read({String? peerId, String? groupId}) async =>
      AiConsentState.unknown;
}

class _Moderation extends Fake implements ModerationRepository {
  @override
  Future<bool> isBlocked(String userId) async => false;
}

class _Signal extends Fake implements SignalService {}
class _Media extends Fake implements MediaService {}
