import 'package:equatable/equatable.dart';

class OcrSettingsState extends Equatable {
  final bool isLoading;
  final List<String> keywords;
  final String? errorMessage;

  const OcrSettingsState({
    this.isLoading = false,
    this.keywords = const [],
    this.errorMessage,
  });

  OcrSettingsState copyWith({
    bool? isLoading,
    List<String>? keywords,
    String? errorMessage,
  }) {
    return OcrSettingsState(
      isLoading: isLoading ?? this.isLoading,
      keywords: keywords ?? this.keywords,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [isLoading, keywords, errorMessage];
}