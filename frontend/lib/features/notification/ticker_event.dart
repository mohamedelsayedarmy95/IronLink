import 'package:equatable/equatable.dart';

/// Events for the TickerBloc.
abstract class TickerEvent extends Equatable {
  const TickerEvent();

  @override
  List<Object> get props => [];
}

/// Event to add a new OCR alert to the ticker.
class AddOcrAlert extends TickerEvent {
  final Map<String, dynamic> alert;

  const AddOcrAlert(this.alert);

  @override
  List<Object> get props => [alert];

  @override
  String toString() => 'AddOcrAlert { alert: $alert }';
}

/// Event to clear the ticker (e.g., when switching screens).
class ClearTicker extends TickerEvent {
  const ClearTicker();

  @override
  List<Object> get props => [];
}