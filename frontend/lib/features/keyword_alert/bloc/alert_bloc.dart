import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/keyword_alert.dart';
import '../local/alert_store.dart';

/// The state behind the ticker, the alert centre, and the unread count.
///
/// WHAT REPLACED WHAT
///
/// The previous TickerBloc was a singleton holding up to fifty raw maps in
/// memory, fed by a WebSocket frame. It had no persistence, so every alert
/// vanished on restart; no acknowledgement, so a handled alert and a missed
/// one were indistinguishable; and no identity, so the same alert arriving
/// twice appeared twice.
///
/// This reads from the store instead, which means the answer to "what do I
/// still owe attention to?" survives the app being killed — the one property
/// that makes an alert worth more than a notification.

sealed class AlertEvent extends Equatable {
  const AlertEvent();

  @override
  List<Object?> get props => const [];
}

/// Load from disk. Sent on startup and whenever the app returns to the
/// foreground, since alerts may have expired while it was away.
class AlertsRequested extends AlertEvent {
  const AlertsRequested();
}

/// A pass just finished and produced alerts.
class AlertsRaised extends AlertEvent {
  const AlertsRaised(this.alerts);

  final List<KeywordAlert> alerts;

  @override
  List<Object?> get props => [alerts];
}

/// The ticker actually drew this alert. Distinct from creating it: an alert
/// created while the app was backgrounded was never presented, and telling the
/// user later that it "was shown" would be false.
class AlertPresented extends AlertEvent {
  const AlertPresented(this.alertId);

  final String alertId;

  @override
  List<Object?> get props => [alertId];
}

/// The user opened the document. Still not acknowledgement (§5.3).
class AlertDocumentOpened extends AlertEvent {
  const AlertDocumentOpened(this.alertId);

  final String alertId;

  @override
  List<Object?> get props => [alertId];
}

/// "تم الاطلاع" — the explicit press, and the only thing that clears an alert.
class AlertAcknowledged extends AlertEvent {
  const AlertAcknowledged(this.alertId);

  final String alertId;

  @override
  List<Object?> get props => [alertId];
}

class AlertDismissed extends AlertEvent {
  const AlertDismissed(this.alertId);

  final String alertId;

  @override
  List<Object?> get props => [alertId];
}

/// Swiped away. Visual only (§5.2.1): the alert stays ALERT_PRESENTED and
/// stays in history. Equivalent to "not currently shown", never to handled.
class AlertHidden extends AlertEvent {
  const AlertHidden(this.alertId);

  final String alertId;

  @override
  List<Object?> get props => [alertId];
}

enum AlertHistoryFilter {
  all,
  unacknowledged,
  acknowledged,
  highConfidence;
}

class AlertFilterChanged extends AlertEvent {
  const AlertFilterChanged(this.filter);

  final AlertHistoryFilter filter;

  @override
  List<Object?> get props => [filter];
}

class AlertState extends Equatable {
  const AlertState({
    this.outstanding = const [],
    this.history = const [],
    this.hiddenIds = const {},
    this.filter = AlertHistoryFilter.all,
    this.loading = false,
  });

  /// Alerts the user still owes an answer to, best first.
  final List<KeywordAlert> outstanding;

  /// Everything within the retention window, newest first.
  final List<KeywordAlert> history;

  /// Swiped away this session. Not persisted, because "not currently shown"
  /// is a property of this screen, not of the alert — after a restart the
  /// user has not seen it again, so it comes back.
  final Set<String> hiddenIds;

  final AlertHistoryFilter filter;
  final bool loading;

  /// What the ticker should show, if anything.
  KeywordAlert? get leadAlert {
    for (final alert in outstanding) {
      if (!hiddenIds.contains(alert.id)) return alert;
    }
    return null;
  }

