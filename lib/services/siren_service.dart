import 'package:audioplayers/audioplayers.dart';

class SirenService {
  /// El `AudioPlayer` se crea al primer uso, NO en el constructor: construirlo
  /// habla con el plugin nativo, y eso hacía imposible montar la pantalla de
  /// la alarma en un test (CCE#122). Con esto, una sirena de mentira que
  /// sobreescriba los métodos de abajo nunca llega a tocar el plugin.
  AudioPlayer? _lazyPlayer;
  AudioPlayer get _player => _lazyPlayer ??= AudioPlayer();

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
    // Sin `??=`: si nunca sonó, no hay nada que liberar (ni que construir).
    _lazyPlayer?.dispose();
  }
}
