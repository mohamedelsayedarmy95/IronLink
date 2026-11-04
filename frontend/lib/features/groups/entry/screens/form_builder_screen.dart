import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/failure.dart';
import '../../../../core/icons.dart';
import '../../../../core/theme.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/iron_button.dart';
import '../../../../l10n/app_localizations.dart';
import '../entry_repository.dart';
import '../models/verification_form.dart';
import '../widgets/dynamic_form_field.dart';

/// A field being composed, before the server assigns it an id.
class _DraftField {
  _DraftField({
    required this.type,
    this.label = '',
    this.placeholder,
    this.helperText,
    this.isRequired = true,
    List<FormFieldOption>? options,
    Map<String, dynamic>? rules,
  })  : options = options ?? [],
        rules = rules ?? {};

  final FormFieldType type;
  String label;
  String? placeholder;
  String? helperText;
  bool isRequired;
  List<FormFieldOption> options;
  Map<String, dynamic> rules;

  /// Local id, used only as a widget key while reordering.
  final String key = UniqueKey().toString();

  bool get needsOptions =>
      type == FormFieldType.selectSingle || type == FormFieldType.selectMulti;

  /// Whether this field could actually be answered. A select with no options
  /// is an unanswerable question; the server rejects it, and catching it here
  /// means the admin sees why before they try to save.
  String? validate(L t) {
    if (label.trim().isEmpty) return t.fieldNeedsLabel;
    if (needsOptions && options.isEmpty) return t.fieldNeedsOptions;
    return null;
  }

  Map<String, dynamic> toPayload() => {
        'field_type': type.wire,
        'label': label.trim(),
        if (placeholder?.trim().isNotEmpty ?? false)
          'placeholder': placeholder!.trim(),
        if (helperText?.trim().isNotEmpty ?? false)
          'helper_text': helperText!.trim(),
        'is_required': isRequired,
        if (rules.isNotEmpty) 'validation_rules': rules,
        if (needsOptions)
          'options': {
            'options': [
              for (final o in options) {'label': o.label, 'value': o.value},
            ],
          },
      };

  /// Preview shape, so the admin sees the real input rather than a mock of it.
  VerificationFormField toPreview() => VerificationFormField(
        id: key,
        type: type,
        label: label.trim().isEmpty ? '—' : label.trim(),
        isRequired: isRequired,
        placeholder: placeholder,
        helperText: helperText,
        validationRules: rules,
        options: options,
      );
}

/// Composes the verification form applicants must complete.
///
/// Editing an existing form creates a new one rather than mutating it:
/// pending requests reference the form they answered, and rewriting it under
/// them would change the questions after the fact.
class FormBuilderScreen extends StatefulWidget {
  const FormBuilderScreen({
    super.key,
    required this.repository,
    required this.groupId,
    this.existing,
  });

  final GroupEntryRepository repository;
  final String groupId;
  final VerificationForm? existing;

  @override
  State<FormBuilderScreen> createState() => _FormBuilderScreenState();
}

