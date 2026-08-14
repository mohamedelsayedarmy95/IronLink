import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ironlink/core/api_client.dart';
import 'package:ironlink/core/failure.dart';
import 'package:ironlink/core/theme.dart';
import 'package:ironlink/core/widgets/empty_state.dart';
import 'package:ironlink/core/widgets/iron_button.dart';
import 'package:ironlink/features/settings/ocr_settings_bloc.dart';
import 'package:ironlink/features/settings/ocr_settings_state.dart';
import 'package:ironlink/l10n/app_localizations.dart';
import '../../core/icons.dart';

/// Localized sentence for a classified failure. Shared entry point so every
/// surface phrases the same cause identically.
String failureMessage(L t, NetworkFailure f) => switch (f) {
      NetworkFailure.offline => t.failureOffline,
      NetworkFailure.timeout => t.failureTimeout,
      NetworkFailure.server => t.failureServer,
      NetworkFailure.unauthorized => t.failureUnauthorized,
      NetworkFailure.rejected => t.failureRejected,
      NetworkFailure.insecure => t.failureInsecure,
      NetworkFailure.unknown => t.failureUnknown,
    };

class OcrSettingsPage extends StatelessWidget {
  const OcrSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => OcrSettingsBloc(
        context.read<ApiClient>(),
        const FlutterSecureStorage(),
      )..add(const LoadKeywords()),
      child: const _OcrSettingsView(),
    );
  }
}

class _OcrSettingsView extends StatefulWidget {
  const _OcrSettingsView();

  @override
  State<_OcrSettingsView> createState() => _OcrSettingsViewState();
}

class _OcrSettingsViewState extends State<_OcrSettingsView> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Drives the add button's enabled state from the field's content.
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;

    // Duplicates are rejected on the device: a round-trip that can only fail
    // is slower and less clear than saying so immediately.
    final existing = context.read<OcrSettingsBloc>().state.keywords;
    if (existing.contains(value)) {
      HapticFeedback.heavyImpact();
      _showNotice(L.of(context).ocrKeywordExists, isWarning: true);
      return;
    }

    context.read<OcrSettingsBloc>().add(AddKeyword(value));
    _controller.clear();
    _focus.requestFocus();
  }

  void _showNotice(String message, {bool isWarning = false}) {
    final accent =
        isWarning ? IronColors.semanticWarning : IronColors.semanticError;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          backgroundColor: IronColors.surfaceSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(IronRadius.md),
            side: BorderSide(color: accent.withValues(alpha: 0.4)),
          ),
          content: Row(
            children: [
              Icon(
                isWarning ? IronIcons.info : IronIcons.error,
                size: 20,
                color: accent,
              ),
              const SizedBox(width: IronSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  style:
                      IronTypography.bodyMedium(color: IronColors.textPrimary),
                ),
              ),
            ],
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final canAdd = _controller.text.trim().isNotEmpty;

    // No Scaffold/AppBar: this view is embedded as a Home tab whose AppBar
    // already carries the settings title.
    return ColoredBox(
      color: IronColors.backgroundPrimary,
      child: BlocConsumer<OcrSettingsBloc, OcrSettingsState>(
        // Transient failures surface as a snackbar only while a list is
        // already on screen; with an empty list the full error state below
        // says the same thing without stacking two messages.
        listenWhen: (prev, curr) =>
            curr.errorKind != null &&
            curr.errorKind != OcrErrorKind.load &&
            (curr.errorKind != prev.errorKind || curr.failure != prev.failure),
        listener: (context, state) {
          HapticFeedback.heavyImpact();
          _showNotice(switch (state.errorKind!) {
            OcrErrorKind.add => t.ocrAddFailed,
            OcrErrorKind.remove => t.ocrRemoveFailed,
            OcrErrorKind.load => t.failureUnknown,
          });
        },
        builder: (context, state) {
          return Padding(
            padding: const EdgeInsets.all(IronSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t.ocrKeywordsTitle,
                  style: IronTypography.headlineLarge(
                      color: IronColors.textPrimary),
                ),
                const SizedBox(height: IronSpacing.xxs),
                Text(
                  t.ocrKeywordsDescription,
                  style: IronTypography.bodyMedium(
                      color: IronColors.textSecondary),
                ),
                const SizedBox(height: IronSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focus,
                        textInputAction: TextInputAction.done,
                        style: IronTypography.bodyLarge(
                            color: IronColors.textPrimary),
                        decoration: InputDecoration(
                          labelText: t.newKeywordLabel,
                          hintText: t.newKeywordHint,
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                    ),
                    const SizedBox(width: IronSpacing.sm),
                    // Sized to match the field's height so the row's baseline
                    // stays level instead of the button floating high.
                    SizedBox(
                      height: 56,
                      child: IronButton(
                        label: t.add,
                        icon: IronIcons.add,
                        expand: false,
                        onPressed: canAdd ? _submit : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: IronSpacing.md),
                Expanded(child: _buildBody(context, t, state)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, L t, OcrSettingsState state) {
    if (state.isLoading && state.keywords.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: IronColors.accentText),
      );
    }

    if (state.errorKind == OcrErrorKind.load && state.keywords.isEmpty) {
      return IronErrorState(
        title: t.ocrLoadFailedTitle,
        message: failureMessage(t, state.failure ?? NetworkFailure.unknown),
        retryLabel: t.retry,
        onRetry: () =>
            context.read<OcrSettingsBloc>().add(const LoadKeywords()),
      );
    }

    if (state.keywords.isEmpty) {
      return IronEmptyState(
        title: t.noKeywordsYet,
        message: t.ocrKeywordsEmptyHint,
        rings: 1,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: IronSpacing.lg),
      itemCount: state.keywords.length,
      separatorBuilder: (_, __) => const SizedBox(height: IronSpacing.xs),
      itemBuilder: (context, index) {
        final keyword = state.keywords[index];
        return Dismissible(
          key: Key(keyword),
          direction: DismissDirection.endToStart,
          onDismissed: (_) {
            HapticFeedback.selectionClick();
            context.read<OcrSettingsBloc>().add(RemoveKeyword(keyword));
          },
          background: Container(
            alignment: AlignmentDirectional.centerEnd,
            padding: const EdgeInsetsDirectional.only(end: IronSpacing.lg),
            decoration: BoxDecoration(
              color: IronColors.semanticError.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(IronRadius.md),
            ),
            child: const Icon(IronIcons.delete,
                color: IronColors.semanticError),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: IronColors.surfacePrimary,
              borderRadius: BorderRadius.circular(IronRadius.md),
              border: Border.all(color: IronColors.borderSubtle),
            ),
            child: ListTile(
              contentPadding: const EdgeInsetsDirectional.only(
                  start: IronSpacing.md, end: IronSpacing.xs),
              leading: const Icon(IronIcons.keyword,
                  color: IronColors.textSecondary, size: IronIcons.sizeInline),
              title: Text(
                keyword,
                style: IronTypography.bodyLarge(color: IronColors.textPrimary),
              ),
              trailing: IconButton(
                tooltip: t.delete,
                // Icon-only control: the tooltip alone is not announced
                // reliably, so the action is named for assistive tech too.
                icon: const Icon(IronIcons.close, color: IronColors.textSecondary),
                iconSize: 20,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  context.read<OcrSettingsBloc>().add(RemoveKeyword(keyword));
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
