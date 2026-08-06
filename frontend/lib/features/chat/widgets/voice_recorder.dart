import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:flutter_ffmpeg/flutter_ffmpeg.dart';
import '../../../core/theme.dart';

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
  final Record _audioRecorder = Record();
  final FlutterFFmpeg _flutterFFmpeg = FlutterFFmpeg();
  bool _isRecording = false;
  double _duration = 0;
  Timer? _timer;
  List<double> _waveform = [];
  String? _recordingPath;

  @override
  void initState() {
    super.initState();
    _initRecorder();
  }

  Future<void> _initRecorder() async {
    if (await _audioRecorder.hasPermission()) {
      // Permission granted
    } else {
      // Request permission - in a real app, we'd handle this properly
      await _audioRecorder.requestPermission();
    }
  }

  void _startRecording() async {
    try {
      final path = await _getTempPath(suffix: '.aac');
      _recordingPath = path;
      await _audioRecorder.record(
        path: path,
        encoder: AudioEncoder.AAC,
        bitRate: 16000,
        samplingRate: 16000,
      );
      setState(() => _isRecording = true);
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
    setState(() => _isRecording = false);

    if (_recordingPath == null) return;

    final file = File(_recordingPath!);
    final duration = await _audioRecorder.getDuration(_recordingPath!);

    if (duration.inSeconds < 1) {
      // Too short -> cancel
      await file.delete();
      widget.onCancel();
      return;
    }

    // Compress audio to OPUS using flutter_ffmpeg
    final compressedPath = await _getTempPath(suffix: '.opus');
    final rc = await _flutterFFmpeg.execute(
        '-i ${_recordingPath!} -c:a libopus -b:a 16k -vbr off $compressedPath');

    if (rc == 0) {
      // Upload compressed file
      await _uploadVoiceMessage(File(compressedPath), duration.inSeconds.toDouble());
    } else {
      // Fallback: upload raw AAC
      await _uploadVoiceMessage(file, duration.inSeconds.toDouble());
    }

    // Cleanup
    await file.delete();
    if (File(compressedPath).existsSync()) await File(compressedPath).delete();

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
    final mediaKey = 'voice_${DateTime.now().millisecondsSinceEpoch}.opus';

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
              color: MilColors.errorRed,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mic, color: MilColors.white),
                const SizedBox(width: 8),
                Text(
                  '${_duration.toStringAsFixed(0)}s',
                  style: const TextStyle(color: MilColors.white, fontSize: 16),
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
                color: MilColors.gold,
              ),
              child: const Icon(Icons.mic, color: MilColors.navyDeep),
            ),
          ),
        if (_isRecording)
          SizedBox(
            height: 100,
            child: AudioWaveforms(
              size: Size(double.infinity, 80),
              waveformData: _waveform,
              waveColor: MilColors.gold,
              waveWidth: 4,
              showLerpLine: false,
              enableCache: true,
            ),
          ),
      ],
    );
  }
}