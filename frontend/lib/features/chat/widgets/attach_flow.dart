import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/media_service.dart';
import '../../../core/theme.dart';
import '../../../core/ws_service.dart';

/// Result handed back to the chat room after a successful upload.
class AttachmentReady {
  const AttachmentReady({
    required this.mediaKey,
    required this.mimeType,
    this.caption,
  });

  final String mediaKey;
  final String mimeType;
  final String? caption;
}

/// Gold attach sheet: gallery / camera / PDF / (voice lives on the input bar).
Future<AttachmentReady?> showAttachFlow(
  BuildContext context, {
  required MediaService media,
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
            content: Text(
                'Ключевое слово "$keyword" найдено в загруженном файле $fileId'),
            backgroundColor: MilColors.navySurface,
          ),
        );
      }
    }
  });

  try {
    final source = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: MilColors.navySurface,
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
                icon: Icons.photo_library_outlined,
                label: 'Контент галереи',
                onTap: () => Navigator.pop(sheetContext, 'gallery'),
              ),
              _AttachOption(
                icon: Icons.camera_alt_outlined,
                label: 'Камера',
                onTap: () => Navigator.pop(sheetContext, 'camera'),
              ),
              _AttachOption(
                icon: Icons.picture_as_pdf_outlined,
                label: 'Файл PDF',
                onTap: () => Navigator.pop(sheetContext, 'pdf'),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !context.mounted) return null;

    if (source == 'pdf') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: MilColors.navySurface,
        content: Text('Выбор PDF будет реализован в следующем обновлении',
            style: TextStyle(color: MilColors.textHi)),
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
              backgroundColor: MilColors.navyDeep,
              child: Icon(icon, color: MilColors.gold),
            ),
            const SizedBox(height: 8),
            Text(label,
                style:
                    const TextStyle(color: MilColors.textLo, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _ImagePreviewScreen extends StatefulWidget {
  const _ImagePreviewScreen({required this.file, required this.media});

  final File file;
  final MediaService media;

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
      final result = await widget.media.upload(
        widget.file,
        mimeType: 'image/jpeg',
        onProgress: (p) => setState(() => _progress = p),
      );
      if (!mounted) return;
      Navigator.of(context).pop(AttachmentReady(
        mediaKey: result.mediaKey,
        mimeType: result.mimeType,
        caption: _caption.text.trim().isEmpty ? null : _caption.text.trim(),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _progress = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Ошибка загрузки — будет повторена автоматически ($e)'),
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
          icon: const Icon(Icons.close, color: MilColors.textHi),
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
              color: MilColors.gold,
              backgroundColor: MilColors.navySurface,
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
                      decoration: const InputDecoration(
                          hintText: 'Введите подпись…'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: MilColors.gold,
                    child: _progress != null
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(
                                color: MilColors.navyDeep, strokeWidth: 2),
                          )
                        : IconButton(
                            icon: const Icon(Icons.send,
                                color: MilColors.navyDeep),
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