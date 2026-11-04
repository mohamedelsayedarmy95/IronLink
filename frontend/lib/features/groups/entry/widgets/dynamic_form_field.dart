import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/media/metadata_scrubber.dart';
import '../../../../core/icons.dart';
import '../../../../core/media_service.dart';
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
    this.media,
  });

  final VerificationFormField field;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;
  final String? errorText;
  final bool enabled;

  /// Required for file and image fields. Null in the admin's preview, where
  /// the control is shown but must not actually upload anything.
  final MediaService? media;

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
        return _UploadField(
          field: field,
          value: value is String ? value as String : null,
          enabled: enabled && media != null,
          media: media,
          onChanged: onChanged,
          decoration: _decoration(),
        );
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

/// File and image answers.
///
/// The stored answer is the media key the server returns, not the local path:
/// the validator checks that key, and a device path would mean nothing to an
/// admin reviewing the request from somewhere else.
class _UploadField extends StatefulWidget {
  const _UploadField({
    required this.field,
    required this.value,
    required this.enabled,
    required this.media,
    required this.onChanged,
    required this.decoration,
  });

  final VerificationFormField field;
  final String? value;
  final bool enabled;
  final MediaService? media;
  final ValueChanged<dynamic> onChanged;
  final InputDecoration decoration;

  @override
  State<_UploadField> createState() => _UploadFieldState();
}

class _UploadFieldState extends State<_UploadField> {
  double? _progress;
  String? _error;

  bool get _uploading => _progress != null;

  Future<void> _pick() async {
    final media = widget.media;
    if (media == null) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      // Documents still come from the gallery for now: a dedicated document
      // picker is a separate dependency, and offering a camera for a PDF
      // would be worse than offering a slightly wide gallery.
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (picked == null || !mounted) return;

    setState(() {
      _progress = 0;
      _error = null;
    });

    try {
      final result = await media.upload(
        File(picked.path),
        mimeType: widget.field.type == FormFieldType.image
            ? 'image/jpeg'
            : 'application/octet-stream',
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      HapticFeedback.selectionClick();
      setState(() => _progress = null);
      widget.onChanged(result.mediaKey);
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      debugPrint('[form-upload] failed: $e');
      setState(() {
        _progress = null;
        // Named separately from the field's validation error: this is about
        // the transfer, not about the answer being wrong. And a format the
        // metadata scrubber cannot strip is refused before any transfer
        // happens, which is a different sentence again.
        _error = e is UnscrubbableMedia
            ? L.of(context).attachUnsupportedFormat
            : L.of(context).uploadFailed;
      });
    }
  }

  void _clear() {
    widget.onChanged(null);
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final hasFile = widget.value != null && widget.value!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(IronSpacing.md),
          decoration: BoxDecoration(
            color: IronColors.surfacePrimary,
            borderRadius: BorderRadius.circular(IronRadius.md),
            border: Border.all(color: IronColors.borderInteractive),
          ),
          child: Row(
            children: [
              Icon(
                widget.field.type == FormFieldType.image
                    ? IronIcons.camera
                    : IronIcons.document,
                size: IronIcons.sizeInline,
                color: hasFile
                    ? IronColors.semanticSuccess
                    : IronColors.textSecondary,
              ),
              const SizedBox(width: IronSpacing.sm),
              Expanded(
                child: Text(
                  _uploading
                      ? t.uploading
                      : hasFile
                          ? t.fileAttached
                          : t.noFileSelected,
                  overflow: TextOverflow.ellipsis,
                  style: IronTypography.bodyMedium(
                    color: hasFile
                        ? IronColors.textPrimary
                        : IronColors.textTertiary,
                  ),
                ),
              ),
              if (hasFile && !_uploading)
                IconButton(
                  tooltip: t.delete,
                  icon: const Icon(IronIcons.close,
                      size: IronIcons.sizeCompact),
                  color: IronColors.textSecondary,
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: widget.enabled ? _clear : null,
                )
              else
                TextButton(
                  onPressed:
                      widget.enabled && !_uploading ? _pick : null,
                  child: Text(hasFile ? t.replace : t.choose),
                ),
            ],
          ),
        ),
        if (_uploading) ...[
          const SizedBox(height: IronSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 3,
              backgroundColor: IronColors.surfaceSecondary,
              valueColor:
                  const AlwaysStoppedAnimation(IronColors.accentText),
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: IronSpacing.xxs),
          Text(
            _error!,
            style: IronTypography.bodySmall(color: IronColors.semanticError),
          ),
        ],
      ],
    );
  }
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
