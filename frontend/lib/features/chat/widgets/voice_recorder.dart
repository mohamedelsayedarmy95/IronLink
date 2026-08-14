import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../../../core/theme.dart';
import '../../../core/icons.dart';

class VoiceRecorder extends StatefulWidget {
  final Function(String mediaKey, double duration, List<double> waveform) onSend;
  final VoidCallback onCancel;

  const VoiceRecorder({
    Key? key,
    required this.onSend,
    required this.onCancel,
  }) : super(key: key);

  @override
  State<VoiceRecorder> createState() => _VoiceRecorderState();
}

class _VoiceRecorderState extends State<VoiceRecorder> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  double _duration = 0;
  Timer? _timer;
  List<double> _waveform = [];
  String? _recordingPath;

  void _startRecording() async {
    try {
      if (!await _audioRecorder.hasPermission()) return;
      final path = await _getTempPath(suffix: '.aac');
      _recordingPath = path;
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 16000,
          sampleRate: 16000,
        ),
        path: path,
      );
      setState(() {
        _isRecording = true;
        _duration = 0;
      });
      _startDurationTimer();
      _startWaveformUpdate();
    } catch (e) {
      debugPrint('Error starting recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;

    _timer?.cancel();
    await _audioRecorder.stop();
    final duration = _duration;
    setState(() => _isRecording = false);

    if (_recordingPath == null) return;

    final file = File(_recordingPath!);

    if (duration < 1) {
      // Too short -> cancel
      if (await file.exists()) await file.delete();
      widget.onCancel();
      return;
    }

    await _uploadVoiceMessage(file, duration);

    // Cleanup
    if (await file.exists()) await file.delete();

    setState(() {
      _recordingPath = null;
      _waveform = [];
    });
  }

  Future<String> _getTempPath({String suffix = '.aac'}) async {
    final dir = await getTemporaryDirectory();
    return '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}$suffix';
  }

  Future<void> _uploadVoiceMessage(File file, double duration) async {
    // In a real implementation, we would upload to the server here
    // For now, we'll simulate by generating a fake media key and mock waveform
    // The actual upload would happen via the media API

    // Simulate media key (in reality, this comes from the server after upload)
    final mediaKey = 'voice_${DateTime.now().millisecondsSinceEpoch}.aac';

    // Generate mock waveform data (in reality, we'd extract this from the audio)
    final waveform = List.generate(20, (_) => 0.5 + 0.5 * (_.isEven ? 1 : -1));

    // Notify parent to send the voice message
    widget.onSend(mediaKey, duration, waveform);
  }

  void _startDurationTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _duration++);
    });
  }

  void _startWaveformUpdate() {
    // Update waveform every 0.1s during recording (mock data)
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_isRecording) {
        timer.cancel();
        return;
      }
      setState(() {
        // Simulate waveform with random data (in real app, use audio meters)
        _waveform = List.generate(20, (_) => 0.5 + 0.5 * (_.isEven ? 1 : -1) * (0.3 + 0.7 * (_.isEven ? 1 : 0)));
      });
    });
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isRecording)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            decoration: BoxDecoration(
              color: IronColors.errorRed,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(IronIcons.mic, color: IronColors.white),
                const SizedBox(width: 8),
                Text(
                  '${_duration.toStringAsFixed(0)}s',
                  style: const TextStyle(color: IronColors.white, fontSize: 16),
                ),
              ],
            ),
          )
        else
          GestureDetector(
            onLongPressStart: (_) => _startRecording(),
            onLongPressEnd: (_) => _stopRecording(),
            onLongPressCancel: () => _stopRecording(),
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: IronColors.gold,
              ),
              child: const Icon(IronIcons.mic, color: IronColors.navyDeep),
            ),
          ),
        if (_isRecording)
          SizedBox(
            height: 100,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final amplitude in _waveform)
                  Container(
                    width: 4,
                    height: 8 + amplitude.clamp(0.0, 1.0) * 72,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: IronColors.gold,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
