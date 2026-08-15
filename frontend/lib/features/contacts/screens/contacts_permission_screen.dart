import 'package:flutter/material.dart';

import '../../../core/icons.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/iron_button.dart';
import '../../../l10n/app_localizations.dart';
import '../contact_sync_service.dart';

/// Explains what contact matching does before the OS prompt appears.
///
/// The explanation comes first deliberately: a permission dialog with no
/// preceding context is the most common reason someone declines a permission
/// they would otherwise have accepted — and in a product about privacy,
/// asking for the address book without saying what happens to it is the
/// wrong way round.
class ContactsPermissionScreen extends StatefulWidget {
  const ContactsPermissionScreen({super.key, required this.service});

  final ContactSyncService service;

  @override
  State<ContactsPermissionScreen> createState() =>
      _ContactsPermissionScreenState();
}

class _ContactsPermissionScreenState extends State<ContactsPermissionScreen> {
  bool _requesting = false;
  bool _denied = false;

  Future<void> _request() async {
    setState(() {
      _requesting = true;
      _denied = false;
    });

    final granted = await widget.service.requestPermission();
    if (!mounted) return;

    if (granted) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _requesting = false;
      // Declining is a legitimate answer, not an error state. The screen
      // stays, explains the alternative, and does not re-prompt.
      _denied = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);

    return Scaffold(
      backgroundColor: IronColors.backgroundPrimary,
      appBar: AppBar(title: Text(t.findContactsTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(IronSpacing.lg),
          children: [
            const SizedBox(height: IronSpacing.lg),
            Center(
              child: Container(
                width: 88,
                height: 88,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: IronColors.accentSubtle,
                  border: Border.all(color: IronColors.borderSubtle),
                ),
                child: const Icon(IronIcons.contacts,
                    size: IronIcons.sizeEmptyState,
                    color: IronColors.accentText),
              ),
            ),
            const SizedBox(height: IronSpacing.lg),
            Text(
              t.findContactsHeadline,
              textAlign: TextAlign.center,
              style:
                  IronTypography.displaySmall(color: IronColors.textPrimary),
            ),
            const SizedBox(height: IronSpacing.xs),
            Text(
              t.findContactsBody,
              textAlign: TextAlign.center,
              style:
                  IronTypography.bodyMedium(color: IronColors.textSecondary),
            ),
            const SizedBox(height: IronSpacing.xl),

            // The specifics, stated plainly. Vague reassurance about
            // "respecting your privacy" is what every app says; this says
            // what actually happens to the data.
            _Point(
              icon: IronIcons.lock,
              title: t.contactsPointHashedTitle,
              body: t.contactsPointHashedBody,
            ),
            _Point(
              icon: IronIcons.blocked,
              title: t.contactsPointNoNumbersTitle,
              body: t.contactsPointNoNumbersBody,
            ),
            _Point(
              icon: IronIcons.delete,
              title: t.contactsPointReversibleTitle,
              body: t.contactsPointReversibleBody,
            ),

            if (_denied) ...[
              const SizedBox(height: IronSpacing.md),
              Container(
                padding: const EdgeInsets.all(IronSpacing.md),
                decoration: BoxDecoration(
                  color: IronColors.surfacePrimary,
                  borderRadius: BorderRadius.circular(IronRadius.md),
                  border: Border.all(
                    color: IronColors.semanticWarning.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(IronIcons.info,
                        size: IronIcons.sizeCompact,
                        color: IronColors.semanticWarning),
                    const SizedBox(width: IronSpacing.sm),
                    Expanded(
                      child: Text(
                        t.contactsDeniedHint,
                        style: IronTypography.bodySmall(
                            color: IronColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: IronSpacing.xl),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(IronSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IronButton(
                label: t.allowContactAccess,
                loading: _requesting,
                onPressed: _requesting ? null : _request,
              ),
              const SizedBox(height: IronSpacing.xs),
              IronButton(
                label: t.notNow,
                variant: IronButtonVariant.ghost,
                onPressed: _requesting
                    ? null
                    : () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: IronSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: IronColors.surfacePrimary,
              border: Border.all(color: IronColors.borderSubtle),
            ),
            child: Icon(icon,
                size: IronIcons.sizeCompact, color: IronColors.accentText),
          ),
          const SizedBox(width: IronSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style:
                      IronTypography.bodyLarge(color: IronColors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: IronTypography.bodySmall(
                      color: IronColors.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
