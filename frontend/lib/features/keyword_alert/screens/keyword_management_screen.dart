import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/keyword_rule.dart';
import '../local/alert_store.dart';
import '../matching/keyword_matcher.dart';
import '../ocr/extracted_document.dart';
import '../text/text_normalizer.dart';

/// Keyword management, per conversation (§5.7).
///
/// The screen this replaces offered a flat global list of bare strings, and
/// its two buttons were both destructive by accident: "add" replaced the whole
/// set server-side, and "remove one" cleared everything. Neither was visible,
/// because the endpoint behind them returned 500 either way.
///
/// The header says plainly who can see these rules, because that is the
/// question a user actually has before typing a name into a box on someone
/// else's software, and the honest answer — nobody, they never leave this
/// device — is the feature's strongest claim.
class KeywordManagementScreen extends StatefulWidget {
  const KeywordManagementScreen({
    super.key,
    required this.store,
    required this.conversationId,
    required this.ownerUserId,
  });

  final AlertStore store;
  final String conversationId;
  final String ownerUserId;

  @override
  State<KeywordManagementScreen> createState() =>
      _KeywordManagementScreenState();
}

class _KeywordManagementScreenState extends State<KeywordManagementScreen> {
  List<KeywordRule> _rules = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rules = await widget.store.rulesFor(widget.conversationId);
    if (!mounted) return;
    setState(() {
      _rules = rules;
      _loading = false;
    });
  }

  Future<void> _edit([KeywordRule? existing]) async {
    final saved = await showModalBottomSheet<KeywordRule>(
      context: context,
      isScrollControlled: true,
      backgroundColor: IronColors.surfacePrimary,
      builder: (_) => KeywordEditorSheet(
        existing: existing,
        conversationId: widget.conversationId,
        ownerUserId: widget.ownerUserId,
        existingRules: _rules,
      ),
    );
    if (saved == null) return;
    await widget.store.saveRule(saved);
    await _load();
  }

  Future<void> _delete(KeywordRule rule) async {
    final l = L.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: IronColors.surfacePrimary,
        content: Text(l.keywordDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // Cascades to the alerts this rule raised — an alert naming a keyword the
    // user believes they erased would be a lie sitting in history.
    await widget.store.deleteRule(rule.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    return Scaffold(
      backgroundColor: IronColors.backgroundPrimary,
      appBar: AppBar(
        title: Text(l.keywordManagementTitle),
        backgroundColor: IronColors.backgroundPrimary,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(),
        tooltip: l.keywordAddTitle,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                Padding(
                  padding: const EdgeInsets.all(IronSpacing.lg),
                  child: Text(
                    l.keywordManagementSubtitle,
                    style: IronTypography.bodySmall(
                      color: IronColors.textSecondary,
                    ),
                  ),
                ),
                if (_rules.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(IronSpacing.xl),
                    child: Text(
                      l.keywordEmpty,
                      textAlign: TextAlign.center,
                      style: IronTypography.bodyMedium(
                        color: IronColors.textTertiary,
                      ),
                    ),
                  )
                else
                  for (final rule in _rules)
                    _RuleTile(
                      rule: rule,
                      onEdit: () => _edit(rule),
                      onDelete: () => _delete(rule),
                      onToggle: (enabled) async {
                        await widget.store.saveRule(rule.copyWith(
                          enabled: enabled,
                          updatedAt: DateTime.now().toUtc(),
                        ));
                        await _load();
                      },
                    ),
              ],
            ),
    );
  }
}

class _RuleTile extends StatelessWidget {
  const _RuleTile({
    required this.rule,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  final KeywordRule rule;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: IronSpacing.lg,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: IronColors.surfacePrimary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: IronColors.borderSubtle),
      ),
      child: ListTile(
        // The user's own spelling, shown back unchanged — never the normalized
        // form, which is an implementation detail they never typed.
        title: Text(
          rule.displayRepresentation,
          style: IronTypography.bodyMedium(
            color: rule.enabled
                ? IronColors.textPrimary
                : IronColors.textDisabled,
          ),
        ),
        subtitle: Text(
          [
            _priorityLabel(l, rule.priority),
            _matchModeLabel(l, rule.matchMode),
            if (rule.category != null) rule.category!,
          ].join(' · '),
          style: IronTypography.labelSmall(color: IronColors.textTertiary),
        ),
        onTap: onEdit,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: rule.enabled,
              onChanged: onToggle,
            ),
            IconButton(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.delete_outline),
              color: IronColors.textSecondary,
              tooltip: l.delete,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

String _priorityLabel(L l, KeywordPriority p) => switch (p) {
      KeywordPriority.low => l.keywordPriorityLow,
      KeywordPriority.medium => l.keywordPriorityMedium,
      KeywordPriority.high => l.keywordPriorityHigh,
      KeywordPriority.critical => l.keywordPriorityCritical,
    };

String _matchModeLabel(L l, KeywordMatchMode m) => switch (m) {
      KeywordMatchMode.exact => l.keywordMatchExact,
      KeywordMatchMode.phrase => l.keywordMatchPhrase,
      KeywordMatchMode.fuzzy => l.keywordMatchFuzzy,
      KeywordMatchMode.regex => l.keywordMatchRegex,
    };

/// Create or edit one rule.
///
/// Validation runs as the user types rather than on save, so a rejected
/// keyword is explained where it was typed instead of after the sheet closes.
/// Every rejection has a reason the user can act on — §1.3 requires rules be
/// editable with immediate effect, and an unexplained refusal is a dead end.
class KeywordEditorSheet extends StatefulWidget {
  const KeywordEditorSheet({
    super.key,
    required this.conversationId,
    required this.ownerUserId,
    required this.existingRules,
    this.existing,
  });

