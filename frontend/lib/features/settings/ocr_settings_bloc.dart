import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ironlink/core/api_client.dart';
import 'ocr_settings_state.dart';

part 'ocr_settings_event.dart';

class OcrSettingsBloc extends Bloc<OcrSettingsEvent, OcrSettingsState> {
  final ApiClient _apiClient;
  final FlutterSecureStorage _storage;

  OcrSettingsBloc(this._apiClient, this._storage)
      : super(const OcrSettingsState()) {
    on<LoadKeywords>(_onLoadKeywords);
    on<AddKeyword>(_onAddKeyword);
    on<RemoveKeyword>(_onRemoveKeyword);
  }

  Future<Options> _auth() async {
    final token = await _apiClient.accessToken;
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  Future<void> _onLoadKeywords(
    LoadKeywords event,
    Emitter<OcrSettingsState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/ocr/keywords',
        options: await _auth(),
      );
      final List<dynamic>? keywordsData = response.data?['keywords'];
      final List<String> keywords =
          keywordsData?.map((e) => e as String).toList() ?? [];
      emit(state.copyWith(isLoading: false, keywords: keywords, clearError: true));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        errorKind: OcrErrorKind.load,
        errorDetail: '$e',
      ));
    }
  }

  Future<void> _onAddKeyword(
    AddKeyword event,
    Emitter<OcrSettingsState> emit,
  ) async {
    // Keep the pre-optimistic list so a failed request can revert to it —
    // reverting to state.keywords here would revert to nothing, since the
    // optimistic add already landed there by the time the catch runs.
    final previousKeywords = state.keywords;
    emit(state.copyWith(
      keywords: [...previousKeywords, event.keyword],
      clearError: true,
    ));

    try {
      await _apiClient.dio.post<Map<String, dynamic>>(
        '/ocr/keywords',
        data: {'keywords': [event.keyword]},
        options: await _auth(),
      );
    } catch (e) {
      emit(state.copyWith(
        keywords: previousKeywords,
        errorKind: OcrErrorKind.add,
        errorDetail: '$e',
      ));
    }
  }

  Future<void> _onRemoveKeyword(
    RemoveKeyword event,
    Emitter<OcrSettingsState> emit,
  ) async {
    final previousKeywords = state.keywords;
    emit(state.copyWith(
      keywords: previousKeywords.where((k) => k != event.keyword).toList(),
      clearError: true,
    ));

    try {
      await _apiClient.dio.delete(
        '/ocr/keywords',
        options: await _auth(),
        data: {'keyword': event.keyword},
      );
    } catch (e) {
      emit(state.copyWith(
        keywords: previousKeywords,
        errorKind: OcrErrorKind.remove,
        errorDetail: '$e',
      ));
    }
  }
}