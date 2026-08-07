import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/env.dart';
import '../bloc/channel_bloc.dart';
import '../widgets/channel_card.dart';

class ChannelListScreen extends StatelessWidget {
  const ChannelListScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Channels'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Create Channel',
            onPressed: () {
              // Navigate to create channel screen
              // TODO: Implement create channel screen
            },
          ),
        ],
      ),
      body: BlocProvider(
        create: (_) => ChannelBloc(
          baseUrl: Env.apiBaseUrl,
          token: '', // TODO: Get token from auth state
        )..add(ChannelFetchStarted()),
        child: BlocBuilder<ChannelBloc, ChannelState>(
          builder: (context, state) {
            if (state is ChannelLoading) {
              return const Center(child: CircularProgressIndicator());
            } else if (state is ChannelFetchFailure) {
              return Center(
                child: Text(state.error),
              );
            } else if (state is ChannelFetchSuccess) {
              final channels = state.channels;
              if (channels.isEmpty) {
                return Center(
                  child: Text('No channels found'),
                );
              }
              return ListView.builder(
                itemCount: channels.length,
                itemBuilder: (context, index) {
                  final channel = channels[index];
                  return ChannelCard(channel: channel);
                },
              );
            } else {
              // Container has no const constructor — `const Container()` is a
              // compile error. SizedBox.shrink() is the const-friendly empty
              // widget and allocates nothing.
              return const SizedBox.shrink();
            }
          },
        ),
      ),
    );
  }
}