  /// How many alerts are waiting in total, for the consolidated "2 Smart
  /// Alerts" summary (§5.5) rather than stacking a second full-height ticker
  /// over the chat.
  ///
  /// The total rather than "others behind this one": the user is being told
  /// how much is outstanding, and "1 more" alongside a visible alert is a
  /// riddle where "2 Smart Alerts" is a fact.
  int get visibleCount =>
      outstanding.where((a) => !hiddenIds.contains(a.id)).length;

  int get unacknowledgedCount => outstanding.length;

  List<KeywordAlert> get filteredHistory => switch (filter) {
        AlertHistoryFilter.all => history,
        AlertHistoryFilter.unacknowledged =>
          history.where((a) => a.status.isOutstanding).toList(),
        AlertHistoryFilter.acknowledged => history
            .where((a) => a.status == AlertStatus.acknowledged)
            .toList(),
        AlertHistoryFilter.highConfidence =>
          history.where((a) => (a.confidence ?? 0) >= 0.85).toList(),
      };

  AlertState copyWith({
    List<KeywordAlert>? outstanding,
    List<KeywordAlert>? history,
    Set<String>? hiddenIds,
    AlertHistoryFilter? filter,
    bool? loading,
  }) =>
      AlertState(
        outstanding: outstanding ?? this.outstanding,
        history: history ?? this.history,
        hiddenIds: hiddenIds ?? this.hiddenIds,
        filter: filter ?? this.filter,
        loading: loading ?? this.loading,
      );

  @override
  List<Object?> get props => [outstanding, history, hiddenIds, filter, loading];
}

class AlertBloc extends Bloc<AlertEvent, AlertState> {
  AlertBloc(this._store, {DateTime Function()? now})
      : _now = now ?? (() => DateTime.now().toUtc()),
        super(const AlertState()) {
    on<AlertsRequested>(_onRequested);
    on<AlertsRaised>(_onRaised);
    on<AlertPresented>((e, emit) => _transition(e.alertId, AlertStatus.alertPresented, emit));
    on<AlertDocumentOpened>((e, emit) => _transition(e.alertId, AlertStatus.documentOpened, emit));
    on<AlertAcknowledged>((e, emit) => _transition(e.alertId, AlertStatus.acknowledged, emit));
    on<AlertDismissed>((e, emit) => _transition(e.alertId, AlertStatus.dismissed, emit));
    on<AlertHidden>(_onHidden);
    on<AlertFilterChanged>((e, emit) => emit(state.copyWith(filter: e.filter)));
  }

  final AlertStore _store;
  final DateTime Function() _now;

  Future<void> _onRequested(AlertsRequested event, Emitter<AlertState> emit) async {
    emit(state.copyWith(loading: true));
    await _reload(emit);
  }

  Future<void> _onRaised(AlertsRaised event, Emitter<AlertState> emit) async {
    // The pipeline already wrote them; this only re-reads, so a duplicate
    // event cannot produce a duplicate row.
    await _reload(emit);
  }

  void _onHidden(AlertHidden event, Emitter<AlertState> emit) {
    emit(state.copyWith(hiddenIds: {...state.hiddenIds, event.alertId}));
  }

  Future<void> _transition(
    String alertId,
    AlertStatus next,
    Emitter<AlertState> emit,
  ) async {
    try {
      await _store.transition(alertId, next, now: _now());
    } on IllegalAlertTransition {
      // Two surfaces acted on one alert — a ticker tap and a notification, say.
      // The first won; re-reading below shows the user what actually happened
      // rather than an error they cannot act on.
    }
    await _reload(emit);
  }

  Future<void> _reload(Emitter<AlertState> emit) async {
    final at = _now();
    // outstanding() sweeps expiries first, so an alert cannot be shown past
    // its window merely because the app was closed when the sweep was due.
    final outstanding = await _store.outstanding(now: at);
    final history = await _store.history(now: at);
    emit(state.copyWith(
      outstanding: outstanding,
      history: history,
      loading: false,
    ));
  }
}
