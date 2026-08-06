import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../../../core/theme.dart';

class SummaryBanner extends StatelessWidget {
  final String summary;
  final bool isLoading;
  final VoidCallback onRefresh;

  const SummaryBanner({
    Key? key,
    required this.summary,
    this.isLoading = false,
    required this.onRefresh,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (summary.isEmpty && !isLoading) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: MilColors.navySurface.withOpacity(0.8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.summary, color: MilColors.gold, size: 20),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context)!.aiSummary,
                style: const TextStyle(
                  color: MilColors.gold,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          isLoading
              ? const SizedBox(
                  height: 20,
                  child: CircularProgressIndicator(color: MilColors.gold, strokeWidth: 2),
                )
              : Text(
                  summary,
                  style: const TextStyle(
                    color: MilColors.textHi,
                    fontSize: 14,
                  ),
                ),
          if (!isLoading && summary.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: onRefresh,
                child: Text(
                  AppLocalizations.of(context)!.refresh,
                  style: TextStyle(color: MilColors.gold, fontSize: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}