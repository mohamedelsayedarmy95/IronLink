import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/crypto/group_signal.dart';
import '../../../core/crypto/signal.dart';
import '../../../core/icons.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/ws_service.dart';
import '../../../l10n/app_localizations.dart';
import '../bloc/group_chat_bloc.dart';
import '../groups_repository.dart';

/// An end-to-end encrypted group conversation.
class GroupChatScreen extends StatelessWidget {
  const GroupChatScreen({
    super.key,
    required this.group,
    required this.myId,
  });

  final GroupInfo group;
  final String myId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (ctx) => GroupChatBloc(
        groupId: group.id,
        myId: myId,
        repo: ctx.read<GroupsRepository>(),
        ws: ctx.read<WsService>(),
        groupCrypto: ctx.read<GroupSignalService>(),
        pairwise: ctx.read<SignalService>(),
      )..add(const GroupChatOpened()),
      child: _GroupChatView(group: group),
    );
  }
}

class _GroupChatView extends StatefulWidget {
  const _GroupChatView({required this.group});

  final GroupInfo group;

  @override
  State<_GroupChatView> createState() => _GroupChatViewState();
}

class _GroupChatViewState extends State<_GroupChatView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showError(GroupChatError error) {
    final t = L.of(context);
    final message = switch (error) {
      GroupChatError.identityChanged => t.secureIdentityChanged,
      GroupChatError.encryptFailed => t.secureEncryptFailed,
      GroupChatError.decryptFailed => t.groupMessageUnreadable,
      GroupChatError.notAMember => t.groupNoLongerMember,
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: IronColors.navySurface),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);

    return Scaffold(
      backgroundColor: IronColors.navyDeep,
      appBar: AppBar(
        backgroundColor: IronColors.navySurface,
        elevation: 0,
        shape: const Border(bottom: BorderSide(color: IronColors.navyBorder)),
        title: BlocBuilder<GroupChatBloc, GroupChatState>(
          builder: (context, state) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.group.name,
                  style: const TextStyle(
                      fontSize: 16, color: IronColors.textHi)),
              Row(
                children: [
                  const Icon(IronIcons.lock,
                      size: 11, color: IronColors.accentText),
                  const SizedBox(width: 4),
                  Text(
                    t.groupMembersCount(state.members.length),
                    style: const TextStyle(
                        fontSize: 11, color: IronColors.textTertiary),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: t.secretChatOn,
            icon: const Icon(IronIcons.lock, color: IronColors.accentText),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: IronColors.navySurface,
                title: Text(t.secretChatOn,
                    style: const TextStyle(color: IronColors.textHi)),
                content: Text(
                  '${t.groupEncryptionNotice}\n\n${t.groupRotationNotice}',
                  style: const TextStyle(color: IronColors.textTertiary),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(t.done,
                        style:
                            const TextStyle(color: IronColors.accentText)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: BlocConsumer<GroupChatBloc, GroupChatState>(
        listener: (context, state) {
          _jumpToBottom();
          final error = state.error;
          if (error != null) _showError(error);
        },
        builder: (context, state) {
          if (state.loading) {
            return const Center(
              child: CircularProgressIndicator(color: IronColors.accentText),
            );
          }

          return Column(
            children: [
              Expanded(
                child: state.messages.isEmpty
                    ? IronEmptyState(
                        title: t.groupNoMessages,
                        message: t.groupEncryptionNotice,
                        rings: 3,
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(16),
                        itemCount: state.messages.length,
                        itemBuilder: (context, i) =>
                            _GroupBubble(message: state.messages[i]),
                      ),
              ),
              if (state.canPost)
                _GroupInputBar(
                  controller: _input,
                  sending: state.sending,
                  onSend: () {
                    final text = _input.text.trim();
                    if (text.isEmpty) return;
                    context.read<GroupChatBloc>().add(GroupTextSent(text));
                    _input.clear();
                  },
                )
              else
                // Announcement groups: everyone reads, admins post. Showing a
                // composer that always fails would be worse than none.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  color: IronColors.navySurface,
                  child: SafeArea(
                    top: false,
                    child: Text(
                      t.groupAnnouncementOnly,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: IronColors.textTertiary, fontSize: 13),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _GroupBubble extends StatelessWidget {
  const _GroupBubble({required this.message});

  final GroupChatMessage message;

  static const _slateGrey = Color(0xFF3E4A5C);

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final mine = message.isMine;

    return Align(
      alignment: mine
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: mine
              ? const LinearGradient(
                  colors: [IronColors.goldBright, IronColors.gold],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: mine ? null : _slateGrey,
          borderRadius: BorderRadiusDirectional.only(
            topStart: const Radius.circular(16),
            topEnd: const Radius.circular(16),
            bottomStart: Radius.circular(mine ? 16 : 4),
            bottomEnd: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Groups need to say who is speaking; a one-to-one chat does not.
            if (!mine && message.senderName != null) ...[
              Text(
                message.senderName!,
                style: const TextStyle(
                  color: IronColors.accentText,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
            ],
            if (message.content == null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(IronIcons.lock,
                      size: IronIcons.sizeCompact, color: IronColors.textLo),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      t.groupMessageUnreadable,
                      style: const TextStyle(
                        color: IronColors.textLo,
                        fontStyle: FontStyle.italic,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              )
            else
              Text(
                message.content!,
                style: TextStyle(
                  color: mine ? IronColors.navyDeep : IronColors.textHi,
                  fontWeight: mine ? FontWeight.w600 : FontWeight.w400,
                  fontSize: 15,
                ),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!message.encrypted && message.content != null) ...[
                  Tooltip(
                    message: t.messageNotEncrypted,
                    child: Icon(
                      IronIcons.unlock,
                      size: 11,
                      semanticLabel: t.messageNotEncrypted,
                      color: mine
                          ? IronColors.navyDeep.withValues(alpha: 0.6)
                          : IronColors.textLo,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  _time(message.createdAt),
                  style: TextStyle(
                    fontSize: 10,
                    color: mine
                        ? IronColors.navyDeep.withValues(alpha: 0.6)
                        : IronColors.textLo,
                  ),
                ),
                if (message.pending) ...[
                  const SizedBox(width: 5),
                  SizedBox(
                    width: 9,
                    height: 9,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.4,
                      color: mine
                          ? IronColors.navyDeep.withValues(alpha: 0.6)
                          : IronColors.textLo,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
}

class _GroupInputBar extends StatelessWidget {
  const _GroupInputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: const BoxDecoration(
          color: IronColors.navySurface,
          border: Border(top: BorderSide(color: IronColors.navyBorder)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                enabled: !sending,
                decoration: InputDecoration(
                  hintText: t.messageHint,
                  fillColor: IronColors.navyDeep,
                ),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: IronColors.gold,
              child: sending
                  // The first send of an epoch distributes sender keys to
                  // every member first, which is not instant.
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: IronColors.navyDeep),
                    )
                  : IconButton(
                      tooltip: t.send,
                      icon: const Icon(IronIcons.send,
                          color: IronColors.navyDeep,
                          size: IronIcons.sizeInline),
                      onPressed: onSend,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
