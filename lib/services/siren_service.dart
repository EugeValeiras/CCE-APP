import 'package:audioplayers/audioplayers.dart';

class SirenService {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;

  bool get isPlaying => _isPlaying;

  Future<void> init() async {
    // Configure for maximum volume playback even in silent mode
    await _player.setAudioContext(
      AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: {AVAudioSessionOptions.duckOthers},
        ),
      ),
    );
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.setVolume(1.0);
  }

  Future<void> startSiren({String sound = 'alarm'}) async {
    if (_isPlaying) return;
    _isPlaying = true;

    String assetPath;
    switch (sound) {
      case 'doorbell':
        assetPath = 'sounds/doorbell.wav';
        break;
      case 'alert':
        assetPath = 'sounds/alert.wav';
        break;
      default:
        assetPath = 'sounds/alarm_siren.wav';
    }

    await _player.setAudioContext(
      AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: {AVAudioSessionOptions.duckOthers},
        ),
      ),
    );
    await _player.setVolume(1.0);
    await _player.play(AssetSource(assetPath));
  }

  Future<void> stop() async {
    _isPlaying = false;
    await _player.stop();
  }

  void dispose() {
    _player.dispose();
  }
}
