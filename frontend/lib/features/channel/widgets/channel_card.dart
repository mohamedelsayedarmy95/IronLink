import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../bloc/channel_bloc.dart';

class ChannelCard extends StatelessWidget {
  final Channel channel;
  final VoidCallback? onTap;

  const ChannelCard({super.key, required this.channel, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: IronColors.navySurface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: IronColors.navyBorder),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: IronColors.navyDeep,
                child: const Icon(Icons.play_circle_outline,
                    color: IronColors.gold),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            channel.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: IronColors.textHi,
                            ),
                          ),
                        ),
                        if (channel.isVerified) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.verified,
                              size: 15, color: IronColors.gold),
                        ],
                      ],
                    ),
                    if (channel.description != null &&
                        channel.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        channel.description!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: IronColors.textLo, fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.people_outline,
                            size: 14, color: IronColors.textLo),
                        const SizedBox(width: 4),
                        Text(
                          L.of(context).subscriberCount(channel.subscriberCount),
                          style: const TextStyle(
                              color: IronColors.textLo, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left, color: IronColors.textLo),
            ],
          ),
        ),
      ),
    );
  }
}
