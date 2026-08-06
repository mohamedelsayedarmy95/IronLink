import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../bloc/channel_bloc.dart';

class ChannelCard extends StatelessWidget {
  final Channel channel;

  const ChannelCard({Key? key, required this.channel}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: ListTile(
        leading: const Icon(Icons.play_circle_outline, color: MilColors.gold),
        title: Text(channel.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (channel.description != null && channel.description!.isNotEmpty)
              Text(channel.description!),
            const SizedBox(height: 4.0),
            Row(
              children: [
                Icon(Icons.people, size: 16, color: MilColors.textLo),
                const SizedBox(width: 4.0),
                Text('${channel.subscriberCount} ${AppLocalizations.of(context)!.subscribers}'),
                const SizedBox(width: 16.0),
                if (channel.isVerified)
                  const Icon(Icons.verified, color: MilColors.gold, size: 16),
              ],
            ),
          ],
        ),
        onTap: () {
          // Navigate to channel screen
          // TODO: Implement channel screen navigation
        },
      ),
    );
  }
}