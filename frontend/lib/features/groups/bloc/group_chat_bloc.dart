import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart'
    show DuplicateMessageException;

import '../../../core/crypto/group_signal.dart';
import '../../../core/crypto/signal.dart';
import '../../../core/ws_service.dart';
import '../groups_repository.dart';

// ── Events ────────────────────────────────────────────────────────────────────

sealed class GroupChatEvent extends Equatable {
  const GroupChatEvent();
  @override
  List<Object?> get props => [];
}

class GroupChatOpened extends GroupChatEvent {
  const GroupChatOpened();
}

class GroupTextSent extends GroupChatEvent {
  const GroupTextSent(this.content);
  final String content;
  @override
  List<Object?> get props => [content];
}

class GroupFrameReceived extends GroupChatEvent {
  const GroupFrameReceived(this.frame);
  final Map<String, dynamic> frame;
  @override
  List<Object?> get props => [frame];
}

// ── State ─────────────────────────────────────────────────────────────────────

/// Why a group message could not be sent or read.
enum GroupChatError {
  /// A member's identity key changed; distributing the group key to whoever
  /// now holds it is a decision for the user, not a default.
  identityChanged,

  /// Encryption refused. The message was not sent.
  encryptFailed,

  /// One or more messages could not be decrypted — usually because they
  /// predate this device's membership.
  decryptFailed,

  /// No longer a member.
  notAMember,
}

class GroupChatState extends Equatable {
  const GroupChatState({
    this.messages = const [],
    this.members = const [],
    this.loading = true,
    this.sending = false,
    this.epoch = 1,
    this.canPost = true,
    this.error,
  });

  final List<GroupChatMessage> messages;
  final List<GroupMemberInfo> members;
  final bool loading;
  final bool sending;
  final int epoch;
  final bool canPost;
  final GroupChatError? error;

  GroupChatState copyWith({
    List<GroupChatMessage>? messages,
    List<GroupMemberInfo>? members,
    bool? loading,
    bool? sending,
    int? epoch,
    bool? canPost,
    GroupChatError? error,
  }) =>
      GroupChatState(
        messages: messages ?? this.messages,
        members: members ?? this.members,
        loading: loading ?? this.loading,
        sending: sending ?? this.sending,
        epoch: epoch ?? this.epoch,
        canPost: canPost ?? this.canPost,
        // Not carried forward: it describes the last attempt, not a lasting
        // condition.
        error: error,
      );

  @override
  List<Object?> get props =>
      [messages.length, _rev, members.length, loading, sending, epoch,
       canPost, error];

  int get _rev => messages.fold(
      0, (acc, m) => acc + (m.pending ? 1 : 0) + (m.encrypted ? 2 : 0));
}

// ── Bloc ──────────────────────────────────────────────────────────────────────

class GroupChatBloc extends Bloc<GroupChatEvent, GroupChatState> {
  GroupChatBloc({
    required this.groupId,
    required this.myId,
    required GroupsRepository repo,
    required WsService ws,
    required GroupSignalService groupCrypto,
    required SignalService pairwise,
  })  : _repo = repo,
        _ws = ws,
        _crypto = groupCrypto,
        _pairwise = pairwise,
        super(const GroupChatState()) {
    on<GroupChatOpened>(_onOpened);
    on<GroupTextSent>(_onTextSent);
    on<GroupFrameReceived>(_onFrame);

    _sub = _ws.frames.listen((f) => add(GroupFrameReceived(f)));
  }

  final String groupId;
  final String myId;
  final GroupsRepository _repo;
  final WsService _ws;
  final GroupSignalService _crypto;
  final SignalService _pairwise;

  StreamSubscription? _sub;
  int _refCounter = 0;

