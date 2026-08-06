import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import '../../../core/theme.dart';
import '../../../core/api_client.dart';
import 'package:dio/dio.dart';

class VoicePlayer extends StatefulWidget {
  final String mediaKey;
  final double duration;
  final List<double> waveform;

  const VoicePlayer({
    Key? key,
    required this.mediaKey,
    required this.duration,
    required this.waveform,
  }) : super(key: key);

  @override
  State<VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<VoicePlayer> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  double _speed = 1.0;
  Duration _position = Duration.zero;
  bool _isLoaded = false;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _playerStateSubscription;

  @override
  void initState() {
    super.initState();
    _positionSubscription = _audioPlayer.positionStream.listen(
        (position) => setState(() => _position = position));
    _playerStateSubscription = _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      }
    });
    _loadAndPlay();
  }

  Future<void> _loadAndPlay() async {
    try {
      // Get media URL from server
      final api = ApiClient();
      final response = await api.dio.get(
        '/media/$mediaKey',
        options: Options(
          headers: {'Authorization': 'Bearer ${await api.accessToken}'},
          responseType: ResponseType.bytes,
        ),
      );
      final bytes = response.data as Uint8List;
      await _audioPlayer.setAudioData(bytes);
      _audioPlayer.setSpeed(_speed);
      await _audioPlayer.play();
      setState(() {
        _isPlaying = true;
        _isLoaded = true;
      });
    } catch (e) {
      debugPrint('Error loading voice message: $e');
      setState(() => _isLoaded = false);
    }
  }

  void _togglePlayPause() {
    if (_audioPlayer.playing) {
      _audioPlayer.pause();
    } else {
      _audioPlayer.resume();
    }
    setState(() => _isPlaying = !_isPlaying);
  }

  void _setSpeed(double speed) {
    _audioPlayer.setSpeed(speed);
    setState(() => _speed = speed);
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded) {
      return const SizedBox(
        height: 80,
        child: Center(
          child: CircularProgressIndicator(color: MilColors.gold),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: MilColors.navySurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Waveform with progress indicator
          SizedBox(
            height: 60,
            child: AudioWaveforms(
              size: Size(double.infinity, 50),
              waveformData: widget.waveform,
              waveColor: MilColors.gold,
              waveWidth: 3,
              showLerpLine: false,
              enableCache: true,
              // We could add a progress indicator here by coloring part of the waveform
              // based on current position, but for simplicity we'll just show the waveform
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisSize.center,
            children: [
              IconButton(
                icon: Icon(
                  _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                  color: MilColors.gold,
                ),
                onPressed: _togglePlayPause,
                iconSize: 32,
              ),
              const SizedBox(width: 16),
              Text(
                '${_position.inMinutes.toString().padLeft(2, '0')}:'
                    '${(_position.inSeconds % 60).toString().padLeft(2, '0')} / '
                    '${widget.duration.inMinutes.toString().padLeft(2, '0')}:'
                    '${(widget.duration.inSeconds % 60).toString().padLeft(2, '0')}',
                style: const TextStyle(color: MilColors.textHi),
              ),
              const SizedBox(width: 16),
              PopupMenuButton<double>(
                initialValue: _speed,
                onSelected: _setSpeed,
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 1.0, child: Text('1.0x')),
                  const PopupMenuItem(value: 1.5, child: Text('1.5x')),
                  const PopupMenuItem(value: 2.0, child: Text('2.0x')),
                ],
                child: Icon(Icons.speed, color: MilColors.gold),
              ),
            ],
          ),
        ],
      ),
    );
  }
}