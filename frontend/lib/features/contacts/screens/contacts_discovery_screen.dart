import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/failure.dart';
import '../../../core/icons.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/iron_button.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/ocr_settings_page.dart' show failureMessage;
import '../contact_sync_service.dart';
import '../contacts_repository.dart';
import 'contacts_permission_screen.dart';

/// Contacts already on IronLink, and the controls governing that matching.
///
/// Privacy is on this screen rather than buried in settings: the place
/// someone realises what the feature knows is the place they should be able
/// to change or revoke it.
class ContactsDiscoveryScreen extends StatefulWidget {
  const ContactsDiscoveryScreen({
    super.key,
    required this.repository,
    required this.service,
    this.onOpenChat,
  });

  final ContactsRepository repository;
  final ContactSyncService service;

  /// Opens a conversation with a discovered contact. Null disables the
  /// action rather than showing a button that does nothing.
  final void Function(DiscoveredContact contact)? onOpenChat;

  @override
  State<ContactsDiscoveryScreen> createState() =>
      _ContactsDiscoveryScreenState();
}

class _ContactsDiscoveryScreenState extends State<ContactsDiscoveryScreen> {
  List<DiscoveredContact> _contacts = const [];
  ContactSyncState? _state;
  NetworkFailure? _failure;

  bool _loading = true;
  bool _syncing = false;
  bool _needsPermission = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final results = await Future.wait([
        widget.repository.matches(),
        widget.repository.state(),
        widget.service.hasPermission(),
      ]);
      if (!mounted) return;
      setState(() {
        _contacts = results[0] as List<DiscoveredContact>;
        _state = results[1] as ContactSyncState;
        _needsPermission = !(results[2] as bool);
        _loading = false;
      });

