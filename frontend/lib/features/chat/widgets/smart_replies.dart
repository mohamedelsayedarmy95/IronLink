import 'package:flutter/material.dart';
import '../../../core/theme.dart';

class SmartReplies extends StatelessWidget {
  final List<String> suggestions;
  final ValueChanged<String> onTap;

  const SmartReplies({
    Key? key,
    required this.suggestions,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: IronColors.navySurface.withOpacity(0.7),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: suggestions.map((suggestion) {
          return ActionChip(
            label: Text(
              suggestion,
              style: const TextStyle(color: IronColors.textHi),
            ),
            backgroundColor: IronColors.navyDeep,
            onPressed: () => onTap(suggestion),
          );
        }).toList(),
      ),
    );
  }
}