import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/api_client.dart';
import 'core/media_service.dart';
import 'core/push_service.dart';
import 'core/theme.dart';
import 'core/ws_service.dart';
import 'features/auth/auth_repository.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/screens/splash_screen.dart';
import 'features/chat/ai_consent_repository.dart';
import 'features/chat/chat_repository.dart';
import 'features/chat/local/message_store.dart';
import 'features/keyword_alert/bloc/alert_bloc.dart';
import 'features/keyword_alert/keyword_alert_service.dart';
import 'features/keyword_alert/local/alert_store.dart';
import 'features/security/widgets/message_safety_banner.dart';
import 'features/contacts/contact_sync_service.dart';
import 'features/contacts/contacts_repository.dart';
import 'features/moderation/moderation_repository.dart';
import 'features/groups/entry/entry_repository.dart';
import 'features/groups/groups_repository.dart';
import 'l10n/app_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // Reads android/app/google-services.json natively. Must happen before
    // the auth screen mounts — Firebase Phone Auth needs it on the very
    // first screen, not just for push notifications post-login.
    await Firebase.initializeApp();
  } catch (_) {
    // No Firebase config (local dev without google-services.json): Phone
    // Auth and push both stay unavailable rather than crashing the app.
  }

  // The local message cache. Opened here so the failure is handled once:
  // if the database cannot be opened the app runs with a null store, which
  // costs search and nothing else.
  MessageStore store;
  try {
    store = await MessageStore.open();
  } catch (_) {
    store = const NullMessageStore();
  }

  // Keyword rules and alerts. Opened here for the same reason as the message
  // cache — one place to handle the failure — but it degrades differently.
  // The message cache is disposable; a rule the user wrote cannot be rebuilt
  // from anywhere, since the server has never seen it. So a database that
  // will not open falls back to an in-memory store, where the feature works
  // for the session rather than silently discarding what the user types.
  AlertStore alerts;
  try {
    alerts = await AlertStore.open();
  } catch (_) {
    alerts = InMemoryAlertStore();
  }

  // The alert bloc and the keyword service are built here rather than in the
  // widget tree because resolving which OCR engines this device has is async,
  // and because both are app-wide: an alert raised in one conversation is
  // still outstanding while the user reads another.
  final alertBloc = AlertBloc(alerts)..add(const AlertsRequested());

  // Nullable on purpose. If the native engines cannot be resolved — a platform
  // channel that failed to attach, a model that did not unpack — the app runs
  // without document scanning rather than failing to start. Every screen that
  // reads it treats null as "not available on this build".
  KeywordAlertService? keywordAlerts;
  try {
    keywordAlerts =
        await KeywordAlertService.create(store: alerts, bloc: alertBloc);
  } catch (e) {
    debugPrint('[keyword-alert] unavailable: $e');
  }

  runApp(MilAcademyApp(
    store: store,
    alerts: alerts,
    alertBloc: alertBloc,
    keywordAlerts: keywordAlerts,
  ));
}

class MilAcademyApp extends StatelessWidget {
  const MilAcademyApp({
    super.key,
    required this.store,
    required this.alerts,
    required this.alertBloc,
    this.keywordAlerts,
  });

  final MessageStore store;
  final AlertStore alerts;
  final AlertBloc alertBloc;

  /// Null where document scanning could not be started. See main().
  final KeywordAlertService? keywordAlerts;

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider(create: (_) => ApiClient()),
        RepositoryProvider<MessageStore>.value(value: store),
        RepositoryProvider(
            create: (ctx) => AuthRepository(ctx.read<ApiClient>())),
        RepositoryProvider(
            create: (ctx) => ChatRepository(ctx.read<ApiClient>())),
        RepositoryProvider(
            create: (ctx) => WsService(ctx.read<ApiClient>())),
        RepositoryProvider(
            create: (ctx) => MediaService(ctx.read<ApiClient>())),
        RepositoryProvider(
            create: (ctx) => GroupsRepository(ctx.read<ApiClient>())),
        RepositoryProvider(
            create: (ctx) => GroupEntryRepository(ctx.read<ApiClient>())),
        RepositoryProvider(
            create: (ctx) => ContactsRepository(ctx.read<ApiClient>())),
        RepositoryProvider(
            create: (ctx) =>
                ContactSyncService(ctx.read<ContactsRepository>())),
        RepositoryProvider(
            create: (ctx) => ModerationRepository(ctx.read<ApiClient>())),
        RepositoryProvider(
            create: (ctx) => AiConsentRepository(ctx.read<ApiClient>())),
        RepositoryProvider(
            create: (ctx) => PushService(ctx.read<ApiClient>())),
        RepositoryProvider<AlertStore>.value(value: alerts),
        // One instance, app-wide, because its value is the cache: assessing
        // the same message again on every scroll frame is the cost this
        // exists to avoid.
        RepositoryProvider(create: (_) => MessageSafety()),
        RepositoryProvider<KeywordAlertService?>.value(value: keywordAlerts),
      ],
      child: Builder(
        builder: (context) => MultiBlocProvider(
          providers: [
            BlocProvider<AlertBloc>.value(value: alertBloc),
          ],
          child: Builder(
            builder: (ctx) => BlocProvider(
                create: (ctx) => AuthBloc(
                  ctx.read<AuthRepository>(),
                  deviceFingerprint: _deviceFingerprint(),
                ),
                child: MaterialApp(
                  navigatorKey: PushService.navigatorKey,
                  title: 'IronLink',
                  debugShowCheckedModeBanner: false,
                  theme: ironLinkDarkTheme(),
                  localizationsDelegates: const [
                    L.delegate,
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  supportedLocales: L.supportedLocales,
                  // No explicit `locale:` — Flutter resolves the device's
                  // locale against supportedLocales itself (Arabic or
                  // English), and falls back to the first supported locale
                  // (Arabic) otherwise. Text direction follows from that.
                  home: const SplashScreen(),
                ),
              ),
            ),
          ),
        ),
    );
  }

  /// Stable device characteristics; matched server-side for anomalous-login
  /// detection. Sprint 3 will replace this with device_info_plus values.
  static String _deviceFingerprint() {
    final raw =
        '${Platform.operatingSystem}|${Platform.operatingSystemVersion}|${Platform.localHostname}';
    return raw.hashCode.toRadixString(16).padLeft(16, '0') +
        raw.length.toRadixString(16).padLeft(16, '0');
  }
}
