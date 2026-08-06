import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../bloc/community_bloc.dart';
import '../widgets/community_card.dart';

class CommunityListScreen extends StatelessWidget {
  const CommunityListScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.communities),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: AppLocalizations.of(context)!.createCommunity,
            onPressed: () {
              // Navigate to create community screen
              // TODO: Implement create community screen
            },
          ),
        ],
      ),
      body: BlocProvider(
        create: (_) => CommunityBloc(
          baseUrl: 'http://localhost:8000', // TODO: Get from config
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
                  child: Text(AppLocalizations.of(context)!.noCommunitiesFound),
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
              return const Container();
            }
          },
        ),
      ),
    );
  }
}