import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/crypto/attachment_crypto.dart';
import '../../../core/icons.dart';
import '../../../core/media_service.dart';
import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';
import 'voice_recorder.dart' show VoiceBars;

/// Plays a voice note, decrypting it first when the stored body is encrypted.
class VoicePlayer extends StatefulWidget {
  const VoicePlayer({
    super.key,
    required this.media,
    required this.mediaKey,
    required this.duration,
    required this.waveform,
    this.attachmentKey,
    this.tint = IronColors.gold,
  });

  final MediaService media;
  final String mediaKey;
  final double duration;
  final List<double> waveform;

  /// Present when the audio in storage is ciphertext.
  final AttachmentKey? attachmentKey;

  final Color tint;

  @override
  State<VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<VoicePlayer> {
  final _player = AudioPlayer();

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _stateSub;

  File? _temp;
  bool _loading = false;
  bool _failed = false;
  bool _tampered = false;
  Duration _position = Duration.zero;
  double _speed = 1;

  @override
  void initState() {
    super.initState();
    // Deliberately does NOT load or play here. The previous version fetched
    // and auto-played in initState, so opening a conversation downloaded
    // every voice note in it and started them talking at once.
    _positionSub = _player.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _stateSub = _player.playerStateStream.listen((s) {
      if (!mounted) return;
      if (s.processingState == ProcessingState.completed) {
        _player.pause();
        _player.seek(Duration.zero);
        setState(() => _position = Duration.zero);
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    // The old code wrote a temp file per playback and never removed any.
    _temp?.delete().ignore();
    super.dispose();
  }

  Future<void> _ensureLoaded() async {
    if (_temp != null || _loading) return;
    setState(() {
      _loading = true;
      _failed = false;
      _tampered = false;
    });

    try {
      final key = widget.attachmentKey;
      final bytes = key != null
          ? await widget.media.downloadDecrypted(widget.mediaKey, key)
          : await widget.media.download(widget.mediaKey);

      final dir = await getTemporaryDirectory();
      // Written to disk because just_audio needs a source it can seek; the
      // decrypted bytes never leave the app's private directory, and the
      // file is deleted when this widget goes away.
      final file = File(
        '${dir.path}/voice_${widget.mediaKey.hashCode}.m4a',
      );
      await file.writeAsBytes(bytes, flush: true);
      await _player.setFilePath(file.path);
      if (!mounted) {
        file.delete().ignore();
        return;
      }
      setState(() {
        _temp = file;
        _loading = false;
      });
    } on AttachmentTampered {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _tampered = true;
      });
    } catch (e) {
      debugPrint('[voice] load failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _toggle() async {
    if (_tampered) return;
    await _ensureLoaded();
    if (_temp == null) return;

    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.setSpeed(_speed);
      await _player.play();
    }
  }

  double get _progress {
    final total = widget.duration;
    if (total <= 0) return 0;
    return (_position.inMilliseconds / (total * 1000)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);

    if (_tampered) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(IronIcons.error,
              size: IronIcons.sizeCompact, color: IronColors.errorRed),
          const SizedBox(width: 8),
          Flexible(
            child: Text(t.attachmentTampered,
                style: const TextStyle(
                    color: IronColors.textLo, fontSize: 12)),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 36,
          height: 36,
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: IronColors.accentText),
                )
              : IconButton(
                  padding: EdgeInsets.zero,
                  tooltip: _player.playing ? t.pause : t.play,
                  icon: Icon(
                    _failed
                        ? IronIcons.offline
                        : _player.playing
                            ? IronIcons.pause
                            : IronIcons.play,
                    color: widget.tint,
                  ),
                  onPressed: _toggle,
                ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 110,
          height: 26,
          child: VoiceBars(
            values: widget.waveform,
            color: widget.tint,
            progress: _temp == null ? 1 : _progress,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _formatDuration(
            _temp == null ? widget.duration : _position.inSeconds.toDouble(),
          ),
          style: TextStyle(color: widget.tint, fontSize: 12),
        ),
        if (_temp != null) ...[
          const SizedBox(width: 4),
          // Playback speed is only meaningful once there is audio loaded.
          GestureDetector(
            onTap: () {
              final next = switch (_speed) {
                1.0 => 1.5,
                1.5 => 2.0,
                _ => 1.0,
              };
              _player.setSpeed(next);
              setState(() => _speed = next);
            },
            child: Text(
              '${_speed}x',
              style: TextStyle(
                  color: widget.tint,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ],
    );
  }
}

String _formatDuration(double seconds) {
  final total = seconds.floor();
  final m = (total ~/ 60).toString().padLeft(2, '0');
  final s = (total % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
