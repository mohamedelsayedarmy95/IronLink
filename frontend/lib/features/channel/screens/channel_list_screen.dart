import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/env.dart';
import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../bloc/channel_bloc.dart';
import '../widgets/channel_card.dart';

class ChannelListScreen extends StatelessWidget {
  const ChannelListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    return Scaffold(
      backgroundColor: IronColors.navyDeep,
      appBar: AppBar(
        backgroundColor: IronColors.navySurface,
        elevation: 0,
        shape: const Border(bottom: BorderSide(color: IronColors.navyBorder)),
        title: Text(
          t.channelsTitle,
          style: const TextStyle(color: IronColors.gold, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: IronColors.gold),
            tooltip: t.createChannel,
            onPressed: () {
              // TODO: create-channel screen not built yet.
            },
          ),
        ],
      ),
      body: BlocProvider(
        create: (_) => ChannelBloc(
          baseUrl: Env.apiBaseUrl,
          token: '', // TODO: read from secure storage once the auth session is wired here
        )..add(ChannelFetchStarted()),
        child: BlocBuilder<ChannelBloc, ChannelState>(
          builder: (context, state) {
            if (state is ChannelLoading) {
              return const Center(
                  child: CircularProgressIndicator(color: IronColors.gold));
            } else if (state is ChannelFetchFailure) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: IronColors.errorRed),
                      const SizedBox(height: 12),
                      Text(
                        state.error,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: IronColors.textLo),
                      ),
                    ],
                  ),
                ),
              );
            } else if (state is ChannelFetchSuccess) {
              final channels = state.channels;
              if (channels.isEmpty) {
                return ListView(
                  children: [
                    const SizedBox(height: 160),
                    const Icon(Icons.campaign_outlined,
                        size: 64, color: IronColors.goldDim),
                    const SizedBox(height: 16),
                    Center(
                      child: Text(t.noChannelsYet,
                          style: const TextStyle(color: IronColors.textLo)),
                    ),
                  ],
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: channels.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) =>
                    ChannelCard(channel: channels[index]),
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}
