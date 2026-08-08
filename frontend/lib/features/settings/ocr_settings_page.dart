import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ironlink/core/api_client.dart';
import 'package:ironlink/core/theme.dart';
import 'package:ironlink/features/settings/ocr_settings_bloc.dart';
import 'package:ironlink/features/settings/ocr_settings_state.dart';

class OcrSettingsPage extends StatelessWidget {
  const OcrSettingsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => OcrSettingsBloc(
        context.read<ApiClient>(),
        const FlutterSecureStorage(),
      )..add(LoadKeywords()),
      child: const _OcrSettingsView(),
    );
  }
}

class _OcrSettingsView extends StatelessWidget {
  const _OcrSettingsView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OCR Keywords'),
        backgroundColor: IronColors.navyDeep,
        foregroundColor: IronColors.textHi,
      ),
      body: BlocBuilder<OcrSettingsBloc, OcrSettingsState>(
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(
              child: CircularProgressIndicator(
                color: IronColors.gold,
              ),
            );
          }

          if (state.errorMessage != null) {
            return Center(
              child: Text(
                state.errorMessage!,
                style: const TextStyle(color: IronColors.errorRed),
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Input field for adding new keyword
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          labelText: 'New Keyword',
                          hintText: 'Enter keyword to add',
                          filled: true,
                        ),
                        onSubmitted: (value) {
                          if (value.trim().isNotEmpty) {
                            context
                                .read<OcrSettingsBloc>()
                                .add(AddKeyword(value.trim()));
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        // The TextField's onSubmitted already handles it,
                        // but we can also handle button press if needed.
                      },
                      child: const Text('Add'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // List of keywords
                Expanded(
                  child: state.keywords.isEmpty
                      ? const Center(
                          child: Text(
                            'No keywords added yet.',
                            style: TextStyle(color: IronColors.textLo),
                          ),
                        )
                      : ListView.builder(
                          itemCount: state.keywords.length,
                          itemBuilder: (context, index) {
                            final keyword = state.keywords[index];
                            return Dismissible(
                              key: Key(keyword),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                color: IronColors.errorRed,
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                child: const Icon(
                                  Icons.delete,
                                  color: IronColors.textHi,
                                ),
                              ),
                              onDismissed: (_) {
                                context
                                    .read<OcrSettingsBloc>()
                                    .add(RemoveKeyword(keyword));
                              },
                              child: ListTile(
                                title: Text(keyword),
                                trailing: const Icon(Icons.delete_outline),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}