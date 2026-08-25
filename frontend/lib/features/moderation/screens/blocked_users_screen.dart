import 'package:flutter/material.dart';

import '../../../core/failure.dart';
import '../../../core/icons.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../l10n/app_localizations.dart';
import '../moderation_repository.dart';

/// The list of people this user has blocked, with one tap to undo.
///
/// Undo matters more than it looks: people block in anger and reconsider, and
/// a block that is hard to reverse turns a moment's decision into a permanent
/// one. The list is also the only honest answer to "who have I blocked?" —
/// there is deliberately no view of who has blocked *you*.
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key, required this.repository});

  final ModerationRepository repository;

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  List<BlockedUser>? _users;
  NetworkFailure? _failure;

  /// Ids currently being unblocked, so a slow network cannot produce two
  /// requests for the same row.
  final _pending = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failure = null);
    try {
      final users = await widget.repository.blockedUsers();
      if (!mounted) return;
      setState(() => _users = users);
    } catch (e) {
      if (!mounted) return;
      setState(() => _failure = NetworkFailureClassifier.from(e));
    }
  }

  Future<void> _unblock(BlockedUser user) async {
    if (!_pending.add(user.userId)) return;
    setState(() {});

    try {
      await widget.repository.unblock(user.userId);
      if (!mounted) return;
      setState(() {
        _users = [..._users ?? []]..removeWhere((u) => u.userId == user.userId);
        _pending.remove(user.userId);
      });
      _toast(L.of(context).userUnblocked(user.fullName));
    } catch (e) {
      if (!mounted) return;
      setState(() => _pending.remove(user.userId));
      _toast(failureMessage(L.of(context), NetworkFailureClassifier.from(e)));
    }
  }

  void _toast(String message) {
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
        title: Text(t.blockedUsers),
      ),
      body: _build(t),
    );
  }

  Widget _build(L t) {
    final failure = _failure;
    if (failure != null) {
      return IronErrorState(
        title: t.blockedUsers,
        message: failureMessage(t, failure),
        onRetry: _load,
      );
    }

    final users = _users;
    if (users == null) {
      return const Center(
        child: CircularProgressIndicator(color: IronColors.accentText),
      );
    }

    if (users.isEmpty) {
      return IronEmptyState(
        title: t.blockedUsersEmpty,
        message: t.blockedUsersEmptyHint,
        // One ring: this list is about individuals, not a group.
        rings: 1,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: IronColors.accentText,
      backgroundColor: IronColors.navySurface,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: users.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: IronColors.borderSubtle),
        itemBuilder: (_, i) {
          final user = users[i];
          final busy = _pending.contains(user.userId);
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: IronColors.navySurface,
              child: Text(
                user.fullName.isEmpty ? '?' : user.fullName.characters.first,
                style: const TextStyle(color: IronColors.textTertiary),
              ),
            ),
            title: Text(user.fullName,
                style: const TextStyle(color: IronColors.textHi)),
            subtitle: Text(
              t.blockedOn(_date(user.blockedAt)),
              style:
                  const TextStyle(color: IronColors.textTertiary, fontSize: 12),
            ),
            trailing: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: IronColors.accentText),
                  )
                : TextButton(
                    onPressed: () => _unblock(user),
                    child: Text(
                      t.unblockUser,
                      style: const TextStyle(color: IronColors.accentText),
                    ),
                  ),
          );
        },
      ),
    );
  }

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Confirmation before blocking.
///
/// Kept as one function so every entry point — the chat menu, a profile, the
/// report sheet — asks the same question and states the same consequence.
Future<bool> confirmBlock(BuildContext context, String name) async {
  final t = L.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: IronColors.navySurface,
      title: Text(t.blockUserTitle(name),
          style: const TextStyle(color: IronColors.textHi)),
      content: Text(t.blockUserBody,
          style: const TextStyle(color: IronColors.textTertiary)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(t.cancel,
              style: const TextStyle(color: IronColors.textTertiary)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(t.blockUser,
              style: const TextStyle(color: IronColors.errorRed)),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Icon used by callers so the affordance looks the same everywhere.
const blockIcon = IronIcons.blocked;
