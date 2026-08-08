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
    emit(state.copyWith(isLoading: true, errorMessage: null));
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/ocr/keywords',
        options: await _auth(),
      );
      final List<dynamic>? keywordsData = response.data?['keywords'];
      final List<String> keywords =
          keywordsData?.map((e) => e as String).toList() ?? [];
      emit(state.copyWith(isLoading: false, keywords: keywords));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load keywords: $e',
      ));
    }
  }

  Future<void> _onAddKeyword(
    AddKeyword event,
    Emitter<OcrSettingsState> emit,
  ) async {
    // Optimistically update the UI
    final newKeywords = List<String>.from(state.keywords)..add(event.keyword);
    emit(state.copyWith(keywords: newKeywords));

    try {
      await _apiClient.dio.post<Map<String, dynamic>>(
        '/ocr/keywords',
        data: {'keywords': [event.keyword]},
        options: await _auth(),
      );
      // If the server returns an error, we'll revert in the catch block
    } catch (e) {
      // Revert the optimistic update
      emit(state.copyWith(keywords: List<String>.from(state.keywords)));
      emit(state.copyWith(
        errorMessage: 'Failed to add keyword: $e',
      ));
    }
  }

  Future<void> _onRemoveKeyword(
    RemoveKeyword event,
    Emitter<OcrSettingsState> emit,
  ) async {
    // Optimistically update the UI
    final newKeywords =
        List<String>.from(state.keywords)..remove(event.keyword);
    emit(state.copyWith(keywords: newKeywords));

    try {
      await _apiClient.dio.delete(
        '/ocr/keywords',
        options: await _auth(),
        data: {'keyword': event.keyword},
      );
    } catch (e) {
      // Revert the optimistic update
      emit(state.copyWith(keywords: List<String>.from(state.keywords)));
      emit(state.copyWith(
        errorMessage: 'Failed to remove keyword: $e',
      ));
    }
  }
}