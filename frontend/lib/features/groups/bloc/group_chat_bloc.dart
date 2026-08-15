import 'dart:async';
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart'
    show DuplicateMessageException;

import '../../../core/crypto/attachment_crypto.dart';
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

/// An attachment or voice note, already uploaded and encrypted.
class GroupMediaSent extends GroupChatEvent {
  const GroupMediaSent({
    required this.kind,
    required this.mediaKey,
    required this.mimeType,
    required this.attachmentKey,
    this.caption,
    this.duration,
    this.waveform,
  });

  final String kind; // 'image' | 'file' | 'voice'
  final String mediaKey;
  final String mimeType;

  /// Required, not optional: a group attachment is always encrypted, so a
  /// missing key would mean the body went up in the clear.
  final AttachmentKey attachmentKey;

  final String? caption;
  final double? duration;
  final List<double>? waveform;

  @override
  List<Object?> get props => [kind, mediaKey];
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
    on<GroupMediaSent>(_onMediaSent);
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
          final decrypted = await _crypto.decrypt(
            groupId: groupId,
            senderId: m.senderId,
            envelope: m.content!,
          );
          m.content = decrypted;
          m.encrypted = true;
          if (m.kind != 'text' && !_applyMediaPayload(m, decrypted)) {
            m.content = null;
          }
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

  Future<void> _onMediaSent(
      GroupMediaSent e, Emitter<GroupChatState> emit) async {
    emit(state.copyWith(sending: true));

    // The same payload shape the direct chat uses, so one envelope format
    // covers both and a reader does not have to learn two.
    final payload = jsonEncode({
      'media_key': e.mediaKey,
      'caption': e.caption,
      'mime': e.mimeType,
      'att': e.attachmentKey.toJson(),
      if (e.duration != null) 'dur': e.duration,
      if (e.waveform != null) 'wave': e.waveform,
    });

    final int epoch;
    final String envelope;
    try {
      epoch = await _ensureDistributed();
      envelope = await _crypto.encrypt(
        groupId: groupId,
        epoch: epoch,
        plaintext: payload,
      );
    } on _NoLongerAMember {
      emit(state.copyWith(sending: false, error: GroupChatError.notAMember));
      return;
    } on IdentityChanged {
      emit(state.copyWith(
          sending: false, error: GroupChatError.identityChanged));
      return;
    } catch (err) {
      debugPrint('[group] media encrypt failed: $err');
      // The body is already in storage, but it is ciphertext nobody holds a
      // key for, so abandoning the send leaks nothing.
      emit(state.copyWith(
          sending: false, error: GroupChatError.encryptFailed));
      return;
    }

    final ref = 'ref_${++_refCounter}';
    _ws.sendGroupMedia(
      group: groupId,
      kind: e.kind,
      content: envelope,
      clientRef: ref,
    );

    emit(state.copyWith(
      sending: false,
      epoch: epoch,
      messages: [
        ...state.messages,
        GroupChatMessage(
          id: ref,
          senderId: myId,
          content: e.caption,
          createdAt: DateTime.now(),
          isMine: true,
          kind: e.kind,
          pending: true,
          encrypted: true,
          mediaKey: e.mediaKey,
          attachmentKey: e.attachmentKey,
          duration: e.duration,
          waveform: e.waveform,
        ),
      ],
    ));
  }

  /// Unpacks a decrypted media envelope onto a message.
  ///
  /// Returns false when the payload is not the shape we sent, which is
  /// treated as an unreadable message rather than guessed at.
  bool _applyMediaPayload(GroupChatMessage message, String decrypted) {
    try {
      final payload = jsonDecode(decrypted) as Map<String, dynamic>;
      message.mediaKey = payload['media_key'] as String?;
      message.content = payload['caption'] as String?;
      final att = payload['att'];
      if (att != null) {
        message.attachmentKey =
            AttachmentKey.fromJson(att as Map<String, dynamic>);
      }
      message.duration = (payload['dur'] as num?)?.toDouble();
      final wave = payload['wave'] as List<dynamic>?;
      message.waveform =
          wave == null ? null : [for (final v in wave) (v as num).toDouble()];
      return true;
    } catch (err) {
      debugPrint('[group] media envelope malformed: $err');
      return false;
    }
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
              // Carries the media fields across. Rebuilding without them
              // blanks the sender's own attachment the instant it is
              // confirmed — the same way it did in the direct chat.
              GroupChatMessage(
                id: f['message_id'] as String,
                senderId: myId,
                content: m.content,
                createdAt: DateTime.parse(f['created_at'] as String).toLocal(),
                isMine: true,
                kind: m.kind,
                encrypted: m.encrypted,
                mediaKey: m.mediaKey,
                attachmentKey: m.attachmentKey,
                duration: m.duration,
                waveform: m.waveform,
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

        final kind = f['message_type'] as String? ?? 'text';
        final message = GroupChatMessage(
          id: f['message_id'] as String,
          senderId: from,
          content: content,
          createdAt: DateTime.parse(f['created_at'] as String).toLocal(),
          isMine: false,
          kind: kind,
          encrypted: encrypted,
          senderName: _nameOf(from),
        );

        // A media message carries its pointer and key inside the envelope,
        // so they only exist once it has been opened.
        if (encrypted && kind != 'text' && content != null) {
          if (!_applyMediaPayload(message, content)) {
            message.content = null;
            emit(state.copyWith(error: GroupChatError.decryptFailed));
          }
        }

        emit(state.copyWith(messages: [...state.messages, message]));
    }
  }
}

class _NoLongerAMember implements Exception {
  const _NoLongerAMember();
}
