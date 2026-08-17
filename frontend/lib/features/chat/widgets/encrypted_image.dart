import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/crypto/attachment_crypto.dart';
import '../../../core/icons.dart';
import '../../../core/media_service.dart';
import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../keyword_alert/keyword_alert_service.dart';

/// Displays an attachment whose stored bytes are encrypted.
///
/// The usual `Image.network` path cannot work here: the object in storage is
/// ciphertext, so the bytes have to be fetched and decrypted on the device
/// before anything can be decoded.
///
/// This is also the only moment a keyword rule can see the document. The
/// server holds no key, so plaintext exists exactly once — here, in memory,
/// for as long as the image is on screen. [scan] hands those bytes to the
/// Smart Keyword Alert queue, which decides whether checking them is worth
/// doing; this widget does not decide, and does not wait.
class EncryptedImage extends StatefulWidget {
  const EncryptedImage({
    super.key,
    required this.media,
    required this.mediaKey,
    required this.attachmentKey,
    this.scan,
  });

  final MediaService media;
  final String mediaKey;
  final AttachmentKey attachmentKey;

  /// Null where keyword alerts are not configured — a platform without a
  /// local store, or a screen that has no conversation to attribute an alert
  /// to. The image renders identically either way.
  final KeywordScanContext? scan;

  @override
  State<EncryptedImage> createState() => _EncryptedImageState();
}

class _EncryptedImageState extends State<EncryptedImage> {
  Uint8List? _bytes;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.media
          .downloadDecrypted(widget.mediaKey, widget.attachmentKey);
      if (!mounted) return;
      setState(() => _bytes = bytes);

      // After the image is on screen, not before. Checking a document is
      // never allowed to delay showing it — the user asked to see a picture,
      // not to wait for a background feature — and a document that fails to
      // decrypt is never offered at all, because there is nothing to read.
      widget.scan?.offer(bytes);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);

    if (_error != null) {
      // Tampering is called out separately from a failed download. One means
      // try again; the other means the bytes are not what the sender sent,
      // and showing them anyway would defeat the authentication entirely.
      final tampered = _error is AttachmentTampered;
      return _Placeholder(
        icon: tampered ? IronIcons.error : IronIcons.offline,
        label: tampered ? t.attachmentTampered : t.attachmentLoadFailed,
        onRetry: tampered
            ? null
            : () {
                setState(() => _error = null);
                _load();
              },
        retryLabel: t.retry,
      );
    }

    final bytes = _bytes;
    if (bytes == null) {
      return const _Placeholder(
        icon: IronIcons.lock,
        label: null,
        busy: true,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.memory(
        bytes,
        fit: BoxFit.cover,
        // Reached when the decrypted bytes are not a decodable image, which
        // means the sender sent something other than what they claimed.
        errorBuilder: (_, __, ___) => _Placeholder(
          icon: IronIcons.error,
          label: t.attachmentLoadFailed,
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.icon,
    required this.label,
    this.busy = false,
    this.onRetry,
    this.retryLabel,
  });

  final IconData icon;
  final String? label;
  final bool busy;
  final VoidCallback? onRetry;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      height: 150,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: IronColors.navyDeep,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: IronColors.borderSubtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: IronColors.accentText),
            )
          else
            Icon(icon, color: IronColors.textTertiary),
          if (label != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                label!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: IronColors.textTertiary, fontSize: 12),
              ),
            ),
          ],
          if (onRetry != null && retryLabel != null)
            TextButton(
              onPressed: onRetry,
              child: Text(retryLabel!,
                  style: const TextStyle(color: IronColors.accentText)),
            ),
        ],
      ),
    );
  }
}
