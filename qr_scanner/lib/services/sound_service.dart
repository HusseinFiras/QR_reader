import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class SoundService extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  bool _isMuted = false;

  bool get isMuted => _isMuted;

  Future<void> initialize() async {
    // Set up any initial configuration
    await _player.setSource(AssetSource('sounds/beep.mp3'));
  }

  Future<void> playQRDetectedSound() async {
    if (!_isMuted) {
      try {
        await _player.play(AssetSource('sounds/beep.mp3'));
      } catch (e) {
        debugPrint('Error playing sound: $e');
      }
    }
  }

  void toggleMute() {
    _isMuted = !_isMuted;
    notifyListeners();
  }

  void dispose() {
    _player.dispose();
    super.dispose();
  }
} 