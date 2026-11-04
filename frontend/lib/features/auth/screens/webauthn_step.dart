import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/iron_button.dart';
import '../../../l10n/app_localizations.dart';
import '../bloc/auth_bloc.dart';
import '../webauthn_service.dart';

class WebAuthnStep extends StatefulWidget {
  const WebAuthnStep({super.key});

  @override
  State<WebAuthnStep> createState() => _WebAuthnStepState();
}

class _WebAuthnStepState extends State<WebAuthnStep> {
  bool _isProcessing = false;
  bool _isRegistration = false;

  Future<void> _handleRegistration(
      Map<String, dynamic> options, String ceremonyId) async {
    setState(() => _isProcessing = true);
    try {
      final credential =
          await WebAuthnService.createCredential(options: options);
      if (!mounted) return;
      context.read<AuthBloc>().add(
            WebAuthnRegistrationCompleted(
                ceremonyId: ceremonyId, credential: credential),
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Registration failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleAuthentication(
      Map<String, dynamic> options, String ceremonyId) async {
    setState(() => _isProcessing = true);
    try {
      final credential = await WebAuthnService.getAssertion(options: options);
      if (!mounted) return;
      context.read<AuthBloc>().add(
            WebAuthnAuthenticationCompleted(
                ceremonyId: ceremonyId, credential: credential),
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Authentication failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);

    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (previous, current) =>
          previous.options != current.options ||
          previous.ceremonyId != current.ceremonyId,
      listener: (context, state) {
        if (state.options != null && state.ceremonyId != null) {
          if (_isRegistration) {
            _handleRegistration(state.options!, state.ceremonyId!);
          } else {
            _handleAuthentication(state.options!, state.ceremonyId!);
          }
        }
      },
      child: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t.webauthnStepTitle,
                style:
                    IronTypography.displayMedium(color: IronColors.textPrimary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: IronSpacing.xs),
              Text(
                t.webauthnStepSubtitle,
                style:
                    IronTypography.bodyMedium(color: IronColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: IronSpacing.xl),
              if (state.isWebAuthnLoading == true || _isProcessing)
                const Center(child: CircularProgressIndicator()),
              if (state.webAuthnError != null)
                Padding(
                  padding: const EdgeInsets.only(top: IronSpacing.sm),
                  child: Text(
                    state.webAuthnError!,
                    style: IronTypography.bodySmall(
                        color: IronColors.semanticError),
                    textAlign: TextAlign.center,
                  ),
                ),
              if (state.isWebAuthnLoading != true && !_isProcessing) ...[
                IronButton(
                  label: t.webauthnButtonRegister,
                  onPressed: () {
                    _isRegistration = true;
                    context
                        .read<AuthBloc>()
                        .add(const WebAuthnRegistrationRequested());
                  },
                ),
                const SizedBox(height: IronSpacing.md),
                IronButton(
                  label: t.webauthnButtonLogin,
                  variant: IronButtonVariant.ghost,
                  onPressed: () {
                    _isRegistration = false;
                    context
                        .read<AuthBloc>()
                        .add(const WebAuthnAuthenticationRequested());
                  },
                ),
              ],
              const SizedBox(height: IronSpacing.xl),
              IronButton(
                label: t.backButton,
                variant: IronButtonVariant.ghost,
                onPressed: () =>
                    context.read<AuthBloc>().add(const StepBackRequested()),
              ),
            ],
          );
        },
      ),
    );
  }
}
