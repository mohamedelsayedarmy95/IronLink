import 'package:equatable/equatable.dart';

/// Which action failed — the bloc is UI-agnostic and has no BuildContext to
/// localize a message with, so it reports what happened and the page (which
/// does have a BuildContext) composes the localized sentence around [error].
enum OcrErrorKind { load, add, remove }

class OcrSettingsState extends Equatable {
  final bool isLoading;
  final List<String> keywords;
  final OcrErrorKind? errorKind;
  final String? errorDetail;

  const OcrSettingsState({
    this.isLoading = false,
    this.keywords = const [],
    this.errorKind,
    this.errorDetail,
  });

  OcrSettingsState copyWith({
    bool? isLoading,
    List<String>? keywords,
    OcrErrorKind? errorKind,
    String? errorDetail,
    bool clearError = false,
  }) {
    return OcrSettingsState(
      isLoading: isLoading ?? this.isLoading,
      keywords: keywords ?? this.keywords,
      errorKind: clearError ? null : (errorKind ?? this.errorKind),
      errorDetail: clearError ? null : (errorDetail ?? this.errorDetail),
    );
  }

  @override
  List<Object?> get props => [isLoading, keywords, errorKind, errorDetail];
}