  /// The epoch this device has already distributed a sender key for. Kept so
  /// the (network-heavy) distribution does not repeat on every send.
  int? _distributedEpoch;

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }

  String? _nameOf(String userId) {
    for (final m in state.members) {
      if (m.userId == userId) return m.fullName;
    }
    return null;
  }

  Future<void> _onOpened(
      GroupChatOpened e, Emitter<GroupChatState> emit) async {
    try {
      final group = await _repo.group(groupId);
      if (group == null) {
        emit(state.copyWith(loading: false, error: GroupChatError.notAMember));
        return;
      }
      final members = await _repo.members(groupId);
      final history = await _repo.history(groupId, myId: myId);

      for (final m in history) {
        m.senderName = null; // filled below once members are in state
        if (m.isMine || m.deleted) continue;
        if (!GroupSignalService.isEnvelope(m.content)) continue;
        try {
          m.content = await _crypto.decrypt(
            groupId: groupId,
            senderId: m.senderId,
            envelope: m.content!,
          );
          m.encrypted = true;
        } catch (_) {
          // Expected for anything sent before this device held the sender's
          // key. Shown as unreadable rather than as ciphertext.
          m.content = null;
        }
      }

      final ordered = history.reversed.toList();
      for (final m in ordered) {
        m.senderName = m.isMine ? null : _nameOfIn(members, m.senderId);
      }

      emit(state.copyWith(
        messages: ordered,
        members: members,
        epoch: group.membersEpoch,
        canPost: group.canPost,
        loading: false,
      ));

      // Old epochs decrypt only messages already received, so pruning them
      // costs nothing and bounds what the device keeps.
      unawaited(_crypto
          .pruneOldEpochs(groupId, group.membersEpoch)
          .catchError((Object e) => debugPrint('[group] prune failed: $e')));
    } catch (err) {
      debugPrint('[group] open failed: $err');
      emit(state.copyWith(loading: false));
    }
  }

  static String? _nameOfIn(List<GroupMemberInfo> members, String userId) {
    for (final m in members) {
      if (m.userId == userId) return m.fullName;
    }
    return null;
  }

  /// Makes sure every current member holds this device's sender key for the
  /// current epoch, sending the ones that are missing.
  ///
  /// Re-checks the epoch against the server first. Membership can change
  /// while this screen is open, and sending under a stale epoch would encrypt
  /// with a key the person who just left still holds.
  Future<int> _ensureDistributed() async {
    final group = await _repo.group(groupId);
    if (group == null) throw const _NoLongerAMember();

    final epoch = group.membersEpoch;
    if (_distributedEpoch == epoch) return epoch;

    final members = await _repo.members(groupId);
    final pending = await _crypto.distributionsFor(
      groupId: groupId,
      epoch: epoch,
      members: [for (final m in members) m.userId],
    );

    for (final d in pending) {
      _ws.sendSenderKey(
        group: groupId,
        to: d.recipientId,
        content: d.payload,
        clientRef: 'skdm_${++_refCounter}',
      );
    }

    _distributedEpoch = epoch;
    return epoch;
  }

  Future<void> _onTextSent(
      GroupTextSent e, Emitter<GroupChatState> emit) async {
    if (e.content.trim().isEmpty) return;
    emit(state.copyWith(sending: true));

    final int epoch;
    final String envelope;
    try {
      epoch = await _ensureDistributed();
      envelope = await _crypto.encrypt(
        groupId: groupId,
        epoch: epoch,
        plaintext: e.content,
      );
    } on _NoLongerAMember {
      emit(state.copyWith(sending: false, error: GroupChatError.notAMember));
      return;
    } on IdentityChanged {
      // Never distribute past this: handing the group key to whoever now
      // holds a changed identity is the thing that must not happen quietly.
      emit(state.copyWith(
          sending: false, error: GroupChatError.identityChanged));
      return;
    } catch (err) {
      debugPrint('[group] encrypt failed: $err');
      emit(state.copyWith(
          sending: false, error: GroupChatError.encryptFailed));
      return;
    }

    final ref = 'ref_${++_refCounter}';
    _ws.sendGroupText(group: groupId, content: envelope, clientRef: ref);

    // The bubble shows the plaintext, not the envelope.
    emit(state.copyWith(
      sending: false,
      epoch: epoch,
      messages: [
        ...state.messages,
        GroupChatMessage(
          id: ref,
          senderId: myId,
          content: e.content,
          createdAt: DateTime.now(),
          isMine: true,
          pending: true,
          encrypted: true,
        ),
      ],
    ));
  }

  Future<void> _onFrame(
      GroupFrameReceived e, Emitter<GroupChatState> emit) async {
    final f = e.frame;

    switch (f['type']) {
      case 'ack':
        final ref = f['client_ref'] as String?;
        if (ref == null || !ref.startsWith('ref_')) return;
        emit(state.copyWith(messages: [
          for (final m in state.messages)
            if (m.id == ref)
              GroupChatMessage(
                id: f['message_id'] as String,
                senderId: myId,
                content: m.content,
                createdAt: DateTime.parse(f['created_at'] as String).toLocal(),
                isMine: true,
                kind: m.kind,
                encrypted: m.encrypted,
              )
            else
              m
        ]));

      case 'skdm':
        // Another member's sender key, arriving pairwise encrypted.
        if (f['group'] != groupId) return;
        final from = f['from'] as String?;
        final content = f['content'] as String?;
        if (from == null || content == null) return;
        try {
          final payload = await _pairwise.decrypt(content, from);
          await _crypto.acceptDistribution(
            senderId: from,
            decryptedPayload: payload,
          );
        } on DuplicateMessageException {
          // Already processed; re-distribution is normal after a rotation.
        } catch (err) {
          debugPrint('[group] sender key rejected from $from: $err');
        }

      case 'group_message':
        if (f['group'] != groupId) return;
        final from = f['from'] as String?;
        if (from == null) return;

        String? content = f['content'] as String?;
        var encrypted = false;

        if (GroupSignalService.isEnvelope(content)) {
          try {
            content = await _crypto.decrypt(
              groupId: groupId,
              senderId: from,
              envelope: content!,
            );
            encrypted = true;
          } on DuplicateMessageException {
            return; // replay
          } catch (err) {
            debugPrint('[group] decrypt failed: $err');
            // Shown as unreadable. Rendering the ciphertext, or trusting
            // whatever arrived, would misrepresent what was verified.
            content = null;
            emit(state.copyWith(error: GroupChatError.decryptFailed));
          }
        }

        emit(state.copyWith(messages: [
          ...state.messages,
          GroupChatMessage(
            id: f['message_id'] as String,
            senderId: from,
            content: content,
            createdAt: DateTime.parse(f['created_at'] as String).toLocal(),
            isMine: false,
            kind: f['message_type'] as String? ?? 'text',
            encrypted: encrypted,
            senderName: _nameOf(from),
          ),
        ]));
    }
  }
}

class _NoLongerAMember implements Exception {
  const _NoLongerAMember();
}
