import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/crypto/attachment_crypto.dart';
import '../../../core/media_service.dart';
import '../../../core/theme.dart';
import '../../../core/ws_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/icons.dart';

/// Result handed back to the chat room after a successful upload.
class AttachmentReady {
  const AttachmentReady({
    required this.mediaKey,
    required this.mimeType,
    this.caption,
    this.key,
  });

  final String mediaKey;
  final String mimeType;
  final String? caption;

  /// Set when the body was encrypted before upload. The chat bloc puts this
  /// inside the Signal envelope; without it the stored object is unreadable
  /// to everyone, including the recipient.
  final AttachmentKey? key;
}

/// Gold attach sheet: gallery / camera / PDF / (voice lives on the input bar).
Future<AttachmentReady?> showAttachFlow(
  BuildContext context, {
  required MediaService media,
  required bool isSecret,
}) async {
  // Obtain WsService from providers to listen for OCR alerts
  final ws = context.read<WsService>();
  StreamSubscription? ocrSub;

  ocrSub = ws.frames.listen((frame) {
    if (frame['type'] == 'ocr_alert') {
      final fileId = frame['file_id'] as String?;
      final keyword = frame['keyword'] as String?;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L.of(context).ocrAlertFound(keyword ?? '')),
            backgroundColor: IronColors.navySurface,
          ),
        );
      }
    }
  });

  try {
    final source = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: IronColors.navySurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _AttachOption(
                icon: IronIcons.gallery,
                label: L.of(context).attachGallery,
                onTap: () => Navigator.pop(sheetContext, 'gallery'),
              ),
              _AttachOption(
                icon: IronIcons.camera,
                label: L.of(context).attachCamera,
                onTap: () => Navigator.pop(sheetContext, 'camera'),
              ),
              _AttachOption(
                icon: IronIcons.document,
                label: L.of(context).attachDocument,
                onTap: () => Navigator.pop(sheetContext, 'pdf'),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !context.mounted) return null;

    if (source == 'pdf') {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(L.of(context).attachPdfComingSoon),
      ));
      return null;
    }

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 92,
    );
    if (picked == null || !context.mounted) return null;

    // Preview + caption before sending, as specified
    return Navigator.of(context).push<AttachmentReady>(
      MaterialPageRoute(
        builder: (_) => _ImagePreviewScreen(
          file: File(picked.path),
          media: media,
          isSecret: isSecret,
        ),
      ),
    );
  } finally {
    ocrSub?.cancel();
  }
}

class _AttachOption extends StatelessWidget {
  const _AttachOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: IronColors.navyDeep,
              child: Icon(icon, color: IronColors.gold),
            ),
            const SizedBox(height: 8),
            Text(label,
                style:
                    const TextStyle(color: IronColors.textLo, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _ImagePreviewScreen extends StatefulWidget {
  const _ImagePreviewScreen({
    required this.file,
    required this.media,
    required this.isSecret,
  });

  final File file;
  final MediaService media;
  final bool isSecret;

  @override
  State<_ImagePreviewScreen> createState() => _ImagePreviewScreenState();
}

class _ImagePreviewScreenState extends State<_ImagePreviewScreen> {
  final _caption = TextEditingController();
  double? _progress;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _progress = 0);
    try {
      final caption =
          _caption.text.trim().isEmpty ? null : _caption.text.trim();

      if (widget.isSecret) {
        // Encrypted before it leaves the device, so what reaches storage is
        // opaque. The server is told so explicitly — otherwise it would
        // re-compress the "image" and destroy it.
        final encrypted = await widget.media.uploadEncrypted(
          widget.file,
          mimeType: 'image/jpeg',
          onProgress: (p) => setState(() => _progress = p),
        );
        if (!mounted) return;
        Navigator.of(context).pop(AttachmentReady(
          mediaKey: encrypted.upload.mediaKey,
          mimeType: 'image/jpeg',
          caption: caption,
          key: encrypted.key,
        ));
        return;
      }

      final result = await widget.media.upload(
        widget.file,
        mimeType: 'image/jpeg',
        onProgress: (p) => setState(() => _progress = p),
      );
      if (!mounted) return;
      Navigator.of(context).pop(AttachmentReady(
        mediaKey: result.mediaKey,
        mimeType: result.mimeType,
        caption: caption,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _progress = null);
      debugPrint('[attach] upload failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(L.of(context).uploadFailed),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(IronIcons.close, color: IronColors.textHi),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              child: Center(child: Image.file(widget.file)),
            ),
          ),
          if (_progress != null)
            LinearProgressIndicator(
              value: _progress,
              color: IronColors.gold,
              backgroundColor: IronColors.navySurface,
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _caption,
                      enabled: _progress == null,
                      decoration: InputDecoration(
                          hintText: L.of(context).captionHint),
                    ),
                  ),
                  const SizedBox(width: 10),
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: IronColors.gold,
                    child: _progress != null
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(
                                color: IronColors.navyDeep, strokeWidth: 2),
                          )
                        : IconButton(
                            icon: const Icon(IronIcons.send,
                                color: IronColors.navyDeep),
                            onPressed: _send,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}