import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/failure.dart';
import '../../../../core/icons.dart';
import '../../../../core/theme.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/iron_button.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../settings/ocr_settings_page.dart' show failureMessage;
import '../entry_repository.dart';
import '../models/verification_form.dart';

/// Admin review of join requests: pending, expired, and decided.
///
/// Expired requests get their own tab rather than being deleted — an admin
/// who missed a request should still be able to see that it happened.
class PendingRequestsScreen extends StatefulWidget {
  const PendingRequestsScreen({
    super.key,
    required this.repository,
    required this.groupId,
    required this.groupName,
    this.form,
  });

  final GroupEntryRepository repository;
  final String groupId;
  final String groupName;

  /// The group's active form, used to label answers. Without it the review
  /// list can only show raw values, which is not reviewable.
  final VerificationForm? form;

  @override
  State<PendingRequestsScreen> createState() => _PendingRequestsScreenState();
}

class _PendingRequestsScreenState extends State<PendingRequestsScreen>
    with SingleTickerProviderStateMixin {
  static const _tabs = [
    JoinRequestStatus.pending,
    JoinRequestStatus.expired,
    JoinRequestStatus.approved,
  ];

  late final TabController _tabs_ = TabController(length: _tabs.length, vsync: this)
    ..addListener(_onTabChanged);

  final Map<JoinRequestStatus, List<JoinRequest>> _byStatus = {};
  final Set<String> _selected = {};

  Map<String, int> _counts = {};
  NetworkFailure? _failure;
  bool _loading = true;
  bool _busy = false;
  bool _selectMode = false;

  JoinRequestStatus get _status => _tabs[_tabs_.index];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs_.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabs_.indexIsChanging) return;
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
    if (!_byStatus.containsKey(_status)) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final results = await Future.wait([
        widget.repository.requests(widget.groupId, status: _status),
        widget.repository.counts(widget.groupId),
      ]);
      if (!mounted) return;
      setState(() {
        _byStatus[_status] = results[0] as List<JoinRequest>;
        _counts = results[1] as Map<String, int>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failure = NetworkFailureClassifier.from(e);
        _loading = false;
      });
    }
  }

  Future<void> _decide(
    JoinRequest req, {
    required bool approve,
    String? reason,
  }) async {
    setState(() => _busy = true);
    try {
      if (approve) {
        await widget.repository.approve(widget.groupId, req.id);
      } else {
        await widget.repository.reject(widget.groupId, req.id, reason: reason);
      }
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      await _load();
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      _toast(failureMessage(L.of(context), NetworkFailureClassifier.from(e)));
      setState(() => _busy = false);
    }
  }

  Future<void> _bulk({required bool approve}) async {
    final t = L.of(context);
    final ids = _selectMode ? _selected.toList() : null;
    final count = ids?.length ?? (_counts[JoinRequestStatus.pending.wire] ?? 0);
    if (count == 0) return;

    final confirmed = await _confirm(
      title: approve ? t.approveAllTitle : t.rejectAllTitle,
      message: approve
          ? t.approveAllConfirm(count)
          : t.rejectAllConfirm(count),
      // Reject-all is irreversible for everyone it touches, so it is styled
      // as destructive and never the default action.
      destructive: !approve,
      confirmLabel: approve ? t.approve : t.reject,
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      final result = await widget.repository.bulk(
        widget.groupId,
        approve: approve,
        requestIds: ids,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _toast(t.bulkResult(result.succeeded));
      setState(() {
        _selectMode = false;
        _selected.clear();
      });
      await _load();
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      _toast(failureMessage(L.of(context), NetworkFailureClassifier.from(e)));
      setState(() => _busy = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final t = L.of(context);
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(t.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(
                  foregroundColor: destructive
                      ? IronColors.semanticError
                      : IronColors.accentText,
                ),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final pending = _counts[JoinRequestStatus.pending.wire] ?? 0;

    return Scaffold(
      backgroundColor: IronColors.backgroundPrimary,
      appBar: AppBar(
        title: Text(t.joinRequestsTitle),
        actions: [
          if (_status == JoinRequestStatus.pending && pending > 0)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _selectMode = !_selectMode;
                        _selected.clear();
                      }),
              child: Text(_selectMode ? t.cancel : t.select),
            ),
        ],
        bottom: TabBar(
          controller: _tabs_,
          labelColor: IronColors.accentText,
          unselectedLabelColor: IronColors.textTertiary,
          indicatorColor: IronColors.accentText,
          tabs: [
            for (final s in _tabs)
              Tab(text: '${_tabLabel(t, s)} (${_counts[s.wire] ?? 0})'),
          ],
        ),
      ),
      body: _body(t),
      bottomNavigationBar: _bulkBar(t, pending),
    );
  }

  String _tabLabel(L t, JoinRequestStatus s) => switch (s) {
        JoinRequestStatus.pending => t.tabPending,
        JoinRequestStatus.expired => t.tabExpired,
        JoinRequestStatus.approved => t.tabHistory,
        _ => s.wire,
      };

  Widget? _bulkBar(L t, int pending) {
    final showing = _status == JoinRequestStatus.pending &&
        (_selectMode ? _selected.isNotEmpty : pending > 0);
    if (!showing) return null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(IronSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: IronButton(
                label: _selectMode
                    ? t.approveSelected(_selected.length)
                    : t.approveAll,
                onPressed: _busy ? null : () => _bulk(approve: true),
              ),
            ),
            const SizedBox(width: IronSpacing.sm),
            Expanded(
              child: IronButton(
                label: _selectMode
                    ? t.rejectSelected(_selected.length)
                    : t.rejectAll,
                variant: IronButtonVariant.destructive,
                onPressed: _busy ? null : () => _bulk(approve: false),
              ),
            ),
          ],
        ),
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
        title: t.requestsLoadFailedTitle,
        message: failureMessage(t, _failure!),
        retryLabel: t.retry,
        onRetry: _load,
      );
    }

    final rows = _byStatus[_status] ?? const <JoinRequest>[];
    if (rows.isEmpty) {
      return IronEmptyState(
        title: _status == JoinRequestStatus.pending
            ? t.noPendingRequests
            : t.nothingHere,
        message: _status == JoinRequestStatus.pending
            ? t.noPendingRequestsHint
            : t.nothingHereHint,
        rings: 3,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: IronColors.accentText,
      backgroundColor: IronColors.surfacePrimary,
      child: ListView.separated(
        padding: const EdgeInsets.all(IronSpacing.md),
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: IronSpacing.sm),
        itemBuilder: (context, i) => _RequestCard(
          request: rows[i],
          form: widget.form,
          busy: _busy,
          selectable: _selectMode && _status == JoinRequestStatus.pending,
          selected: _selected.contains(rows[i].id),
          onSelectedChanged: (on) => setState(() {
            on ? _selected.add(rows[i].id) : _selected.remove(rows[i].id);
          }),
          onApprove: () => _decide(rows[i], approve: true),
          onReject: () async {
            final reason = await _askReason(t);
            if (reason == null) return;
            await _decide(rows[i], approve: false,
                reason: reason.isEmpty ? null : reason);
          },
        ),
      ),
    );
  }

  Future<String?> _askReason(L t) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.rejectRequestTitle),
        content: TextField(
          controller: controller,
          maxLines: 3,
          maxLength: 500,
          decoration: InputDecoration(hintText: t.rejectionReasonOptional),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: TextButton.styleFrom(
                foregroundColor: IronColors.semanticError),
            child: Text(t.reject),
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends StatefulWidget {
  const _RequestCard({
    required this.request,
    required this.form,
    required this.busy,
    required this.selectable,
    required this.selected,
    required this.onSelectedChanged,
    required this.onApprove,
    required this.onReject,
  });

  final JoinRequest request;
  final VerificationForm? form;
  final bool busy;
  final bool selectable;
  final bool selected;
  final ValueChanged<bool> onSelectedChanged;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final req = widget.request;
    final actionable = req.status == JoinRequestStatus.pending ||
        req.status == JoinRequestStatus.moreInfoNeeded;

    return Container(
      decoration: BoxDecoration(
        color: IronColors.surfacePrimary,
        borderRadius: BorderRadius.circular(IronRadius.md),
        border: Border.all(
          color: widget.selected
              ? IronColors.accentText
              : IronColors.borderSubtle,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(IronRadius.md),
            child: Padding(
              padding: const EdgeInsets.all(IronSpacing.md),
              child: Row(
                children: [
                  if (widget.selectable)
                    SizedBox(
                      width: 40,
                      child: Checkbox(
                        value: widget.selected,
                        onChanged: (v) => widget.onSelectedChanged(v ?? false),
                        activeColor: IronColors.accentPrimary,
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          // The requester's display name is not on the
                          // request payload yet; the id keeps the row
                          // identifiable rather than showing a blank.
                          req.userId,
                          overflow: TextOverflow.ellipsis,
                          style: IronTypography.bodyLarge(
                              color: IronColors.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _relative(t, req.createdAt),
                          style: IronTypography.bodySmall(
                              color: IronColors.textTertiary),
                        ),
                      ],
                    ),
                  ),
                  _StatusChip(status: req.status),
                  const SizedBox(width: IronSpacing.xs),
                  Icon(
                    _expanded ? IronIcons.close : IronIcons.forward,
                    size: IronIcons.sizeCompact,
                    color: IronColors.textTertiary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1, color: IronColors.borderSubtle),
            Padding(
              padding: const EdgeInsets.all(IronSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ..._answerRows(t),
                  if (req.rejectionReason != null) ...[
                    const SizedBox(height: IronSpacing.xs),
                    Text(
                      '${t.rejectionReasonLabel}: ${req.rejectionReason}',
                      style: IronTypography.bodySmall(
                          color: IronColors.semanticError),
                    ),
                  ],
                  if (actionable) ...[
                    const SizedBox(height: IronSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: IronButton(
                            label: t.approve,
                            onPressed: widget.busy ? null : widget.onApprove,
                          ),
                        ),
                        const SizedBox(width: IronSpacing.sm),
                        Expanded(
                          child: IronButton(
                            label: t.reject,
                            variant: IronButtonVariant.secondary,
                            onPressed: widget.busy ? null : widget.onReject,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _answerRows(L t) {
    final answers = widget.request.answers;
    if (answers.isEmpty) {
      return [
        Text(
          t.noAnswersSubmitted,
          style: IronTypography.bodySmall(color: IronColors.textTertiary),
        ),
      ];
    }

    // Labels come from the form; without it the ids alone are unreviewable,
    // so the raw key is shown rather than nothing.
    final labels = {
      for (final f in widget.form?.fields ?? const []) f.id: f.label,
    };

    return [
      for (final entry in answers.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: IronSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 130,
                child: Text(
                  labels[entry.key] ?? entry.key,
                  style: IronTypography.bodySmall(
                      color: IronColors.textTertiary),
                ),
              ),
              const SizedBox(width: IronSpacing.xs),
              Expanded(
                child: Text(
                  _display(entry.value),
                  style: IronTypography.bodyMedium(
                      color: IronColors.textPrimary),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  static String _display(dynamic value) {
    if (value is List) return value.join('، ');
    if (value is bool) return value ? '✓' : '✕';
    return value?.toString() ?? '';
  }

  static String _relative(L t, DateTime? at) {
    if (at == null) return '';
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 60) return t.minutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return t.hoursAgo(diff.inHours);
    return t.daysAgo(diff.inDays);
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final JoinRequestStatus status;

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final (label, color) = switch (status) {
      JoinRequestStatus.pending => (t.statusPending, IronColors.semanticWarning),
      JoinRequestStatus.approved => (t.statusApproved, IronColors.semanticSuccess),
      JoinRequestStatus.rejected => (t.statusRejected, IronColors.semanticError),
      JoinRequestStatus.moreInfoNeeded =>
        (t.statusMoreInfo, IronColors.semanticInfo),
      JoinRequestStatus.expired => (t.statusExpired, IronColors.textTertiary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: IronSpacing.xs, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(IronRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: IronTypography.labelSmall(color: color),
      ),
    );
  }
}
