import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/env.dart';
import '../bloc/community_bloc.dart';
import '../widgets/community_card.dart';
import '../../../core/icons.dart';

class CommunityListScreen extends StatelessWidget {
  const CommunityListScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Communities'),
        actions: [
          IconButton(
            icon: const Icon(IronIcons.add),
            tooltip: 'Create Community',
            onPressed: () {
              // Navigate to create community screen
              // TODO: Implement create community screen
            },
          ),
        ],
      ),
      body: BlocProvider(
        create: (_) => CommunityBloc(
          baseUrl: Env.apiBaseUrl,
          token: '', // TODO: Get token from auth state
        )..add(CommunityFetchStarted()),
        child: BlocBuilder<CommunityBloc, CommunityState>(
          builder: (context, state) {
            if (state is CommunityLoading) {
              return const Center(child: CircularProgressIndicator());
            } else if (state is CommunityFetchFailure) {
              return Center(
                child: Text(state.error),
              );
            } else if (state is CommunityFetchSuccess) {
              final communities = state.communities;
              if (communities.isEmpty) {
                return Center(
                  child: Text('No communities found'),
                );
              }
              return ListView.builder(
                itemCount: communities.length,
                itemBuilder: (context, index) {
                  final community = communities[index];
                  return CommunityCard(community: community);
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