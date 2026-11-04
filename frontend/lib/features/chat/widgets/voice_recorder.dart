import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../core/crypto/attachment_crypto.dart';
import '../../../core/icons.dart';
import '../../../core/media_service.dart';
import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';
import 'waveform.dart';

/// A recorded voice note, once it is actually stored.
class VoiceNote {
  const VoiceNote({
    required this.mediaKey,
    required this.duration,
    required this.waveform,
    this.attachmentKey,
  });

  final String mediaKey;
  final double duration;
  final List<double> waveform;

  /// Set when the audio was encrypted before upload.
  final AttachmentKey? attachmentKey;
}

/// Hold to record, release to send.
///
/// The previous version never uploaded anything: it invented a media key from
/// a timestamp and a waveform from `List.generate`, then deleted the audio.
/// Every voice note it produced pointed at an object that did not exist.
class VoiceRecorder extends StatefulWidget {
  const VoiceRecorder({
    super.key,
    required this.media,
    required this.encrypted,
    required this.onSend,
    required this.onCancel,
  });

  final MediaService media;

  /// Encrypts the audio before upload. A voice note discloses at least as
  /// much as the message it replaces, so it follows the chat's setting.
  final bool encrypted;

  final void Function(VoiceNote note) onSend;
  final VoidCallback onCancel;

  @override
  State<VoiceRecorder> createState() => _VoiceRecorderState();
}

class _VoiceRecorderState extends State<VoiceRecorder> {
  final _recorder = AudioRecorder();

  bool _recording = false;
  bool _uploading = false;
  double _seconds = 0;
  String? _path;

  Timer? _ticker;
  StreamSubscription<Amplitude>? _amplitudes;

  /// dBFS readings taken while recording, turned into bars on stop. Real
  /// measurements — the bars have to correspond to the audio, or they are
  /// decoration pretending to be information.
  final _readings = <double>[];

  /// Live preview, resampled from whatever has been captured so far.
  List<double> _preview = const [];

  static const _minSeconds = 1.0;
  static const _maxSeconds = 300.0; // 5 minutes

  @override
  void dispose() {
    _ticker?.cancel();
    _amplitudes?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_recording || _uploading) return;
    try {
      if (!await _recorder.hasPermission()) return;

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 32000,
          sampleRate: 22050,
          numChannels: 1, // speech; stereo doubles the size for nothing
        ),
        path: path,
      );

      _readings.clear();
      _amplitudes = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((a) {
        _readings.add(a.current);
        if (mounted) {
          setState(() => _preview = Waveform.fromDecibels(_readings));
        }
      });

      setState(() {
        _path = path;
        _recording = true;
        _seconds = 0;
        _preview = const [];
      });

      _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!mounted) return;
        setState(() => _seconds += 0.1);
        // A recording left running by a stuck gesture would otherwise grow
        // until the upload is rejected for size.
        if (_seconds >= _maxSeconds) _stop(send: true);
      });
    } catch (e) {
      debugPrint('[voice] start failed: $e');
      if (mounted) setState(() => _recording = false);
    }
  }

  Future<void> _stop({required bool send}) async {
    if (!_recording) return;

    _ticker?.cancel();
    await _amplitudes?.cancel();
    _amplitudes = null;

    final path = await _recorder.stop();
    final duration = _seconds;
    if (mounted) setState(() => _recording = false);

    final file = File(path ?? _path ?? '');
    if (!send || path == null || duration < _minSeconds) {
      // Too short to be intentional — usually a mis-tap on the mic.
      if (await file.exists()) await file.delete();
      widget.onCancel();
      return;
    }

    if (mounted) setState(() => _uploading = true);
    try {
      final waveform = Waveform.fromDecibels(_readings);

      if (widget.encrypted) {
        final result = await widget.media.uploadEncrypted(
          file,
          mimeType: 'audio/mp4',
        );
        widget.onSend(VoiceNote(
          mediaKey: result.upload.mediaKey,
          duration: duration,
          waveform: waveform,
          attachmentKey: result.key,
        ));
      } else {
        final result = await widget.media.upload(file, mimeType: 'audio/mp4');
        widget.onSend(VoiceNote(
          mediaKey: result.mediaKey,
          duration: duration,
          waveform: waveform,
        ));
      }
    } catch (e) {
      debugPrint('[voice] upload failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L.of(context).voiceUploadFailed)),
        );
      }
      widget.onCancel();
    } finally {
      // Deleted only after the upload, not before it. The old code removed
      // the file regardless, so a failed send lost the recording outright.
      if (await file.exists()) await file.delete();
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);

    if (_uploading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: IronColors.accentText),
        ),
      );
    }

    return GestureDetector(
      onLongPressStart: (_) => _start(),
      onLongPressEnd: (_) => _stop(send: true),
      onLongPressCancel: () => _stop(send: false),
      child: Semantics(
        button: true,
        label: t.recordVoiceNote,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_recording) ...[
              Text(
                _formatDuration(_seconds),
                style: const TextStyle(
                    color: IronColors.errorRed, fontSize: 13),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                height: 28,
                child: _Bars(values: _preview, color: IronColors.errorRed),
              ),
              const SizedBox(width: 8),
            ],
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _recording ? IronColors.errorRed : IronColors.gold,
              ),
              child: Icon(
                IronIcons.mic,
                color: _recording ? IronColors.white : IronColors.navyDeep,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDuration(double seconds) {
  final total = seconds.floor();
  final m = (total ~/ 60).toString().padLeft(2, '0');
  final s = (total % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// The bars themselves, shared by the recorder and the player.
class _Bars extends StatelessWidget {
  const _Bars({required this.values, required this.color, this.progress = 1});

  final List<double> values;
  final Color color;

  /// 0..1 — bars past this point are dimmed, showing playback position.
  final double progress;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Container(
                height: 3 + values[i] * (constraints.maxHeight - 3),
                margin: const EdgeInsets.symmetric(horizontal: 0.5),
                decoration: BoxDecoration(
                  color: i / values.length <= progress
                      ? color
                      : color.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Exposed so the player draws exactly the same bars as the recorder.
class VoiceBars extends StatelessWidget {
  const VoiceBars({
    super.key,
    required this.values,
    required this.color,
    this.progress = 1,
  });

  final List<double> values;
  final Color color;
  final double progress;

  @override
  Widget build(BuildContext context) =>
      _Bars(values: values, color: color, progress: progress);
}
