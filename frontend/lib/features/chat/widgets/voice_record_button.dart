import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../core/media_service.dart';
import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/icons.dart';

/// WhatsApp-style hold-to-record, lift-to-send, drag-left-to-cancel —
/// restyled in gold with a pulsing ring while recording.
class VoiceRecordButton extends StatefulWidget {
  const VoiceRecordButton({
    super.key,
    required this.media,
    required this.onRecorded,
  });

  final MediaService media;
  final void Function(String mediaKey, String mimeType) onRecorded;

  @override
  State<VoiceRecordButton> createState() => _VoiceRecordButtonState();
}

class _VoiceRecordButtonState extends State<VoiceRecordButton>
    with SingleTickerProviderStateMixin {
  final _recorder = AudioRecorder();
  bool _recording = false;
  bool _cancelZone = false;
  double _dragDx = 0;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!await _recorder.hasPermission()) return;
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000),
      path: path,
    );
    setState(() {
      _recording = true;
      _cancelZone = false;
      _dragDx = 0;
    });
  }

  Future<void> _stop({required bool send}) async {
    final path = await _recorder.stop();
    setState(() => _recording = false);
    if (!send || path == null) {
      if (path != null) File(path).delete().ignore();
      return;
    }
    try {
      final result = await widget.media.upload(
        File(path),
        mimeType: 'audio/mpeg',
      );
      widget.onRecorded(result.mediaKey, result.mimeType);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L.of(context).voiceUploadFailed)),
        );
      }
    } finally {
      File(path).delete().ignore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    return GestureDetector(
      onLongPressStart: (_) => _start(),
      onLongPressMoveUpdate: (d) {
        // Drag toward the start side (RTL: to the right visually) to cancel
        _dragDx = d.offsetFromOrigin.dx;
        final cancel = _dragDx.abs() > 80;
        if (cancel != _cancelZone) setState(() => _cancelZone = cancel);
      },
      onLongPressEnd: (_) => _stop(send: !_cancelZone),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_recording) ...[
            Text(
              _cancelZone ? t.releaseToCancel : t.dragToCancel,
              style: TextStyle(
                fontSize: 12,
                color: _cancelZone ? IronColors.errorRed : IronColors.textLo,
              ),
            ),
            const SizedBox(width: 8),
          ],
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) => Container(
              padding: const EdgeInsets.all(4),
              decoration: _recording
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: (_cancelZone
                                ? IronColors.errorRed
                                : IronColors.gold)
                            .withValues(alpha: 0.3 + 0.5 * _pulse.value),
                        width: 3,
                      ),
                    )
                  : null,
              child: CircleAvatar(
                radius: _recording ? 26 : 20,
                backgroundColor: _recording
                    ? (_cancelZone ? IronColors.errorRed : IronColors.gold)
                    : Colors.transparent,
                child: Icon(
                  _recording ? IronIcons.mic : IronIcons.mic,
                  color: _recording
                      ? IronColors.navyDeep
                      : IronColors.gold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