class _FormBuilderScreenState extends State<FormBuilderScreen> {
  final _fields = <_DraftField>[];
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );

  bool _saving = false;
  bool _preview = false;

  @override
  void initState() {
    super.initState();
    // Start from the existing form so an edit is a change, not a rewrite.
    for (final f in widget.existing?.fields ?? const <VerificationFormField>[]) {
      _fields.add(_DraftField(
        type: f.type,
        label: f.label,
        placeholder: f.placeholder,
        helperText: f.helperText,
        isRequired: f.isRequired,
        options: List.of(f.options),
        rules: Map.of(f.validationRules),
      ));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _addField() async {
    final type = await showModalBottomSheet<FormFieldType>(
      context: context,
      backgroundColor: IronColors.backgroundSecondary,
      isScrollControlled: true,
      builder: (_) => const _FieldTypePicker(),
    );
    if (type == null || !mounted) return;

    final draft = _DraftField(type: type);
    final saved = await _editField(draft, isNew: true);
    if (saved != true || !mounted) return;
    setState(() => _fields.add(draft));
  }

  Future<bool?> _editField(_DraftField draft, {bool isNew = false}) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: IronColors.backgroundSecondary,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _FieldEditor(draft: draft, isNew: isNew),
      ),
    );
  }

  Future<void> _save() async {
    final t = L.of(context);

    if (_name.text.trim().isEmpty) {
      _toast(t.formNeedsName);
      return;
    }
    if (_fields.isEmpty) {
      _toast(t.formNeedsFields);
      return;
    }
    for (var i = 0; i < _fields.length; i++) {
      final problem = _fields[i].validate(t);
      if (problem != null) {
        _toast('${t.fieldNumber(i + 1)}: $problem');
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final form = await widget.repository.createForm(
        widget.groupId,
        name: _name.text.trim(),
        fields: [for (final f in _fields) f.toPayload()],
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(form);
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() => _saving = false);
      _toast(failureMessage(t, NetworkFailureClassifier.from(e)));
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
        title: Text(t.formBuilderTitle),
        actions: [
          IconButton(
            tooltip: _preview ? t.editForm : t.previewForm,
            icon: Icon(
              _preview ? IronIcons.settings : IronIcons.show,
              size: IronIcons.sizeInline,
            ),
            onPressed: _fields.isEmpty
                ? null
                : () => setState(() => _preview = !_preview),
          ),
        ],
      ),
      body: _preview ? _previewBody(t) : _editorBody(t),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(IronSpacing.md),
          child: Row(
            children: [
              if (!_preview) ...[
                Expanded(
                  child: IronButton(
                    label: t.addField,
                    icon: IronIcons.add,
                    variant: IronButtonVariant.secondary,
                    onPressed: _saving ? null : _addField,
                  ),
                ),
                const SizedBox(width: IronSpacing.sm),
              ],
              Expanded(
                child: IronButton(
                  label: t.saveAndActivate,
                  loading: _saving,
                  onPressed: _fields.isEmpty ? null : _save,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _editorBody(L t) {
    if (_fields.isEmpty) {
      return IronEmptyState(
        title: t.formBuilderEmptyTitle,
        message: t.formBuilderEmptyHint,
        rings: 1,
        actionLabel: t.addField,
        onAction: _addField,
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(IronSpacing.md),
          child: TextField(
            controller: _name,
            style: IronTypography.bodyLarge(color: IronColors.textPrimary),
            decoration: InputDecoration(
              labelText: t.formNameLabel,
              hintText: t.formNameHint,
            ),
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: IronSpacing.md),
            itemCount: _fields.length,
            onReorder: (from, to) => setState(() {
              // ReorderableListView reports the target index before removal,
              // so it shifts by one when moving down.
              if (to > from) to -= 1;
              _fields.insert(to, _fields.removeAt(from));
            }),
            itemBuilder: (context, i) {
              final field = _fields[i];
              return Padding(
                key: ValueKey(field.key),
                padding: const EdgeInsets.only(bottom: IronSpacing.xs),
                child: _FieldRow(
                  index: i,
                  draft: field,
                  onEdit: () async {
                    final changed = await _editField(field);
                    if (changed == true && mounted) setState(() {});
                  },
                  onDelete: () => setState(() => _fields.removeAt(i)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Renders through the same widget applicants use, so what the admin
  /// approves is what gets shipped — not a separate mock that can drift.
  Widget _previewBody(L t) {
    return ListView(
      padding: const EdgeInsets.all(IronSpacing.md),
      children: [
        Text(
          _name.text.trim().isEmpty ? t.formBuilderTitle : _name.text.trim(),
          style: IronTypography.headlineLarge(color: IronColors.textPrimary),
        ),
        const SizedBox(height: IronSpacing.xxs),
        Text(
          t.previewNotice,
          style: IronTypography.bodySmall(color: IronColors.textTertiary),
        ),
        const SizedBox(height: IronSpacing.lg),
        for (final field in _fields)
          IgnorePointer(
            child: DynamicFormField(
              field: field.toPreview(),
              value: null,
              onChanged: (_) {},
            ),
          ),
      ],
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.index,
    required this.draft,
    required this.onEdit,
    required this.onDelete,
  });

  final int index;
  final _DraftField draft;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final problem = draft.validate(t);

    return Material(
      color: IronColors.surfacePrimary,
      borderRadius: BorderRadius.circular(IronRadius.md),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(IronRadius.md),
        child: Container(
          padding: const EdgeInsetsDirectional.only(
            start: IronSpacing.sm,
            end: IronSpacing.xs,
            top: IronSpacing.xs,
            bottom: IronSpacing.xs,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(IronRadius.md),
            border: Border.all(
              color: problem == null
                  ? IronColors.borderSubtle
                  : IronColors.semanticWarning.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.all(IronSpacing.xs),
                  child: Icon(IronIcons.tapHint,
                      size: IronIcons.sizeCompact,
                      color: IronColors.textTertiary),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            draft.label.trim().isEmpty
                                ? t.untitledField
                                : draft.label.trim(),
                            overflow: TextOverflow.ellipsis,
                            style: IronTypography.bodyLarge(
                                color: IronColors.textPrimary),
                          ),
                        ),
                        if (draft.isRequired)
                          Text(
                            ' *',
                            style: IronTypography.bodyLarge(
                                color: IronColors.semanticError),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      problem ?? _typeLabel(t, draft.type),
                      style: IronTypography.bodySmall(
                        color: problem == null
                            ? IronColors.textTertiary
                            : IronColors.semanticWarning,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: t.delete,
                icon: const Icon(IronIcons.delete,
                    size: IronIcons.sizeCompact),
                color: IronColors.textTertiary,
                constraints:
                    const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _typeLabel(L t, FormFieldType type) => switch (type) {
      FormFieldType.textShort => t.fieldTypeTextShort,
      FormFieldType.textLong => t.fieldTypeTextLong,
      FormFieldType.number => t.fieldTypeNumber,
      FormFieldType.selectSingle => t.fieldTypeSelectSingle,
      FormFieldType.selectMulti => t.fieldTypeSelectMulti,
      FormFieldType.date => t.fieldTypeDate,
      FormFieldType.phone => t.fieldTypePhone,
      FormFieldType.file => t.fieldTypeFile,
      FormFieldType.image => t.fieldTypeImage,
      FormFieldType.checkbox => t.fieldTypeCheckbox,
      FormFieldType.url => t.fieldTypeUrl,
      FormFieldType.email => t.fieldTypeEmail,
      FormFieldType.unsupported => t.fieldTypeUnsupported,
    };

IconData _typeIcon(FormFieldType type) => switch (type) {
      FormFieldType.textShort || FormFieldType.textLong => IronIcons.summary,
      FormFieldType.number => IronIcons.speed,
      FormFieldType.selectSingle ||
      FormFieldType.selectMulti =>
        IronIcons.keyword,
      FormFieldType.date => IronIcons.pending,
      FormFieldType.phone => IronIcons.device,
      FormFieldType.file => IronIcons.document,
      FormFieldType.image => IronIcons.camera,
      FormFieldType.checkbox => IronIcons.success,
      FormFieldType.url => IronIcons.forward,
      FormFieldType.email => IronIcons.send,
      FormFieldType.unsupported => IronIcons.info,
    };

/// The field library, per spec §2.2. A sheet rather than a side panel:
/// there is no room for two panels on a phone.
class _FieldTypePicker extends StatelessWidget {
  const _FieldTypePicker();

  static const _offered = [
    FormFieldType.textShort,
    FormFieldType.textLong,
    FormFieldType.number,
    FormFieldType.selectSingle,
    FormFieldType.selectMulti,
    FormFieldType.date,
    FormFieldType.phone,
    FormFieldType.email,
    FormFieldType.url,
    FormFieldType.checkbox,
    FormFieldType.file,
    FormFieldType.image,
  ];

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(IronSpacing.md),
            child: Text(
              t.chooseFieldType,
              style:
                  IronTypography.headlineLarge(color: IronColors.textPrimary),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final type in _offered)
                  ListTile(
                    leading: Icon(_typeIcon(type),
                        size: IronIcons.sizeInline,
                        color: IronColors.textSecondary),
                    title: Text(
                      _typeLabel(t, type),
                      style: IronTypography.bodyLarge(
                          color: IronColors.textPrimary),
                    ),
                    onTap: () => Navigator.pop(context, type),
                  ),
              ],
            ),
          ),
          const SizedBox(height: IronSpacing.sm),
        ],
      ),
    );
  }
}

/// Field properties, per spec §2.1.
class _FieldEditor extends StatefulWidget {
  const _FieldEditor({required this.draft, required this.isNew});

  final _DraftField draft;
  final bool isNew;

  @override
  State<_FieldEditor> createState() => _FieldEditorState();
}

class _FieldEditorState extends State<_FieldEditor> {
  late final _label = TextEditingController(text: widget.draft.label);
  late final _placeholder =
      TextEditingController(text: widget.draft.placeholder ?? '');
  late final _helper =
      TextEditingController(text: widget.draft.helperText ?? '');
  late final _option = TextEditingController();

  late bool _required = widget.draft.isRequired;
  late final List<FormFieldOption> _options = List.of(widget.draft.options);

  @override
  void dispose() {
    _label.dispose();
    _placeholder.dispose();
    _helper.dispose();
    _option.dispose();
    super.dispose();
  }

  void _addOption() {
    final text = _option.text.trim();
    if (text.isEmpty) return;
    // Value is derived from the label so the admin never has to think about
    // a separate machine key; duplicates are rejected because the server
    // requires option values to be unique.
    final value = text.toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    if (_options.any((o) => o.value == value)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(L.of(context).optionExists)));
      return;
    }
    setState(() {
      _options.add(FormFieldOption(label: text, value: value));
      _option.clear();
    });
  }

  void _apply() {
    widget.draft
      ..label = _label.text
      ..placeholder = _placeholder.text.trim().isEmpty
          ? null
          : _placeholder.text.trim()
      ..helperText =
          _helper.text.trim().isEmpty ? null : _helper.text.trim()
      ..isRequired = _required
      ..options = _options;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(IronSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _typeLabel(t, widget.draft.type),
              style:
                  IronTypography.headlineLarge(color: IronColors.textPrimary),
            ),
            const SizedBox(height: IronSpacing.md),

            TextField(
              controller: _label,
              autofocus: widget.isNew,
              style: IronTypography.bodyLarge(color: IronColors.textPrimary),
              decoration: InputDecoration(
                labelText: t.fieldLabelLabel,
                hintText: t.fieldLabelHint,
              ),
            ),
            const SizedBox(height: IronSpacing.sm),

            if (widget.draft.type != FormFieldType.checkbox) ...[
              TextField(
                controller: _placeholder,
                style: IronTypography.bodyLarge(color: IronColors.textPrimary),
                decoration:
                    InputDecoration(labelText: t.fieldPlaceholderLabel),
              ),
              const SizedBox(height: IronSpacing.sm),
            ],

            TextField(
              controller: _helper,
              style: IronTypography.bodyLarge(color: IronColors.textPrimary),
              decoration: InputDecoration(labelText: t.fieldHelperLabel),
            ),
            const SizedBox(height: IronSpacing.sm),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _required,
              onChanged: (v) => setState(() => _required = v),
              activeColor: IronColors.accentPrimary,
              title: Text(
                t.fieldRequiredLabel,
                style: IronTypography.bodyLarge(color: IronColors.textPrimary),
              ),
            ),

            if (widget.draft.needsOptions) ...[
              const Divider(color: IronColors.borderSubtle),
              const SizedBox(height: IronSpacing.xs),
              Text(
                t.fieldOptionsLabel,
                style: IronTypography.bodyMedium(
                    color: IronColors.textSecondary),
              ),
              const SizedBox(height: IronSpacing.xs),
              for (var i = 0; i < _options.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: IronSpacing.xxs),
                  child: Row(
                    children: [
                      const Icon(IronIcons.keyword,
                          size: IronIcons.sizeCompact,
                          color: IronColors.textTertiary),
                      const SizedBox(width: IronSpacing.xs),
                      Expanded(
                        child: Text(
                          _options[i].label,
                          style: IronTypography.bodyMedium(
                              color: IronColors.textPrimary),
                        ),
                      ),
                      IconButton(
                        tooltip: t.delete,
                        icon: const Icon(IronIcons.close,
                            size: IronIcons.sizeCompact),
                        color: IronColors.textTertiary,
                        constraints: const BoxConstraints(
                            minWidth: 48, minHeight: 48),
                        onPressed: () => setState(() => _options.removeAt(i)),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _option,
                      style: IronTypography.bodyLarge(
                          color: IronColors.textPrimary),
                      decoration:
                          InputDecoration(hintText: t.addOptionHint),
                      onSubmitted: (_) => _addOption(),
                    ),
                  ),
                  const SizedBox(width: IronSpacing.xs),
                  IconButton(
                    tooltip: t.add,
                    icon: const Icon(IronIcons.add),
                    color: IronColors.accentText,
                    constraints:
                        const BoxConstraints(minWidth: 48, minHeight: 48),
                    onPressed: _addOption,
                  ),
                ],
              ),
            ],

            const SizedBox(height: IronSpacing.md),
            IronButton(label: t.done, onPressed: _apply),
            const SizedBox(height: IronSpacing.sm),
          ],
        ),
      ),
    );
  }
}
