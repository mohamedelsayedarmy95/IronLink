import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/icons.dart';
import '../../../../core/theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../models/verification_form.dart';

/// Renders one admin-defined field as a real input.
///
/// The admin controls the label, the type, and the rules; this decides how
/// each type is presented. A field type the client doesn't recognise renders
/// as a disabled notice rather than vanishing — silently dropping a required
/// question would let someone submit an incomplete form and be rejected for
/// it without ever seeing what was missing.
class DynamicFormField extends StatelessWidget {
  const DynamicFormField({
    super.key,
    required this.field,
    required this.value,
    required this.onChanged,
    this.errorText,
    this.enabled = true,
  });

  final VerificationFormField field;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;
  final String? errorText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: IronSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label(field: field),
          const SizedBox(height: IronSpacing.xs),
          _input(context, t),
          if (field.helperText != null && errorText == null) ...[
            const SizedBox(height: IronSpacing.xxs),
            Text(
              field.helperText!,
              style: IronTypography.bodySmall(color: IronColors.textTertiary),
            ),
          ],
          if (errorText != null) ...[
            const SizedBox(height: IronSpacing.xxs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(IronIcons.error,
                    size: IronIcons.sizeCompact,
                    color: IronColors.semanticError),
                const SizedBox(width: IronSpacing.xs),
                Expanded(
                  child: Text(
                    errorText!,
                    style: IronTypography.bodySmall(
                        color: IronColors.semanticError),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _input(BuildContext context, L t) {
    switch (field.type) {
      case FormFieldType.textLong:
        return _text(context, maxLines: 5, minLines: 3);
      case FormFieldType.number:
        return _text(
          context,
          keyboard: const TextInputType.numberWithOptions(decimal: true),
          formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))],
          ltr: true,
        );
      case FormFieldType.phone:
        return _text(context, keyboard: TextInputType.phone, ltr: true);
      case FormFieldType.email:
        return _text(context, keyboard: TextInputType.emailAddress, ltr: true);
      case FormFieldType.url:
        return _text(context, keyboard: TextInputType.url, ltr: true);
      case FormFieldType.selectSingle:
        return _selectSingle(context, t);
      case FormFieldType.selectMulti:
        return _selectMulti(context);
      case FormFieldType.date:
        return _date(context, t);
      case FormFieldType.checkbox:
        return _checkbox(context);
      case FormFieldType.file:
      case FormFieldType.image:
        return _upload(context, t);
      case FormFieldType.textShort:
        return _text(context);
      case FormFieldType.unsupported:
        return _unsupported(t);
    }
  }

  InputDecoration _decoration({Widget? suffix, Widget? prefix}) =>
      InputDecoration(
        hintText: field.placeholder,
        suffixIcon: suffix,
        prefixIcon: prefix,
        // The error is rendered beneath this widget so it can sit next to an
        // icon; letting the field draw its own would show it twice.
        errorText: errorText == null ? null : '',
        errorStyle: const TextStyle(height: 0, fontSize: 0),
      );

  Widget _text(
    BuildContext context, {
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
    int maxLines = 1,
    int? minLines,
    bool ltr = false,
  }) {
    return TextFormField(
      initialValue: value?.toString() ?? '',
      enabled: enabled,
      keyboardType: keyboard,
      inputFormatters: [
        ...?formatters,
        if (field.maxLength != null)
          LengthLimitingTextInputFormatter(field.maxLength),
      ],
      maxLines: maxLines,
      minLines: minLines,
      // Numbers, emails, phones and URLs stay left-to-right even in an
      // Arabic layout; they are not prose.
      textDirection: ltr ? TextDirection.ltr : null,
      style: IronTypography.bodyLarge(color: IronColors.textPrimary),
      decoration: _decoration(),
      onChanged: onChanged,
    );
  }

  Widget _selectSingle(BuildContext context, L t) {
    final current = value?.toString();
    // A stale value that is no longer offered would make the dropdown throw,
    // so it is treated as unselected.
    final valid = field.options.any((o) => o.value == current) ? current : null;

    return InputDecorator(
      decoration: _decoration(),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: valid,
          isExpanded: true,
          hint: Text(
            field.placeholder ?? t.selectAnOption,
            style: IronTypography.bodyLarge(color: IronColors.textTertiary),
          ),
          dropdownColor: IronColors.surfaceSecondary,
          borderRadius: BorderRadius.circular(IronRadius.md),
          iconEnabledColor: IronColors.textSecondary,
          style: IronTypography.bodyLarge(color: IronColors.textPrimary),
          items: [
            for (final option in field.options)
              DropdownMenuItem(value: option.value, child: Text(option.label)),
          ],
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }

  Widget _selectMulti(BuildContext context) {
    final selected = <String>{
      ...(value is List ? (value as List).map((v) => v.toString()) : const []),
    };
    return Wrap(
      spacing: IronSpacing.xs,
      runSpacing: IronSpacing.xs,
      children: [
        for (final option in field.options)
          FilterChip(
            label: Text(option.label),
            selected: selected.contains(option.value),
            onSelected: enabled
                ? (on) {
                    final next = {...selected};
                    on ? next.add(option.value) : next.remove(option.value);
                    onChanged(next.toList());
                  }
                : null,
            backgroundColor: IronColors.surfacePrimary,
            selectedColor: IronColors.accentSubtle,
            checkmarkColor: IronColors.accentText,
            side: BorderSide(
              color: selected.contains(option.value)
                  ? IronColors.accentText
                  : IronColors.borderInteractive,
            ),
            labelStyle: IronTypography.bodyMedium(
              color: selected.contains(option.value)
                  ? IronColors.textPrimary
                  : IronColors.textSecondary,
            ),
          ),
      ],
    );
  }

  Widget _date(BuildContext context, L t) {
    final parsed = value is String ? DateTime.tryParse(value as String) : null;
    return InkWell(
      onTap: enabled
          ? () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: parsed ?? now,
                firstDate: DateTime(now.year - 100),
                lastDate: DateTime(now.year + 50),
              );
              if (picked != null) {
                onChanged(picked.toIso8601String().split('T').first);
              }
            }
          : null,
      borderRadius: BorderRadius.circular(IronRadius.md),
      child: InputDecorator(
        decoration: _decoration(
          suffix: const Icon(IronIcons.pending,
              size: IronIcons.sizeInline, color: IronColors.textSecondary),
        ),
        child: Text(
          parsed == null
              ? (field.placeholder ?? t.selectADate)
              : value.toString(),
          style: IronTypography.bodyLarge(
            color: parsed == null
                ? IronColors.textTertiary
                : IronColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _checkbox(BuildContext context) {
    final checked = value == true;
    return InkWell(
      onTap: enabled ? () => onChanged(!checked) : null,
      borderRadius: BorderRadius.circular(IronRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: IronSpacing.xs),
        child: Row(
          children: [
            // 48px target: the checkbox glyph alone is well under the floor.
            SizedBox(
              width: 48,
              height: 48,
              child: Checkbox(
                value: checked,
                onChanged: enabled ? (v) => onChanged(v ?? false) : null,
                activeColor: IronColors.accentPrimary,
                side: const BorderSide(color: IronColors.borderInteractive),
              ),
            ),
            Expanded(
              child: Text(
                field.placeholder ?? field.label,
                style: IronTypography.bodyMedium(color: IronColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _upload(BuildContext context, L t) {
    final hasFile = value is String && (value as String).isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(IronSpacing.md),
      decoration: BoxDecoration(
        color: IronColors.surfacePrimary,
        borderRadius: BorderRadius.circular(IronRadius.md),
        border: Border.all(color: IronColors.borderInteractive),
      ),
      child: Row(
        children: [
          Icon(
            field.type == FormFieldType.image
                ? IronIcons.camera
                : IronIcons.document,
            size: IronIcons.sizeInline,
            color: IronColors.textSecondary,
          ),
          const SizedBox(width: IronSpacing.sm),
          Expanded(
            child: Text(
              hasFile ? (value as String).split('/').last : t.noFileSelected,
              overflow: TextOverflow.ellipsis,
              style: IronTypography.bodyMedium(
                color: hasFile
                    ? IronColors.textPrimary
                    : IronColors.textTertiary,
              ),
            ),
          ),
          TextButton(
            // Upload is wired to the media service in a follow-up; the
            // control is disabled rather than pretending to work.
            onPressed: null,
            child: Text(t.comingSoon),
          ),
        ],
      ),
    );
  }

  Widget _unsupported(L t) => Container(
        padding: const EdgeInsets.all(IronSpacing.md),
        decoration: BoxDecoration(
          color: IronColors.surfacePrimary,
          borderRadius: BorderRadius.circular(IronRadius.md),
          border: Border.all(
            color: IronColors.semanticWarning.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            const Icon(IronIcons.info,
                size: IronIcons.sizeInline,
                color: IronColors.semanticWarning),
            const SizedBox(width: IronSpacing.sm),
            Expanded(
              child: Text(
                t.fieldTypeUnsupported,
                style:
                    IronTypography.bodySmall(color: IronColors.textSecondary),
              ),
            ),
          ],
        ),
      );
}

class _Label extends StatelessWidget {
  const _Label({required this.field});

  final VerificationFormField field;

  @override
  Widget build(BuildContext context) {
    // Checkbox carries its label beside the control, so repeating it above
    // would show the same sentence twice.
    if (field.type == FormFieldType.checkbox) return const SizedBox.shrink();

    return RichText(
      text: TextSpan(
        style: IronTypography.bodyMedium(color: IronColors.textSecondary),
        children: [
          TextSpan(text: field.label),
          if (field.isRequired)
            TextSpan(
              text: ' *',
              style: IronTypography.bodyMedium(
                  color: IronColors.semanticError),
            ),
        ],
      ),
    );
  }
}
