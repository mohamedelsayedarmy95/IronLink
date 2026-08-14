import 'package:equatable/equatable.dart';

import '../../core/failure.dart';

/// Which action failed — the bloc is UI-agnostic and has no BuildContext to
/// localize a message with, so it reports what happened and why, and the page
/// composes the localized sentence.
enum OcrErrorKind { load, add, remove }

class OcrSettingsState extends Equatable {
  final bool isLoading;
  final List<String> keywords;
  final OcrErrorKind? errorKind;

  /// Cause behind [errorKind], as a classified failure rather than raw
  /// exception text — nothing here can leak a stack trace or host address
  /// into the interface.
  final NetworkFailure? failure;

  const OcrSettingsState({
    this.isLoading = false,
    this.keywords = const [],
    this.errorKind,
    this.failure,
  });

  OcrSettingsState copyWith({
    bool? isLoading,
    List<String>? keywords,
    OcrErrorKind? errorKind,
    NetworkFailure? failure,
    bool clearError = false,
  }) {
    return OcrSettingsState(
      isLoading: isLoading ?? this.isLoading,
      keywords: keywords ?? this.keywords,
      errorKind: clearError ? null : (errorKind ?? this.errorKind),
      failure: clearError ? null : (failure ?? this.failure),
    );
  }

  @override
  List<Object?> get props => [isLoading, keywords, errorKind, failure];
}
