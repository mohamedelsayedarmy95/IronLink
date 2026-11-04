import 'package:flutter/material.dart';

import '../../../../core/icons.dart';
import '../../../../core/theme.dart';
import '../../../../core/widgets/iron_button.dart';
import '../../../../l10n/app_localizations.dart';
import '../models/verification_form.dart';

/// Where an applicant's own request stands, and what they can do about it.
///
/// Every state offers exactly one next step, or says plainly that there is
/// none. A status with no path forward and no explanation is what makes a
/// gated group feel arbitrary rather than deliberate.
class RequestStatusCard extends StatelessWidget {
  const RequestStatusCard({
    super.key,
    required this.request,
    this.onCancel,
    this.onAmend,
    this.onRequestAgain,
    this.busy = false,
  });

  final JoinRequest request;
  final VoidCallback? onCancel;
  final VoidCallback? onAmend;
  final VoidCallback? onRequestAgain;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final (icon, color, title, body) = _content(t);

    return Container(
      padding: const EdgeInsets.all(IronSpacing.md),
      decoration: BoxDecoration(
        color: IronColors.surfacePrimary,
        borderRadius: BorderRadius.circular(IronRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                child: Text(
                  title,
                  style: IronTypography.bodyLarge(
                      color: IronColors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: IronSpacing.xs),
          Text(
            body,
            style: IronTypography.bodyMedium(color: IronColors.textSecondary),
          ),

          // The admin's own words, shown verbatim rather than summarised —
          // it is the only thing telling the applicant what to change.
          if (request.status == JoinRequestStatus.moreInfoNeeded &&
              request.adminNotes != null) ...[
            const SizedBox(height: IronSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(IronSpacing.sm),
              decoration: BoxDecoration(
                color: IronColors.surfaceSecondary,
                borderRadius: BorderRadius.circular(IronRadius.sm),
              ),
              child: Text(
                request.adminNotes!,
                style:
                    IronTypography.bodyMedium(color: IronColors.textPrimary),
              ),
            ),
          ],

          if (request.status == JoinRequestStatus.rejected &&
              request.rejectionReason != null) ...[
            const SizedBox(height: IronSpacing.sm),
            Text(
              '${t.rejectionReasonLabel}: ${request.rejectionReason}',
              style:
                  IronTypography.bodySmall(color: IronColors.semanticError),
            ),
          ],

          ..._actions(t),
        ],
      ),
    );
  }

  List<Widget> _actions(L t) {
    final buttons = <Widget>[];

    switch (request.status) {
      case JoinRequestStatus.pending:
        if (onCancel != null) {
          buttons.add(IronButton(
            label: t.cancelRequest,
            variant: IronButtonVariant.secondary,
            onPressed: busy ? null : onCancel,
          ));
        }
      case JoinRequestStatus.moreInfoNeeded:
        if (onAmend != null) {
          buttons.add(IronButton(
            label: t.amendRequest,
            onPressed: busy ? null : onAmend,
          ));
        }
        if (onCancel != null) {
          buttons.add(IronButton(
            label: t.cancelRequest,
            variant: IronButtonVariant.ghost,
            onPressed: busy ? null : onCancel,
          ));
        }
      case JoinRequestStatus.expired:
        if (onRequestAgain != null) {
          buttons.add(IronButton(
            label: t.requestAgain,
            onPressed: busy ? null : onRequestAgain,
          ));
        }
      // Approved needs no action; rejected offers none unless the group
      // allows re-applying, which the caller decides by passing a callback.
      case JoinRequestStatus.approved:
        break;
      case JoinRequestStatus.rejected:
        if (onRequestAgain != null) {
          buttons.add(IronButton(
            label: t.requestAgain,
            variant: IronButtonVariant.secondary,
            onPressed: busy ? null : onRequestAgain,
          ));
        }
    }

    if (buttons.isEmpty) return const [];
    return [
      const SizedBox(height: IronSpacing.md),
      for (final b in buttons) ...[
        b,
        const SizedBox(height: IronSpacing.xs),
      ],
    ];
  }

  (IconData, Color, String, String) _content(L t) => switch (request.status) {
        JoinRequestStatus.pending => (
            IronIcons.pending,
            IronColors.semanticWarning,
            t.statusPending,
            t.statusPendingBody,
          ),
        JoinRequestStatus.approved => (
            IronIcons.success,
            IronColors.semanticSuccess,
            t.statusApproved,
            t.statusApprovedBody,
          ),
        JoinRequestStatus.rejected => (
            IronIcons.blocked,
            IronColors.semanticError,
            t.statusRejected,
            t.statusRejectedBody,
          ),
        JoinRequestStatus.moreInfoNeeded => (
            IronIcons.info,
            IronColors.semanticInfo,
            t.statusMoreInfo,
            t.statusMoreInfoBody,
          ),
        JoinRequestStatus.expired => (
            IronIcons.pending,
            IronColors.textTertiary,
            t.statusExpired,
            t.statusExpiredBody,
          ),
      };
}
