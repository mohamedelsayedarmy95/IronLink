import 'package:flutter/material.dart';

import '../../../../core/failure.dart';
import '../../../../core/icons.dart';
import '../../../../core/theme.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/iron_button.dart';
import '../../../../l10n/app_localizations.dart';
import '../entry_repository.dart';
import '../models/verification_form.dart';

/// Record of sensitive actions taken on the group.
///
/// Paginated with "Load more" rather than numbered pages: entries arrive
/// newest-first and continuously, so page 2 would mean something different
/// each time it was opened.
class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({
    super.key,
    required this.repository,
    required this.groupId,
  });

  final GroupEntryRepository repository;
  final String groupId;

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  static const _pageSize = 25;

  /// Filter groupings. Related actions are collapsed into one choice so the
  /// menu reads as intents rather than as a list of enum values.
  static const _filters = <String, List<AuditAction>>{
    'approvals': [AuditAction.approveRequest, AuditAction.bulkApprove],
    'rejections': [AuditAction.rejectRequest, AuditAction.bulkReject],
    'bans': [AuditAction.banMember, AuditAction.unbanMember],
    'settings': [AuditAction.changeJoinMode, AuditAction.updateForm],
  };

  final _entries = <AuditEntry>[];

  String? _filter;
  NetworkFailure? _failure;
  bool _loading = true;
  bool _loadingMore = false;
  bool _exhausted = false;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _failure = null;
        _exhausted = false;
      });
    } else {
      setState(() => _loadingMore = true);
    }

    try {
      // One request per action in the group, since the endpoint filters by a
      // single action. Merged and re-sorted below.
      final actions = _filter == null ? <AuditAction?>[null] : _filters[_filter]!;
      final batches = await Future.wait([
        for (final a in actions)
          widget.repository.auditLog(
            widget.groupId,
            action: a?.wire,
            limit: _pageSize,
            offset: reset ? 0 : _entries.length,
          ),
      ]);
      if (!mounted) return;

      final merged = [for (final b in batches) ...b]
        ..sort((a, b) => (b.createdAt ?? DateTime(0))
            .compareTo(a.createdAt ?? DateTime(0)));

      setState(() {
        if (reset) _entries.clear();
        _entries.addAll(merged);
        // A short page means the server had nothing further to give.
        _exhausted = merged.length < _pageSize;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failure = NetworkFailureClassifier.from(e);
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);

    return Scaffold(
      backgroundColor: IronColors.backgroundPrimary,
      appBar: AppBar(title: Text(t.auditLogTitle)),
      body: Column(
        children: [
          _FilterBar(
            selected: _filter,
            options: _filters.keys.toList(),
            onSelected: (f) {
              setState(() => _filter = f);
              _load(reset: true);
            },
          ),
          Expanded(child: _body(t)),
        ],
      ),
    );
  }

  Widget _body(L t) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: IronColors.accentText),
      );
    }
    if (_failure != null) {
      return IronErrorState(
        title: t.auditLogLoadFailedTitle,
        message: failureMessage(t, _failure!),
        retryLabel: t.retry,
        onRetry: () => _load(reset: true),
      );
    }
    if (_entries.isEmpty) {
      return IronEmptyState(
        title: t.auditLogEmpty,
        message: t.auditLogEmptyHint,
        rings: 1,
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      color: IronColors.accentText,
      backgroundColor: IronColors.surfacePrimary,
      child: ListView.separated(
        padding: const EdgeInsets.all(IronSpacing.md),
        itemCount: _entries.length + (_exhausted ? 0 : 1),
        separatorBuilder: (_, __) => const SizedBox(height: IronSpacing.xs),
        itemBuilder: (context, i) {
          if (i >= _entries.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: IronSpacing.sm),
              child: IronButton(
                label: t.loadMore,
                variant: IronButtonVariant.secondary,
                loading: _loadingMore,
                onPressed: _loadingMore ? null : () => _load(),
              ),
            );
          }
          return _AuditRow(entry: _entries[i]);
        },
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.selected,
    required this.options,
    required this.onSelected,
  });

  final String? selected;
  final List<String> options;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: IronSpacing.md),
        children: [
          _chip(t.filterAll, selected == null, () => onSelected(null)),
          for (final o in options)
            _chip(_label(t, o), selected == o, () => onSelected(o)),
        ],
      ),
    );
  }

  Widget _chip(String label, bool active, VoidCallback onTap) => Padding(
        padding: const EdgeInsetsDirectional.only(end: IronSpacing.xs),
        child: Center(
          child: ChoiceChip(
            label: Text(label),
            selected: active,
            onSelected: (_) => onTap(),
            backgroundColor: IronColors.surfacePrimary,
            selectedColor: IronColors.accentSubtle,
            side: BorderSide(
              color: active
                  ? IronColors.accentText
                  : IronColors.borderInteractive,
            ),
            labelStyle: IronTypography.bodySmall(
              color: active ? IronColors.textPrimary : IronColors.textSecondary,
            ),
          ),
        ),
      );

  static String _label(L t, String key) => switch (key) {
        'approvals' => t.filterApprovals,
        'rejections' => t.filterRejections,
        'bans' => t.filterBans,
        'settings' => t.filterSettings,
        _ => key,
      };
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.entry});

  final AuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final (icon, color) = _mark(entry.action);

    return Container(
      padding: const EdgeInsets.all(IronSpacing.md),
      decoration: BoxDecoration(
        color: IronColors.surfacePrimary,
        borderRadius: BorderRadius.circular(IronRadius.md),
        border: Border.all(color: IronColors.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
            ),
            child: Icon(icon, size: IronIcons.sizeCompact, color: color),
          ),
          const SizedBox(width: IronSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title(t, entry),
                  style:
                      IronTypography.bodyLarge(color: IronColors.textPrimary),
                ),
                if (entry.detailLine != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    entry.detailLine!,
                    style: IronTypography.bodySmall(
                        color: IronColors.textSecondary),
                  ),
                ],
                const SizedBox(height: IronSpacing.xxs),
                Text(
                  _timestamp(entry.createdAt),
                  style: IronTypography.labelSmall(
                      color: IronColors.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static (IconData, Color) _mark(AuditAction action) => switch (action) {
        AuditAction.approveRequest ||
        AuditAction.bulkApprove =>
          (IronIcons.success, IronColors.semanticSuccess),
        AuditAction.rejectRequest ||
        AuditAction.bulkReject =>
          (IronIcons.blocked, IronColors.semanticError),
        AuditAction.banMember =>
          (IronIcons.shieldAlert, IronColors.semanticError),
        AuditAction.unbanMember =>
          (IronIcons.verified, IronColors.semanticSuccess),
        AuditAction.requestMoreInfo =>
          (IronIcons.info, IronColors.semanticInfo),
        AuditAction.changeJoinMode ||
        AuditAction.updateForm =>
          (IronIcons.settings, IronColors.textSecondary),
        AuditAction.removeMember =>
          (IronIcons.delete, IronColors.semanticWarning),
        AuditAction.assignModerator =>
          (IronIcons.admin, IronColors.semanticInfo),
        AuditAction.reopenRequest =>
          (IronIcons.refresh, IronColors.semanticInfo),
        AuditAction.exportAuditLog =>
          (IronIcons.document, IronColors.textSecondary),
        AuditAction.unknown => (IronIcons.info, IronColors.textTertiary),
      };

  static String _title(L t, AuditEntry entry) {
    final count = entry.count;
    return switch (entry.action) {
      AuditAction.approveRequest => t.auditApproved,
      AuditAction.rejectRequest => t.auditRejected,
      AuditAction.requestMoreInfo => t.auditMoreInfo,
      AuditAction.bulkApprove => t.auditBulkApproved(count ?? 0),
      AuditAction.bulkReject => t.auditBulkRejected(count ?? 0),
      AuditAction.banMember => t.auditBanned,
      AuditAction.unbanMember => t.auditUnbanned,
      AuditAction.removeMember => t.auditRemoved,
      AuditAction.changeJoinMode => t.auditJoinModeChanged,
      AuditAction.updateForm => t.auditFormUpdated,
      AuditAction.assignModerator => t.auditModeratorAssigned,
      AuditAction.reopenRequest => t.auditReopened,
      AuditAction.exportAuditLog => t.auditExported,
      // Falls back to the server's own name so an action this build predates
      // still appears rather than leaving a hole in the trail.
      AuditAction.unknown => entry.rawAction,
    };
  }

  static String _timestamp(DateTime? at) {
    if (at == null) return '';
    final local = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
