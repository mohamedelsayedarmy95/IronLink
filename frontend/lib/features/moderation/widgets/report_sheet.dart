import 'package:dio/dio.dart' show DioException;
import 'package:flutter/material.dart';

import '../../../core/failure.dart';
import '../../../core/icons.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/iron_button.dart';
import '../../../l10n/app_localizations.dart';
import '../moderation_repository.dart';

/// Outcome handed back to the caller, so the chat screen can react without
/// the sheet needing to know anything about it.
class ReportOutcome {
  const ReportOutcome({required this.submitted, required this.alsoBlocked});

  final bool submitted;
  final bool alsoBlocked;
}

/// The report flow.
///
/// Reporting is a moment of stress, so the sheet asks exactly one required
/// question — what is wrong — and treats everything else as optional. The
/// "block them as well" option is on the same screen because someone who has
/// just reported harassment almost always wants it, and making them find a
/// second menu afterwards is a poor answer to that.
Future<ReportOutcome?> showReportSheet(
  BuildContext context, {
  required ModerationRepository repository,
  required String reportedUserId,
  required String reportedUserName,
  String? messageId,
  String? contentSnapshot,
}) {
  return showModalBottomSheet<ReportOutcome>(
    context: context,
    isScrollControlled: true,
    backgroundColor: IronColors.navySurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ReportSheet(
      repository: repository,
      reportedUserId: reportedUserId,
      reportedUserName: reportedUserName,
      messageId: messageId,
      contentSnapshot: contentSnapshot,
    ),
  );
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({
    required this.repository,
    required this.reportedUserId,
    required this.reportedUserName,
    this.messageId,
    this.contentSnapshot,
  });

  final ModerationRepository repository;
  final String reportedUserId;
  final String reportedUserName;
  final String? messageId;
  final String? contentSnapshot;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _details = TextEditingController();
  ReportReason? _reason;
  bool _alsoBlock = false;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  String _label(L t, ReportReason reason) => switch (reason) {
        ReportReason.spam => t.reasonSpam,
        ReportReason.harassment => t.reasonHarassment,
        ReportReason.impersonation => t.reasonImpersonation,
        ReportReason.scam => t.reasonScam,
        ReportReason.illegalContent => t.reasonIllegalContent,
        ReportReason.leakedClassified => t.reasonLeakedClassified,
        ReportReason.other => t.reasonOther,
      };

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null || _sending) return;

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      await widget.repository.report(
        reportedUserId: widget.reportedUserId,
        reason: reason,
        messageId: widget.messageId,
        details: _details.text.trim(),
        contentSnapshot: widget.contentSnapshot,
      );
      if (_alsoBlock) {
        await widget.repository.block(widget.reportedUserId);
      }
      if (!mounted) return;
      Navigator.pop(
        context,
        ReportOutcome(submitted: true, alsoBlocked: _alsoBlock),
      );
    } catch (e) {
      if (!mounted) return;
      final t = L.of(context);
      setState(() {
        _sending = false;
        // A duplicate is not an error the user can fix by retrying, so it
        // gets its own sentence rather than the generic "rejected".
        _error = e is DioException && e.response?.statusCode == 409
            ? t.reportAlreadySent
            // Mapped, never the raw exception: a Dio stack trace in a
            // bottom sheet tells the user nothing and reads as a crash.
            : failureMessage(t, NetworkFailureClassifier.from(e));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final insets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: IronColors.borderInteractive,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                t.reportTitle,
                style: const TextStyle(
                  color: IronColors.textHi,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.reportedUserName,
                style: const TextStyle(
                    color: IronColors.textTertiary, fontSize: 13),
              ),
              const SizedBox(height: 18),
              Text(
                t.reportReasonQuestion,
                style: const TextStyle(
                  color: IronColors.textHi,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              for (final reason in ReportReason.values)
                _ReasonTile(
                  label: _label(t, reason),
                  selected: _reason == reason,
                  onTap: _sending
                      ? null
                      : () => setState(() => _reason = reason),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _details,
                enabled: !_sending,
                maxLines: 3,
                maxLength: 2000,
                style: const TextStyle(color: IronColors.textHi),
                decoration: InputDecoration(
                  labelText: t.reportDetails,
                  labelStyle:
                      const TextStyle(color: IronColors.textTertiary),
                  enabledBorder: const OutlineInputBorder(
                    borderSide:
                        BorderSide(color: IronColors.borderInteractive),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: IronColors.accentPrimary),
                  ),
                ),
              ),
              if (widget.contentSnapshot != null) ...[
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(IronIcons.info,
                        size: IronIcons.sizeCompact,
                        color: IronColors.textTertiary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t.reportEvidenceNotice,
                        style: const TextStyle(
                            color: IronColors.textTertiary, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _alsoBlock,
                onChanged: _sending
                    ? null
                    : (v) => setState(() => _alsoBlock = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: IronColors.accentPrimary,
                title: Text(
                  t.reportAlsoBlock,
                  style: const TextStyle(color: IronColors.textHi),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(
                      color: IronColors.errorRed, fontSize: 13),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: IronButton(
                  label: t.reportSubmit,
                  loading: _sending,
                  // Disabled until a reason is chosen: a report with no
                  // reason cannot be triaged, so it is not worth sending.
                  onPressed: _reason == null ? null : _submit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReasonTile extends StatelessWidget {
  const _ReasonTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: selected
                ? IronColors.accentPrimary.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? IronColors.accentPrimary
                  : IronColors.borderInteractive,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? IronIcons.radioOn : IronIcons.radioOff,
                size: IronIcons.sizeCompact,
                color: selected
                    ? IronColors.accentText
                    : IronColors.textTertiary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                      color: IronColors.textHi, fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
