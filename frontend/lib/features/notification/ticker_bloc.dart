import 'package:flutter_bloc/flutter_bloc.dart';
import 'ticker_event.dart';
import 'ticker_state.dart';

/// Bloc that manages the queue of OCR alerts for the news ticker.
/// Implemented as a singleton so it can be accessed from anywhere without BlocProvider.
class TickerBloc extends Bloc<TickerEvent, TickerState> {
  TickerBloc._internal() : super(const TickerState()) {
    on<AddOcrAlert>((event, emit) {
      // Add the alert to the queue, keeping only the last 50 alerts.
      final List<Map<String, dynamic>> newAlerts = List.from(state.alerts)
        ..add(event.alert);
      // Keep only the last 50 alerts to prevent the list from growing indefinitely.
      if (newAlerts.length > 50) {
        newAlerts.removeRange(0, newAlerts.length - 50);
      }
      emit(state.copyWith(alerts: newAlerts));
    });

    on<ClearTicker>((event, emit) {
      emit(state.copyWith(alerts: []));
    });
  }

  // Singleton instance
  static final TickerBloc _instance = TickerBloc._internal();

  factory TickerBloc() => _instance;
}