import 'package:flutter/material.dart';

import '../../../core/failure.dart';
import '../../../core/icons.dart';
import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../ai_consent_repository.dart';

/// Asks for — or withdraws — permission to send a conversation's text for AI
/// processing.
///
/// The sheet says what actually happens rather than "improve your
/// experience": the messages leave the device and reach a third party. That
/// is the one fact someone needs to decide, and burying it would make the
/// consent worthless.
Future<AiConsentState?> showAiConsentSheet(
  BuildContext context, {
  required AiConsentRepository repository,
  required AiConsentState current,
  String? peerId,
  String? groupId,
  required String conversationName,
}) {
  return showModalBottomSheet<AiConsentState>(
    context: context,
    isScrollControlled: true,
    backgroundColor: IronColors.navySurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _AiConsentSheet(
      repository: repository,
      current: current,
      peerId: peerId,
      groupId: groupId,
      conversationName: conversationName,
    ),
  );
}

class _AiConsentSheet extends StatefulWidget {
  const _AiConsentSheet({
    required this.repository,
    required this.current,
    required this.conversationName,
    this.peerId,
    this.groupId,
  });

  final AiConsentRepository repository;
  final AiConsentState current;
  final String conversationName;
  final String? peerId;
  final String? groupId;

  @override
  State<_AiConsentSheet> createState() => _AiConsentSheetState();
}

class _AiConsentSheetState extends State<_AiConsentSheet> {
  late AiConsentState _state = widget.current;
  bool _busy = false;
  String? _error;

  Future<void> _set(bool granted) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await widget.repository.set(
        granted: granted,
        peerId: widget.peerId,
        groupId: widget.groupId,
      );
      if (!mounted) return;
      setState(() {
        _state = updated;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = failureMessage(
            L.of(context), NetworkFailureClassifier.from(e));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
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
            Row(
              children: [
                const Icon(IronIcons.info, color: IronColors.accentText),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    t.aiConsentTitle,
                    style: const TextStyle(
                      color: IronColors.textHi,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // The plain statement of what happens. Everything else on this
            // sheet is secondary to it.
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: IronColors.navyDeep,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: IronColors.borderInteractive),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.aiConsentWhatHappens,
                    style: const TextStyle(
                        color: IronColors.textHi,
                        fontSize: 14,
                        height: 1.45),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    t.aiConsentEncryptionNote,
                    style: const TextStyle(
                        color: IronColors.textTertiary,
                        fontSize: 13,
                        height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            SwitchListTile(
              value: _state.granted,
              onChanged: _busy ? null : _set,
              contentPadding: EdgeInsets.zero,
              activeThumbColor: IronColors.accentPrimary,
              title: Text(
                t.aiConsentToggle,
                style: const TextStyle(color: IronColors.textHi),
              ),
              subtitle: Text(
                t.aiConsentToggleHint(widget.conversationName),
                style: const TextStyle(
                    color: IronColors.textTertiary, fontSize: 12),
              ),
            ),

            // Everyone's agreement is required, so this says who is missing
            // rather than leaving the feature mysteriously unavailable.
            if (_state.granted && !_state.everyoneAgreed) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(IronIcons.pending,
                      size: IronIcons.sizeCompact,
                      color: IronColors.textTertiary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _state.waitingOn.isEmpty
                          ? t.aiConsentWaitingGeneric
                          : t.aiConsentWaitingOn(
                              _state.waitingOn.join('، ')),
                      style: const TextStyle(
                          color: IronColors.textTertiary, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],

            if (_state.canUseAi) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(IronIcons.success,
                      size: IronIcons.sizeCompact,
                      color: IronColors.accentText),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t.aiConsentEveryoneAgreed,
                      style: const TextStyle(
                          color: IronColors.accentText, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 14),
            Text(
              t.aiConsentWithdrawNote,
              style: const TextStyle(
                  color: IronColors.textTertiary, fontSize: 12, height: 1.4),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(
                      color: IronColors.errorRed, fontSize: 13)),
            ],

            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context, _state),
                child: Text(t.done,
                    style: const TextStyle(color: IronColors.accentText)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
