import 'dart:core';
import 'package:flutter/foundation.dart';

class ScannerPerformanceService {
  int _totalFrames = 0;
  int _processedFrames = 0;
  int _droppedFrames = 0;
  List<Duration> _processingTimes = [];
  DateTime? _lastFrameTime;

  void recordFrameProcessed(Duration processingTime) {
    _totalFrames++;
    _processedFrames++;
    _processingTimes.add(processingTime);
    _lastFrameTime = DateTime.now();
    
    // Keep only last 100 timing samples
    if (_processingTimes.length > 100) {
      _processingTimes.removeAt(0);
    }
  }
  
  void recordDroppedFrame() {
    _totalFrames++;
    _droppedFrames++;
  }
  
  void reset() {
    _totalFrames = 0;
    _processedFrames = 0;
    _droppedFrames = 0;
    _processingTimes.clear();
    _lastFrameTime = null;
  }
  
  double get averageProcessingTime {
    if (_processingTimes.isEmpty) return 0;
    final total = _processingTimes.fold<Duration>(
      Duration.zero,
      (prev, curr) => prev + curr,
    );
    return total.inMicroseconds / _processingTimes.length / 1000; // Convert to ms
  }
  
  double get frameRate {
    if (_totalFrames < 2 || _lastFrameTime == null) return 0;
    final duration = DateTime.now().difference(_lastFrameTime!);
    return _processedFrames / duration.inSeconds;
  }
  
  void logPerformanceMetrics() {
    debugPrint('''
Camera Performance Metrics:
Total Frames: $_totalFrames
Processed Frames: $_processedFrames
Dropped Frames: $_droppedFrames
Average Processing Time: ${averageProcessingTime.toStringAsFixed(2)}ms
Current Frame Rate: ${frameRate.toStringAsFixed(2)} fps
''');
  }
} 