      // Clearing the badge is its own call, made only once the list is
      // actually on screen.
      if (_contacts.any((c) => c.isNew)) {
        await widget.repository.markSeen();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failure = NetworkFailureClassifier.from(e);
        _loading = false;
      });
    }
  }

  Future<void> _sync() async {
    if (_needsPermission) {
      final granted = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ContactsPermissionScreen(service: widget.service),
        ),
      );
      if (granted != true || !mounted) return;
      setState(() => _needsPermission = false);
    }

    setState(() => _syncing = true);
    try {
      final result = await widget.service.sync();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() => _syncing = false);

      if (result != null) {
        _toast(result.newMatches > 0
            ? L.of(context).syncFoundNew(result.newMatches)
            : L.of(context).syncNoNewContacts);
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() => _syncing = false);
      _toast(failureMessage(
          L.of(context), NetworkFailureClassifier.from(e)));
    }
  }

  Future<void> _setDiscoverability(Discoverability level) async {
    final previous = _state;
    setState(() => _state = ContactSyncState(
          syncEnabled: previous?.syncEnabled ?? true,
          contactCount: previous?.contactCount ?? 0,
          discoverability: level,
          syncedAt: previous?.syncedAt,
        ));
    try {
      await widget.repository.setDiscoverability(level);
    } catch (e) {
      if (!mounted) return;
      // Reverting matters more here than elsewhere: leaving the UI showing a
      // stricter setting than the server holds would tell someone they are
      // private when they are not.
      setState(() => _state = previous);
      _toast(failureMessage(
          L.of(context), NetworkFailureClassifier.from(e)));
    }
  }

  Future<void> _deleteAll() async {
    final t = L.of(context);
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(t.deleteContactDataTitle),
            content: Text(t.deleteContactDataConfirm),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(t.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(
                    foregroundColor: IronColors.semanticError),
                child: Text(t.deleteEverything),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    try {
      await widget.repository.deleteAll();
      // The device forgets the salt too, so it can no longer reproduce the
      // digests it previously computed.
      await widget.service.forgetSalt();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _toast(t.contactDataDeleted);
      await _load();
    } catch (e) {
      if (!mounted) return;
      _toast(failureMessage(
          L.of(context), NetworkFailureClassifier.from(e)));
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    return Scaffold(
      backgroundColor: IronColors.backgroundPrimary,
      appBar: AppBar(
        title: Text(t.contactsTitle),
        actions: [
          IconButton(
            tooltip: t.syncNow,
            icon: const Icon(IronIcons.refresh, size: IronIcons.sizeInline),
            onPressed: _syncing ? null : _sync,
          ),
        ],
      ),
      body: _body(t),
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
        title: t.contactsLoadFailedTitle,
        message: failureMessage(t, _failure!),
        retryLabel: t.retry,
        onRetry: _load,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: IronColors.accentText,
      backgroundColor: IronColors.surfacePrimary,
      child: ListView(
        padding: const EdgeInsets.all(IronSpacing.md),
        children: [
          if (_needsPermission) ...[
            _PermissionPrompt(onEnable: _sync, syncing: _syncing),
            const SizedBox(height: IronSpacing.lg),
          ],

          if (_contacts.isEmpty && !_needsPermission)
            IronEmptyState(
              title: t.noContactsFound,
              message: t.noContactsFoundHint,
              rings: 3,
              actionLabel: t.syncNow,
              onAction: _syncing ? null : _sync,
            )
          else ...[
            if (_contacts.isNotEmpty) ...[
              Text(
                t.onIronLink(_contacts.length),
                style: IronTypography.headlineMedium(
                    color: IronColors.textPrimary),
              ),
              const SizedBox(height: IronSpacing.xs),
              for (final contact in _contacts)
                _ContactRow(
                  contact: contact,
                  onOpenChat: widget.onOpenChat == null
                      ? null
                      : () => widget.onOpenChat!(contact),
                ),
            ],
          ],

          const SizedBox(height: IronSpacing.xl),
          _PrivacySection(
            state: _state,
            onChanged: _setDiscoverability,
            onDeleteAll: _deleteAll,
          ),
          const SizedBox(height: IronSpacing.xl),
        ],
      ),
    );
  }
}

class _PermissionPrompt extends StatelessWidget {
  const _PermissionPrompt({required this.onEnable, required this.syncing});

  final VoidCallback onEnable;
  final bool syncing;

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    return Container(
      padding: const EdgeInsets.all(IronSpacing.md),
      decoration: BoxDecoration(
        color: IronColors.surfacePrimary,
        borderRadius: BorderRadius.circular(IronRadius.md),
        border: Border.all(color: IronColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(IronIcons.contacts,
                  size: IronIcons.sizeInline, color: IronColors.accentText),
              const SizedBox(width: IronSpacing.sm),
              Expanded(
                child: Text(
                  t.contactSyncOff,
                  style:
                      IronTypography.bodyLarge(color: IronColors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: IronSpacing.xs),
          Text(
            t.contactSyncOffHint,
            style: IronTypography.bodySmall(color: IronColors.textTertiary),
          ),
          const SizedBox(height: IronSpacing.md),
          IronButton(
            label: t.enableContactSync,
            loading: syncing,
            onPressed: syncing ? null : onEnable,
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.contact, required this.onOpenChat});

  final DiscoveredContact contact;
  final VoidCallback? onOpenChat;

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: IronSpacing.xs),
      child: Material(
        color: IronColors.surfacePrimary,
        borderRadius: BorderRadius.circular(IronRadius.md),
        child: InkWell(
          onTap: onOpenChat,
          borderRadius: BorderRadius.circular(IronRadius.md),
          child: Container(
            padding: const EdgeInsets.all(IronSpacing.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(IronRadius.md),
              border: Border.all(color: IronColors.borderSubtle),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: IronColors.surfaceSecondary,
                  ),
                  child: Text(
                    contact.fullName.isEmpty
                        ? '?'
                        : contact.fullName.characters.first,
                    style: IronTypography.headlineMedium(
                        color: IronColors.accentText),
                  ),
                ),
                const SizedBox(width: IronSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              contact.fullName,
                              overflow: TextOverflow.ellipsis,
                              style: IronTypography.bodyLarge(
                                  color: IronColors.textPrimary),
                            ),
                          ),
                          if (contact.isNew) ...[
                            const SizedBox(width: IronSpacing.xs),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: IronColors.accentSubtle,
                                borderRadius:
                                    BorderRadius.circular(IronRadius.sm),
                              ),
                              child: Text(
                                t.badgeNew,
                                style: IronTypography.labelSmall(
                                    color: IronColors.accentText),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (contact.username != null)
                        Text(
                          '@${contact.username}',
                          style: IronTypography.bodySmall(
                              color: IronColors.textTertiary),
                        ),
                    ],
                  ),
                ),
                if (onOpenChat != null)
                  const Icon(IronIcons.chats,
                      size: IronIcons.sizeInline,
                      color: IronColors.accentText),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrivacySection extends StatelessWidget {
  const _PrivacySection({
    required this.state,
    required this.onChanged,
    required this.onDeleteAll,
  });

  final ContactSyncState? state;
  final ValueChanged<Discoverability> onChanged;
  final VoidCallback onDeleteAll;

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final current = state?.discoverability ?? Discoverability.contactsOfContacts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.contactPrivacyTitle,
          style: IronTypography.headlineMedium(color: IronColors.textPrimary),
        ),
        const SizedBox(height: IronSpacing.xs),
        Text(
          t.whoCanFindMe,
          style: IronTypography.bodyMedium(color: IronColors.textSecondary),
        ),
        const SizedBox(height: IronSpacing.xs),
        for (final level in Discoverability.values)
          RadioListTile<Discoverability>(
            value: level,
            groupValue: current,
            onChanged: (v) => v == null ? null : onChanged(v),
            activeColor: IronColors.accentPrimary,
            contentPadding: EdgeInsets.zero,
            title: Text(
              switch (level) {
                Discoverability.everyone => t.discoverEveryone,
                Discoverability.contactsOfContacts => t.discoverMutual,
                Discoverability.nobody => t.discoverNobody,
              },
              style: IronTypography.bodyLarge(color: IronColors.textPrimary),
            ),
            subtitle: Text(
              switch (level) {
                Discoverability.everyone => t.discoverEveryoneHint,
                Discoverability.contactsOfContacts => t.discoverMutualHint,
                Discoverability.nobody => t.discoverNobodyHint,
              },
              style:
                  IronTypography.bodySmall(color: IronColors.textTertiary),
            ),
          ),

        const SizedBox(height: IronSpacing.md),

        // States what is actually held, as a number the user can check,
        // rather than a reassurance they have to take on faith.
        if (state != null)
          Container(
            padding: const EdgeInsets.all(IronSpacing.md),
            decoration: BoxDecoration(
              color: IronColors.surfacePrimary,
              borderRadius: BorderRadius.circular(IronRadius.md),
              border: Border.all(color: IronColors.borderSubtle),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(IronIcons.lock,
                    size: IronIcons.sizeCompact,
                    color: IronColors.textTertiary),
                const SizedBox(width: IronSpacing.sm),
                Expanded(
                  child: Text(
                    t.storedHashesNotice(state!.contactCount),
                    style: IronTypography.bodySmall(
                        color: IronColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: IronSpacing.md),
        IronButton(
          label: t.deleteContactData,
          variant: IronButtonVariant.destructive,
          onPressed: onDeleteAll,
        ),
      ],
    );
  }
}
