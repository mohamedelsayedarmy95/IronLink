part of 'ocr_settings_bloc.dart';

abstract class OcrSettingsEvent extends Equatable {
  const OcrSettingsEvent();

  @override
  List<Object> get props => [];
}

class LoadKeywords extends OcrSettingsEvent {
  const LoadKeywords();
}

class AddKeyword extends OcrSettingsEvent {
  final String keyword;

  const AddKeyword(this.keyword);

  @override
  List<Object> get props => [keyword];
}

class RemoveKeyword extends OcrSettingsEvent {
  final String keyword;

  const RemoveKeyword(this.keyword);

  @override
  List<Object> get props => [keyword];
}