  final String conversationId;
  final String ownerUserId;
  final List<KeywordRule> existingRules;
  final KeywordRule? existing;

  @override
  State<KeywordEditorSheet> createState() => _KeywordEditorSheetState();
}

class _KeywordEditorSheetState extends State<KeywordEditorSheet> {
  late final TextEditingController _keyword;
  late final TextEditingController _category;
  late final TextEditingController _notes;
  late final TextEditingController _pattern;
  late final TextEditingController _sample;

  late KeywordPriority _priority;
  late KeywordMatchMode _mode;
  late bool _caseSensitive;

  String? _error;
  bool? _sampleMatches;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _keyword = TextEditingController(text: e?.displayRepresentation ?? '');
    _category = TextEditingController(text: e?.category ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _pattern = TextEditingController(text: e?.regexPattern ?? '');
    _sample = TextEditingController();
    _priority = e?.priority ?? KeywordPriority.medium;
    _mode = e?.matchMode ?? KeywordMatchMode.exact;
    _caseSensitive = e?.caseSensitive ?? false;
  }

  @override
  void dispose() {
    _keyword.dispose();
    _category.dispose();
    _notes.dispose();
    _pattern.dispose();
    _sample.dispose();
    super.dispose();
  }

  KeywordRule? _build() {
    final normalizer = TextNormalizer(caseSensitive: _caseSensitive);
    return KeywordRule.create(
      ownerUserId: widget.ownerUserId,
      conversationScope: widget.conversationId,
      displayRepresentation: _keyword.text,
      normalize: normalizer.normalizeToString,
      now: widget.existing?.createdAt ?? DateTime.now().toUtc(),
      matchMode: _mode,
      priority: _priority,
      caseSensitive: _caseSensitive,
      regexPattern: _mode == KeywordMatchMode.regex ? _pattern.text : null,
      category: _category.text,
      notes: _notes.text,
      idOverride: widget.existing?.id,
    );
  }

  String _localizedError(L l, String code) => switch (code) {
        'keyword_too_short' => l.keywordErrorTooShort,
        'keyword_too_long' => l.keywordErrorTooLong,
        'keyword_not_matchable' => l.keywordErrorNotMatchable,
        'regex_invalid_pattern' || 'regex_required' => l.keywordErrorRegexInvalid,
        'regex_nested_quantifier' ||
        'regex_backreference' ||
        'regex_too_long' =>
          l.keywordErrorRegexUnsafe,
        _ => l.keywordErrorRegexInvalid,
      };

  void _validate() {
    final l = L.of(context);
    setState(() {
      _error = null;
      try {
        final rule = _build();
        if (rule == null) return;

        // A rule that is only a connector would fire on every document ever
        // sent. Caught here rather than silently never matching, which is what
        // the matcher would otherwise do and the user would never understand.
        if (rule.matchMode != KeywordMatchMode.regex &&
            isStopWord(rule.normalizedRepresentation)) {
          _error = l.keywordErrorStopWord;
          return;
        }

        final clash = widget.existingRules.any((r) =>
            r.id != rule.id &&
            r.normalizedRepresentation == rule.normalizedRepresentation &&
            r.matchMode == rule.matchMode);
        if (clash) _error = l.keywordErrorDuplicate;
      } on KeywordRuleError catch (e) {
        _error = _localizedError(l, e.code);
      }
    });
  }

