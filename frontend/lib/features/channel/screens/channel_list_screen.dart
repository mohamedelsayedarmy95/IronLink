import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/env.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../l10n/app_localizations.dart';
import '../bloc/channel_bloc.dart';
import '../widgets/channel_card.dart';
import '../../../core/icons.dart';

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
            icon: const Icon(IronIcons.add, color: IronColors.gold),
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
              // state.error holds raw transport text; the user sees a cause
              // they can act on instead.
              return IronErrorState(
                title: t.channelsLoadFailedTitle,
                message: t.failureServer,
                retryLabel: t.retry,
                onRetry: () =>
                    context.read<ChannelBloc>().add(ChannelFetchStarted()),
              );
            } else if (state is ChannelFetchSuccess) {
              final channels = state.channels;
              if (channels.isEmpty) {
                return IronEmptyState(
                  title: t.noChannelsYet,
                  message: t.noChannelsYetHint,
                  rings: 4,
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
