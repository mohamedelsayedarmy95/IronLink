import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../../core/api_client.dart';

// We'll create a simple API service for channels
class ChannelApiService {
  final String baseUrl;
  final ApiClient api;

  ChannelApiService({required this.baseUrl, required this.api});

  /// Read per request from secure storage. Passing a token in at
  /// construction meant the screen sent an empty bearer and every channel
  /// call came back 401.
  Future<Map<String, String>> _headers() async => {
        'Authorization': 'Bearer ${await api.accessToken ?? ''}',
        'Content-Type': 'application/json',
      };

  Future<List<Channel>> getChannels() async {
    final response = await http.get(
      Uri.parse('$baseUrl/channels'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Channel.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load channels');
    }
  }

  Future<Channel> createChannel(Map<String, dynamic> channelData) async {
    final response = await http.post(
      Uri.parse('$baseUrl/channels'),
      headers: await _headers(),
      body: jsonEncode(channelData),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      return Channel.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to create channel');
    }
  }
}

class Channel {
  final int id;
  final String name;
  final String? description;
  final String type; // public or private
  final String? category;
  final int ownerId;
  final bool isVerified;
  final int subscriberCount;

  Channel({
    required this.id,
    required this.name,
    this.description,
    required this.type,
    this.category,
    required this.ownerId,
    required this.isVerified,
    required this.subscriberCount,
  });

  factory Channel.fromJson(Map<String, dynamic> json) {
    return Channel(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      type: json['type'],
      category: json['category'],
      ownerId: json['owner_id'],
      isVerified: json['is_verified'],
      subscriberCount: json['subscriber_count'],
    );
  }
}

// === Events ===

abstract class ChannelEvent extends Equatable {
  const ChannelEvent();
  @override
  List<Object> get props => [];
}

class ChannelFetchStarted extends ChannelEvent {}

// ChannelFetchSuccess / ChannelFetchFailure are STATES, declared at the bottom
// of this file — they were previously also declared here as events. Dart bound
// the name to this first declaration, so `emit(ChannelFetchSuccess(...))` was
// passing an event where a state was required. They describe the outcome of a
// fetch, not a command into the bloc, so the event copies are removed.

class ChannelCreated extends ChannelEvent {
  final Channel channel;
  const ChannelCreated(this.channel);
  @override
  List<Object> get props => [channel];
}

// === BLoC ===

class ChannelBloc extends Bloc<ChannelEvent, ChannelState> {
  final ChannelApiService _apiService;

  ChannelBloc({required String baseUrl, required ApiClient api})
      : _apiService = ChannelApiService(baseUrl: baseUrl, api: api),
        super(ChannelInitial()) {
    on<ChannelFetchStarted>(_onChannelFetchStarted);
  }

  Future<void> _onChannelFetchStarted(
      ChannelFetchStarted event, Emitter<ChannelState> emit) async {
    emit(ChannelLoading());
    try {
      final channels = await _apiService.getChannels();
      emit(ChannelFetchSuccess(channels));
    } catch (e) {
      emit(ChannelFetchFailure(e.toString()));
    }
  }

}

// === States ===

abstract class ChannelState extends Equatable {
  const ChannelState();
  @override
  List<Object> get props => [];
}

class ChannelInitial extends ChannelState {}

class ChannelLoading extends ChannelState {}

class ChannelFetchSuccess extends ChannelState {
  final List<Channel> channels;
  const ChannelFetchSuccess(this.channels);
  @override
  List<Object> get props => [channels];
}

class ChannelFetchFailure extends ChannelState {
  final String error;
  const ChannelFetchFailure(this.error);
  @override
  List<Object> get props => [error];
}