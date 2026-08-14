import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ironlink/core/api_client.dart';
import 'package:ironlink/core/theme.dart';
import 'package:ironlink/features/settings/ocr_settings_bloc.dart';
import 'package:ironlink/features/settings/ocr_settings_state.dart';
import 'package:ironlink/l10n/app_localizations.dart';

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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(BuildContext context) {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    context.read<OcrSettingsBloc>().add(AddKeyword(value));
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    // No own Scaffold/AppBar: this view only ever lives embedded as a Home
    // tab (see HomeScreen), whose AppBar already shows the settings title —
    // a second AppBar here would just stack redundantly under it.
    return ColoredBox(
      color: IronColors.navyDeep,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t.ocrKeywordsTitle,
              style: const TextStyle(
                  color: IronColors.gold, fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              t.ocrKeywordsDescription,
              style: const TextStyle(color: IronColors.textLo, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: IronColors.textHi),
                    decoration: InputDecoration(
                      labelText: t.newKeywordLabel,
                      hintText: t.newKeywordHint,
                    ),
                    onSubmitted: (_) => _submit(context),
                  ),
                ),
                const SizedBox(width: 10),
                Material(
                  color: IronColors.gold,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _submit(context),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                      child: Icon(Icons.add, color: IronColors.navyDeep),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: BlocConsumer<OcrSettingsBloc, OcrSettingsState>(
                listenWhen: (prev, curr) =>
                    curr.errorKind != null &&
                    (curr.errorKind != prev.errorKind ||
                        curr.errorDetail != prev.errorDetail) &&
                    curr.keywords.isNotEmpty,
                listener: (context, state) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(
                      backgroundColor: IronColors.navySurface,
                      content: Text(_errorText(t, state.errorKind!, state.errorDetail),
                          style: const TextStyle(color: IronColors.textHi)),
                    ));
                },
                builder: (context, state) {
                  if (state.isLoading && state.keywords.isEmpty) {
                    return const Center(
                      child: CircularProgressIndicator(color: IronColors.gold),
                    );
                  }

                  if (state.errorKind != null && state.keywords.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.wifi_off_outlined,
                              size: 48, color: IronColors.errorRed),
                          const SizedBox(height: 12),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              _errorText(t, state.errorKind!, state.errorDetail),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: IronColors.textLo),
                            ),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: () => context
                                .read<OcrSettingsBloc>()
                                .add(const LoadKeywords()),
                            icon: const Icon(Icons.refresh),
                            label: Text(t.retry),
                          ),
                        ],
                      ),
                    );
                  }

                  if (state.keywords.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.manage_search_outlined,
                              size: 56, color: IronColors.goldDim),
                          const SizedBox(height: 12),
                          Text(t.noKeywordsYet,
                              style: const TextStyle(color: IronColors.textLo)),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: state.keywords.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final keyword = state.keywords[index];
                      return Dismissible(
                        key: Key(keyword),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: AlignmentDirectional.centerEnd,
                          padding: const EdgeInsetsDirectional.only(end: 20),
                          decoration: BoxDecoration(
                            color: IronColors.errorRed.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.delete_outline,
                              color: IronColors.errorRed),
                        ),
                        onDismissed: (_) => context
                            .read<OcrSettingsBloc>()
                            .add(RemoveKeyword(keyword)),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          decoration: BoxDecoration(
                            color: IronColors.navySurface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: IronColors.navyBorder),
                          ),
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.label_outline,
                                color: IronColors.gold, size: 20),
                            title: Text(keyword,
                                style: const TextStyle(color: IronColors.textHi)),
                            trailing: IconButton(
                              tooltip: t.delete,
                              icon: const Icon(Icons.delete_outline,
                                  color: IronColors.textLo),
                              onPressed: () => context
                                  .read<OcrSettingsBloc>()
                                  .add(RemoveKeyword(keyword)),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _errorText(L t, OcrErrorKind kind, String? detail) {
    final error = detail ?? '';
    return switch (kind) {
      OcrErrorKind.load => t.ocrLoadFailed(error),
      OcrErrorKind.add => t.ocrAddFailed(error),
      OcrErrorKind.remove => t.ocrRemoveFailed(error),
    };
  }
}
