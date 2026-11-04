import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../core/widgets/empty_state.dart';
import '../../l10n/app_localizations.dart';
import 'entry/entry_repository.dart';
import 'entry/models/verification_form.dart';
import 'entry/screens/group_entry_screen.dart';
import 'entry/screens/group_entry_settings_screen.dart';
import 'entry/screens/pending_requests_screen.dart';
import 'groups_repository.dart';
import 'screens/group_chat_screen.dart';

/// My-groups list; tapping a group shows its members with rank icons.
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key, required this.repo, required this.myId});

  final GroupsRepository repo;
  final String myId;

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  late Future<List<GroupInfo>> _future = widget.repo.myGroups();

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: IronColors.gold,
      backgroundColor: IronColors.navySurface,
      onRefresh: () async {
        setState(() => _future = widget.repo.myGroups());
        await _future;
      },
      child: FutureBuilder<List<GroupInfo>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
                child: CircularProgressIndicator(color: IronColors.gold));
          }
          final groups = snap.data ?? [];
          if (groups.isEmpty) {
            return LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IronEmptyState(
                    title: L.of(context).notInAnyGroupYet,
                    message: L.of(context).notInAnyGroupYetHint,
                    rings: 3,
                  ),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: groups.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _GroupCard(
              group: groups[i],
              // A member goes to the conversation, which is what a group is
              // for; anyone without a role is looking at a group they have
              // not joined, so the entry screen is the useful destination.
              onTap: () => groups[i].myRole == null
                  ? _openEntry(context, groups[i])
                  : _openChat(context, groups[i]),
              onShowMembers: () => _showMembers(context, groups[i]),
              onReviewRequests: _canReview(groups[i])
                  ? () => _openRequests(context, groups[i])
                  : null,
              // Entry configuration is admin-only; moderators may review
              // requests but not change the rules they are reviewed under.
              onOpenSettings: _canConfigure(groups[i])
                  ? () => _openSettings(context, groups[i])
                  : null,
            ),
          );
        },
      ),
    );
  }

  /// Reviewing entry requests is a moderator-and-above capability, matching
  /// the permission the server enforces. Showing the affordance to a member
  /// would only produce a 403 they can do nothing about.
  static bool _canReview(GroupInfo group) =>
      const {'moderator', 'admin', 'owner'}.contains(group.myRole);

  void _openChat(BuildContext context, GroupInfo group) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupChatScreen(group: group, myId: widget.myId),
      ),
    );
  }

  static bool _canConfigure(GroupInfo group) =>
      const {'admin', 'owner'}.contains(group.myRole);

  Future<void> _openEntry(BuildContext context, GroupInfo group) =>
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GroupEntryScreen(
            repository: context.read<GroupEntryRepository>(),
            groupId: group.id,
            groupName: group.name,
            groupDescription: group.description,
            memberCount: group.memberCount,
          ),
        ),
      );

  Future<void> _openSettings(BuildContext context, GroupInfo group) =>
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GroupEntrySettingsScreen(
            repository: context.read<GroupEntryRepository>(),
            groupId: group.id,
            groupName: group.name,
          ),
        ),
      );

  Future<void> _openRequests(BuildContext context, GroupInfo group) async {
    final repo = context.read<GroupEntryRepository>();

    // The active form is fetched up front so answers can be shown against
    // their labels; a review screen listing bare field ids is not reviewable.
    VerificationForm? form;
    try {
      form = await repo.activeForm(group.id);
    } catch (_) {
      // Non-fatal: the list still works, answers just fall back to raw keys.
    }
    if (!context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PendingRequestsScreen(
          repository: repo,
          groupId: group.id,
          groupName: group.name,
          form: form,
        ),
      ),
    );
  }

  void _showMembers(BuildContext context, GroupInfo group) {
    final t = L.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: IronColors.navySurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, scrollController) =>
            FutureBuilder<List<GroupMemberInfo>>(
          future: widget.repo.members(group.id),
          builder: (context, snap) {
            final members = snap.data ?? [];
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    t.groupMembersTitle(group.name, group.memberCount),
                    style: const TextStyle(
                        color: IronColors.gold,
                        fontSize: 17,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  child: snap.connectionState != ConnectionState.done
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: IronColors.gold))
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: members.length,
                          itemBuilder: (context, i) =>
                              _MemberTile(member: members[i]),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.onTap,
    this.onShowMembers,
    this.onReviewRequests,
    this.onOpenSettings,
  });

  final GroupInfo group;
  final VoidCallback onTap;

  /// Opening the group now goes to the conversation, so the member list
  /// needs its own way in.
  final VoidCallback? onShowMembers;

  /// Null for members, who cannot review entry requests.
  final VoidCallback? onReviewRequests;

  /// Null for anyone below admin, who cannot change entry rules.
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: IronColors.navySurface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: IronColors.navyBorder),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: IronColors.navyDeep,
                child: Icon(
                  group.isAnnouncement
                      ? IronIcons.broadcasts
                      : IronIcons.groups,
                  color: IronColors.gold,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(group.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                        ),
                        if (group.myRole == 'admin' ||
                            group.myRole == 'owner') ...[
                          const SizedBox(width: 6),
                          const Icon(IronIcons.admin,
                              size: IronIcons.sizeCompact, color: IronColors.gold),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      group.isAnnouncement
                          ? L.of(context).announcementChannelReadOnly
                          : L.of(context).memberCount(group.memberCount),
                      style: const TextStyle(
                          color: IronColors.textLo, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (onShowMembers != null && group.myRole != null)
                IconButton(
                  tooltip: L.of(context).groupMembersCount(group.memberCount),
                  icon: const Icon(IronIcons.groups,
                      size: IronIcons.sizeInline),
                  color: IronColors.textLo,
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: onShowMembers,
                ),
              if (onOpenSettings != null)
                IconButton(
                  tooltip: L.of(context).entrySettingsTitle,
                  icon: const Icon(IronIcons.settings,
                      size: IronIcons.sizeInline),
                  color: IronColors.textLo,
                  // 48px target: the glyph alone sits well under the floor.
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: onOpenSettings,
                ),
              if (onReviewRequests != null)
                IconButton(
                  tooltip: L.of(context).joinRequestsTitle,
                  icon: const Icon(IronIcons.verified,
                      size: IronIcons.sizeInline),
                  color: IronColors.gold,
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: onReviewRequests,
                ),
              if (onOpenSettings == null &&
                  onReviewRequests == null &&
                  onShowMembers == null)
                const Icon(IronIcons.forward, color: IronColors.textLo),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member});

  final GroupMemberInfo member;

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: IronColors.navyDeep,
        child: Text(
          member.fullName.characters.first,
          style: const TextStyle(
              color: IronColors.gold, fontWeight: FontWeight.w700),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(member.fullName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: IronColors.textHi)),
          ),
          const SizedBox(width: 6),
          // Rank icon: gold star = admin/owner, eye = observer
          if (member.isAdmin)
            const Icon(IronIcons.admin, size: IronIcons.sizeCompact, color: IronColors.gold)
          else if (member.isObserver)
            const Icon(IronIcons.show,
                size: IronIcons.sizeCompact, color: IronColors.textLo),
        ],
      ),
      subtitle: Text(
        switch (member.role) {
          'owner' => t.roleOwner,
          'admin' => t.roleAdmin,
          'moderator' => t.roleModerator,
          'observer' => t.roleObserver,
          _ => t.roleMember,
        },
        style: const TextStyle(color: IronColors.textLo, fontSize: 12),
      ),
    );
  }
}
