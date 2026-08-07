import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../../core/theme.dart';

class CommunityApiService {
  final String baseUrl;
  final String token; // JWT token

  CommunityApiService({required this.baseUrl, required this.token});

  Future<List<Community>> getCommunities() async {
    final response = await http.get(
      Uri.parse('$baseUrl/communities'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Community.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load communities');
    }
  }

  Future<Community> createCommunity(Map<String, dynamic> communityData) async {
    final response = await http.post(
      Uri.parse('$baseUrl/communities'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(communityData),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      return Community.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to create community');
    }
  }
}

class Community {
  final int id;
  final String name;
  final String? description;
  final String? category;
  final int ownerId;
  final bool isVerified;
  final int memberCount;

  Community({
    required this.id,
    required this.name,
    this.description,
    this.category,
    required this.ownerId,
    required this.isVerified,
    required this.memberCount,
  });

  factory Community.fromJson(Map<String, dynamic> json) {
    return Community(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      category: json['category'],
      ownerId: json['owner_id'],
      isVerified: json['is_verified'],
      memberCount: json['memberCount'],
    );
  }
}

// === BLoC Events ===

abstract class CommunityEvent extends Equatable {
  const CommunityEvent();
  @override
  List<Object> get props => [];
}

class CommunityFetchStarted extends CommunityEvent {}

// CommunityFetchSuccess / CommunityFetchFailure are STATES, declared at the
// bottom of this file — they were previously also declared here as events.
// Dart bound the name to this first declaration, so
// `emit(CommunityFetchSuccess(...))` was passing an event where a state was
// required. They describe the outcome of a fetch, not a command into the bloc.

class CommunityCreated extends CommunityEvent {
  final Community community;
  const CommunityCreated(this.community);
  @override
  List<Object> get props => [community];
}

// === BLoC ===

class CommunityBloc extends Bloc<CommunityEvent, CommunityState> {
  final CommunityApiService _apiService;

  CommunityBloc({required String baseUrl, required String token})
      : _apiService = CommunityApiService(baseUrl: baseUrl, token: token),
        super(CommunityInitial()) {
    on<CommunityFetchStarted>(_onCommunityFetchStarted);
  }

  Future<void> _onCommunityFetchStarted(
      CommunityFetchStarted event, Emitter<CommunityState> emit) async {
    emit(CommunityLoading());
    try {
      final communities = await _apiService.getCommunities();
      emit(CommunityFetchSuccess(communities));
    } catch (e) {
      emit(CommunityFetchFailure(e.toString()));
    }
  }

}

// === States ===

abstract class CommunityState extends Equatable {
  const CommunityState();
  @override
  List<Object> get props => [];
}

class CommunityInitial extends CommunityState {}

class CommunityLoading extends CommunityState {}

class CommunityFetchSuccess extends CommunityState {
  final List<Community> communities;
  const CommunityFetchSuccess(this.communities);
  @override
  List<Object> get props => [communities];
}

class CommunityFetchFailure extends CommunityState {
  final String error;
  const CommunityFetchFailure(this.error);
  @override
  List<Object> get props => [error];
}