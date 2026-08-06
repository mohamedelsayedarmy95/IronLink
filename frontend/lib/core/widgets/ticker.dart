import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../features/notification/ticker_bloc.dart';
import '../../features/notification/ticker_event.dart';
import '../../features/notification/ticker_state.dart';
import '../theme.dart';

/// A premium news ticker with glassmorphism background that displays OCR alerts.
/// It shows a horizontally scrolling marquee of alerts.
class NewsTicker extends StatefulWidget {
  const NewsTicker({Key? key}) : super(key: key);

  @override
  State<NewsTicker> createState() => _NewsTickerState();
}

class _NewsTickerState extends State<NewsTicker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final ScrollController _scrollController;
  late final StreamSubscription<TickerState> _subscription;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20), // Adjust speed as needed
    )..repeat(reverse: true);
    _scrollController = ScrollController();

    // Listen to the animation controller to update the scroll position
    _animationController.addListener(() {
      if (_scrollController.hasClients) {
        final maxScrollExtent = _scrollController.position.maxScrollExtent;
        if (maxScrollExtent > 0) {
          _scrollController.jumpTo(maxScrollExtent * _animationController.value);
        }
      }
    });

    // Subscribe to the TickerBloc to get alerts
    _subscription = TickerBloc().stream.listen((state) {
      if (mounted) {
        setState(() {}); // Rebuild when the alert list changes
      }
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    _animationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TickerBloc, TickerState>(
      bloc: TickerBloc(),
      builder: (context, state) {
        final alerts = state.alerts;
        if (alerts.isEmpty) {
          return const SizedBox.shrink(); // Hide ticker if no alerts
        }
        return GlassCard.dark(
          child: Padding(
            padding: IronSpacing.symmetric(horizontal: IronSpacing.lg),
            child: SizedBox(
              height: 40.0, // Fixed height for the ticker
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                controller: _scrollController,
                itemCount: alerts.length * 2, // Duplicate to create seamless loop
                itemBuilder: (context, index) {
                  final alert = alerts[index % alerts.length];
                  final keyword = alert['matched_keyword'] ?? '';
                  final fileName = alert['file_name'] ?? 'unknown file';
                  final text =
                      '��🔔 $keyword found in $fileName   '; // Extra spacing for gap
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Text(
                      text,
                      style: IronTypography.bodyLarge(context: context)
                          .copyWith(color: IronColors.textPrimary(context)),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}