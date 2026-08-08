import 'package:equatable/equatable.dart';

/// State for the TickerBloc.
class TickerState extends Equatable {
  final List<Map<String, dynamic>> alerts;
  final bool isLoading;
  final String? error;

  const TickerState({
    this.alerts = const [],
    this.isLoading = false,
    this.error,
  });

  TickerState copyWith({
    List<Map<String, dynamic>>? alerts,
    bool? isLoading,
    String? error,
  }) =>
      TickerState(
        alerts: alerts ?? this.alerts,
        isLoading: isLoading ?? this.isLoading,
        error: error ?? this.error,
      );

  @override
  List<Object?> get props => [alerts, isLoading, error];
}