  /// "Test this keyword" (§5.7) — the answer to "will this actually match?"
  /// given without waiting for a document to arrive.
  void _test() {
    final rule = () {
      try {
        return _build();
      } on KeywordRuleError {
        return null;
      }
    }();
    if (rule == null) {
      setState(() => _sampleMatches = null);
      return;
    }

    final text = _sample.text;
    final page = ExtractedPage(
      pageNumber: 1,
      text: text,
      source: PageTextSource.nativeTextLayer,
      words: [
        for (final m in RegExp(r'\S+').allMatches(text))
          RecognizedWord(start: m.start, end: m.end, confidence: 1.0),
      ],
    );

    // The real matcher, not an approximation of it. A test that used
    // different logic from the pipeline would be worse than none — it would
    // promise behaviour the feature does not have.
    final hits = const KeywordMatcher().match(
      rules: [rule],
      document: ExtractedDocument(pages: [page], engine: 'keyword-test'),
    );
    setState(() => _sampleMatches = hits.isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final insets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        IronSpacing.lg,
        IronSpacing.lg,
        IronSpacing.lg,
        IronSpacing.lg + insets,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.existing == null ? l.keywordAddTitle : l.keywordEditTitle,
              style: IronTypography.titleMedium(color: IronColors.textPrimary),
            ),
            const SizedBox(height: IronSpacing.md),
            TextField(
              controller: _keyword,
              autofocus: true,
              onChanged: (_) => _validate(),
              decoration: InputDecoration(
                labelText: l.keywordFieldLabel,
                hintText: l.keywordFieldHint,
                errorText: _error,
              ),
            ),
            const SizedBox(height: IronSpacing.md),
            _ModeSelector(
              value: _mode,
              onChanged: (mode) {
                setState(() => _mode = mode);
                _validate();
              },
            ),
            if (_mode == KeywordMatchMode.regex) ...[
              const SizedBox(height: IronSpacing.sm),
              TextField(
                controller: _pattern,
                onChanged: (_) => _validate(),
                decoration: const InputDecoration(
                  labelText: 'INV-\\d{6}',
                ),
              ),
            ],
            const SizedBox(height: IronSpacing.md),
            _PrioritySelector(
              value: _priority,
              onChanged: (p) => setState(() => _priority = p),
            ),
            const SizedBox(height: IronSpacing.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                l.keywordCaseSensitiveLabel,
                style: IronTypography.bodySmall(
                  color: IronColors.textSecondary,
                ),
              ),
              value: _caseSensitive,
              onChanged: (v) {
                setState(() => _caseSensitive = v);
                _validate();
              },
            ),
            TextField(
              controller: _category,
              decoration: InputDecoration(labelText: l.keywordCategoryLabel),
            ),
            const SizedBox(height: IronSpacing.sm),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: InputDecoration(labelText: l.keywordNotesLabel),
            ),
            const SizedBox(height: IronSpacing.lg),
            Text(
              l.keywordTestTitle,
              style: IronTypography.labelSmall(
                color: IronColors.textSecondary,
              ),
            ),
            const SizedBox(height: IronSpacing.xs),
            TextField(
              controller: _sample,
              onChanged: (_) => _test(),
              decoration: InputDecoration(
                hintText: l.keywordTestHint,
                suffixIcon: _sampleMatches == null
                    ? null
                    : Icon(
                        _sampleMatches!
                            ? Icons.check_circle_outline
                            : Icons.remove_circle_outline,
                        color: _sampleMatches!
                            ? IronColors.semanticSuccess
                            : IronColors.textTertiary,
                        // The icon repeats what the label says rather than
                        // replacing it: colour alone is not a signal.
                        semanticLabel: _sampleMatches!
                            ? l.keywordTestMatched
                            : l.keywordTestNoMatch,
                      ),
              ),
            ),
            const SizedBox(height: IronSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l.cancel),
                ),
                const SizedBox(width: IronSpacing.xs),
                FilledButton(
                  onPressed: _error != null || _keyword.text.trim().isEmpty
                      ? null
                      : () {
                          _validate();
                          if (_error != null) return;
                          try {
                            Navigator.pop(context, _build());
                          } on KeywordRuleError catch (e) {
                            setState(() =>
                                _error = _localizedError(L.of(context), e.code));
                          }
                        },
                  child: Text(l.done),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.value, required this.onChanged});

  final KeywordMatchMode value;
  final ValueChanged<KeywordMatchMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Wrap(
      spacing: 8,
      children: [
        for (final mode in KeywordMatchMode.values)
          // Fuzzy is EXPERIMENTAL and stays out of the picker until it earns
          // its way in (§9.4) — an option that silently does nothing is worse
          // than no option.
          if (mode != KeywordMatchMode.fuzzy)
            ChoiceChip(
              label: Text(_matchModeLabel(l, mode)),
              selected: value == mode,
              onSelected: (_) => onChanged(mode),
            ),
      ],
    );
  }
}

class _PrioritySelector extends StatelessWidget {
  const _PrioritySelector({required this.value, required this.onChanged});

  final KeywordPriority value;
  final ValueChanged<KeywordPriority> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Wrap(
      spacing: 8,
      children: [
        for (final priority in KeywordPriority.values)
          ChoiceChip(
            label: Text(_priorityLabel(l, priority)),
            selected: value == priority,
            onSelected: (_) => onChanged(priority),
          ),
      ],
    );
  }
}
