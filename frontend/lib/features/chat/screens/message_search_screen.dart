import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/icons.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../l10n/app_localizations.dart';
import '../local/message_store.dart';

/// Searches messages this device has already decrypted.
///
/// Runs entirely on-device: the server holds ciphertext it cannot read, so
/// there is no server-side index to query and building one would defeat the
/// encryption. The consequence worth stating in the UI is that results only
/// cover conversations this device has actually opened.
class MessageSearchScreen extends StatefulWidget {
  const MessageSearchScreen({
    super.key,
    required this.store,
    this.onOpenConversation,
  });

  final MessageStore store;

  /// Jumps to the conversation a hit belongs to. The name comes from the
  /// cache and may be null for rows written before it was stored.
  final void Function(String peerId, String? peerName)? onOpenConversation;

  @override
  State<MessageSearchScreen> createState() => _MessageSearchScreenState();
}

class _MessageSearchScreenState extends State<MessageSearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  Timer? _debounce;
  List<MessageSearchHit> _hits = const [];
  String _query = '';
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    // Autofocus: this screen exists to be typed into, and making the user tap
    // the field first is a step with no purpose.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    // Local queries are fast, but running one per keystroke still rebuilds
    // the list mid-word for no benefit.
    _debounce = Timer(const Duration(milliseconds: 200), () => _run(value));
  }

  Future<void> _run(String value) async {
    final term = value.trim();
    if (term.isEmpty) {
      setState(() {
        _hits = const [];
        _query = '';
        _searching = false;
      });
      return;
    }

    setState(() => _searching = true);
    final hits = await widget.store.search(term);
    if (!mounted) return;
    setState(() {
      _hits = hits;
      _query = term;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);

    return Scaffold(
      backgroundColor: IronColors.backgroundPrimary,
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          focusNode: _focus,
          textInputAction: TextInputAction.search,
          style: IronTypography.bodyLarge(color: IronColors.textPrimary),
          decoration: InputDecoration(
            hintText: t.searchMessagesHint,
            // The field is the app bar; a box around it would draw a border
            // inside a bar that already has one.
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: _onChanged,
          onSubmitted: _run,
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              tooltip: t.cancel,
              icon: const Icon(IronIcons.close, size: IronIcons.sizeInline),
              onPressed: () {
                _controller.clear();
                _run('');
                _focus.requestFocus();
              },
            ),
        ],
      ),
      body: _body(t),
    );
  }

  Widget _body(L t) {
    if (_query.isEmpty) {
      return IronEmptyState(
        title: t.searchMessagesTitle,
        message: t.searchMessagesOnDeviceNotice,
        rings: 1,
      );
    }
    if (_searching && _hits.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: IronColors.accentText),
      );
    }
    if (_hits.isEmpty) {
      return IronEmptyState(
        title: t.searchNoResults,
        message: t.searchNoResultsHint,
        rings: 1,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(IronSpacing.md),
      itemCount: _hits.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: IronSpacing.xs),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: IronSpacing.xs),
            child: Text(
              t.searchResultCount(_hits.length),
              style: IronTypography.bodySmall(color: IronColors.textTertiary),
            ),
          );
        }
        final hit = _hits[i - 1];
        return _HitRow(
          hit: hit,
          query: _query,
          onTap: widget.onOpenConversation == null
              ? null
              : () => widget.onOpenConversation!(hit.peerId, hit.peerName),
        );
      },
    );
  }
}

class _HitRow extends StatelessWidget {
  const _HitRow({required this.hit, required this.query, required this.onTap});

  final MessageSearchHit hit;
  final String query;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: IronColors.surfacePrimary,
      borderRadius: BorderRadius.circular(IronRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(IronRadius.md),
        child: Container(
          padding: const EdgeInsets.all(IronSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(IronRadius.md),
            border: Border.all(color: IronColors.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    hit.message.isMine ? IronIcons.send : IronIcons.chats,
                    size: IronIcons.sizeCompact,
                    color: IronColors.textTertiary,
                  ),
                  const SizedBox(width: IronSpacing.xs),
                  // Which conversation the hit came from. Without it a
                  // result is just a floating sentence.
                  Expanded(
                    child: Text(
                      hit.peerName ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: IronTypography.labelSmall(
                          color: IronColors.textSecondary),
                    ),
                  ),
                  const SizedBox(width: IronSpacing.xs),
                  Text(
                    _timestamp(hit.message.createdAt),
                    style: IronTypography.labelSmall(
                        color: IronColors.textTertiary),
                  ),
                ],
              ),
              const SizedBox(height: IronSpacing.xxs),
              _Highlighted(text: hit.message.content ?? '', query: query),
            ],
          ),
        ),
      ),
    );
  }

  static String _timestamp(DateTime at) {
    final local = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

/// Marks the matched span so the reason a result appeared is visible at a
/// glance, rather than leaving the user to scan for it.
class _Highlighted extends StatelessWidget {
  const _Highlighted({required this.text, required this.query});

  final String text;
  final String query;

  @override
  Widget build(BuildContext context) {
    final base = IronTypography.bodyMedium(color: IronColors.textPrimary);
    final lower = text.toLowerCase();
    final needle = query.toLowerCase();
    final at = lower.indexOf(needle);

    if (at < 0 || needle.isEmpty) {
      return Text(text, maxLines: 3, overflow: TextOverflow.ellipsis,
          style: base);
    }

    return RichText(
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: base,
        children: [
          TextSpan(text: text.substring(0, at)),
          TextSpan(
            text: text.substring(at, at + needle.length),
            style: base.copyWith(
              color: IronColors.accentText,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: text.substring(at + needle.length)),
        ],
      ),
    );
  }
}
