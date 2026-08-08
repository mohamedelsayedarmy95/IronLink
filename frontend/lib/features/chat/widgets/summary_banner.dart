import 'package:flutter/material.dart';
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
      color: IronColors.navySurface.withOpacity(0.8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.summarize, color: IronColors.gold, size: 20),
              const SizedBox(width: 8),
              Text(
                'AI Summary',
                style: const TextStyle(
                  color: IronColors.gold,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          isLoading
              ? const SizedBox(
                  height: 20,
                  child: CircularProgressIndicator(color: IronColors.gold, strokeWidth: 2),
                )
              : Text(
                  summary,
                  style: const TextStyle(
                    color: IronColors.textHi,
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
                  'Refresh',
                  style: TextStyle(color: IronColors.gold, fontSize: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}