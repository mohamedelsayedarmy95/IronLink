import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../bloc/community_bloc.dart';

class CommunityCard extends StatelessWidget {
  final Community community;

  const CommunityCard({Key? key, required this.community}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: ListTile(
        leading: const Icon(Icons.group, color: IronColors.gold),
        title: Text(community.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (community.description != null && community.description!.isNotEmpty)
              Text(community.description!),
            const SizedBox(height: 4.0),
            Row(
              children: [
                Icon(Icons.people, size: 16, color: IronColors.textLo),
                const SizedBox(width: 4.0),
                Text('\${community.memberCount} members'),
                const SizedBox(width: 16.0),
                if (community.isVerified)
                  const Icon(Icons.verified, color: IronColors.gold, size: 16),
              ],
            ),
          ],
        ),
        onTap: () {
          // Navigate to community screen
          // TODO: Implement community screen navigation
        },
      ),
    );
  }
}