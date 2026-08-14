import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import 'groups_repository.dart';

/// My-groups list; tapping a group shows its members with rank icons.
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key, required this.repo});

  final GroupsRepository repo;

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
            return ListView(children: [
              const SizedBox(height: 160),
              const Icon(Icons.groups_outlined,
                  size: 64, color: IronColors.goldDim),
              const SizedBox(height: 16),
              Center(
                child: Text(L.of(context).notInAnyGroupYet,
                    style: const TextStyle(color: IronColors.textLo)),
              ),
            ]);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: groups.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _GroupCard(
              group: groups[i],
              onTap: () => _showMembers(context, groups[i]),
            ),
          );
        },
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
  const _GroupCard({required this.group, required this.onTap});

  final GroupInfo group;
  final VoidCallback onTap;

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
                      ? Icons.campaign_outlined
                      : Icons.groups_outlined,
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
                          const Icon(Icons.star,
                              size: 15, color: IronColors.gold),
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
              const Icon(Icons.chevron_left, color: IronColors.textLo),
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
            const Icon(Icons.star, size: 15, color: IronColors.gold)
          else if (member.isObserver)
            const Icon(Icons.visibility_outlined,
                size: 15, color: IronColors.textLo),
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
