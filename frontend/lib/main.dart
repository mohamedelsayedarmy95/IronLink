import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/api_client.dart';
import 'core/media_service.dart';
import 'core/push_service.dart';
import 'core/theme.dart';
import 'core/ws_service.dart';
import 'features/auth/auth_repository.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/screens/splash_screen.dart';
import 'features/chat/chat_repository.dart';
import 'features/groups/groups_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MilAcademyApp());
}

class MilAcademyApp extends StatelessWidget {
  const MilAcademyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider(create: (_) => ApiClient()),
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
            create: (ctx) => PushService(ctx.read<ApiClient>())),
      ],
      child: Builder(
        builder: (context) => BlocProvider(
          create: (ctx) => AuthBloc(
            ctx.read<AuthRepository>(),
            deviceFingerprint: _deviceFingerprint(),
          ),
          child: MaterialApp(
            navigatorKey: PushService.navigatorKey,
            title: 'IronLink',
            debugShowCheckedModeBanner: false,
            theme: ironLinkDarkTheme(),
            // RTL-first: Arabic is the primary language
            locale: const Locale('ar'),
            builder: (context, child) => Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            ),
            home: const SplashScreen(),
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
