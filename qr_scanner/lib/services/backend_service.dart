import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:flutter/foundation.dart';
import '../services/sound_service.dart';

class QRResult {
  final String data;
  final String type;
  final Map<String, int> rect;
  final List<List<int>> polygon;
  final DateTime timestamp;

  QRResult({
    required this.data,
    required this.type,
    required this.rect,
    required this.polygon,
    required this.timestamp,
  });

  factory QRResult.fromJson(Map<dynamic, dynamic> json) {
    // Convert dynamic map to properly typed map for rect
    final rectData = (json['rect'] as Map<dynamic, dynamic>).map(
      (key, value) => MapEntry(key.toString(), value as int),
    );

    // Convert polygon data to proper type
    final polygonData = (json['polygon'] as List).map((point) {
      final pointList = point as List;
      return [pointList[0] as int, pointList[1] as int];
    }).toList();

    return QRResult(
      data: json['data'].toString(),
      type: json['type'].toString(),
      rect: rectData,
      polygon: polygonData,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (json['timestamp'] as num).toInt() * 1000,
      ),
    );
  }
}

class BackendService extends ChangeNotifier {
  static const String _host = '127.0.0.1';
  static const int _port = 5000;
  
  Socket? _socket;
  bool _isConnected = false;
  final StreamController<QRResult> _resultStreamController = StreamController<QRResult>.broadcast();
  final StreamController<String> _errorStreamController = StreamController<String>.broadcast();
  final List<Map<String, dynamic>> _detectedCodes = [];
  final SoundService _soundService = SoundService();

  Stream<QRResult> get resultStream => _resultStreamController.stream;
  Stream<String> get errorStream => _errorStreamController.stream;
  bool get isConnected => _isConnected;
  List<Map<String, dynamic>> get detectedCodes => List.unmodifiable(_detectedCodes);
  SoundService get soundService => _soundService;

  Future<void> initialize() async {
    await _soundService.initialize();
  }

  Future<void> connect() async {
    if (_isConnected) return;

    int attempts = 0;
    const maxAttempts = 5;

    while (attempts < maxAttempts) {
      try {
        _socket = await Socket.connect('127.0.0.1', 5000);
        _isConnected = true;
        debugPrint('Connected to backend server');
        
        _socket!.listen(
          (List<int> data) {
            _handleServerMessage(data);
          },
          onError: (error) {
            debugPrint('Socket error: $error');
            _isConnected = false;
            notifyListeners();
          },
          onDone: () {
            debugPrint('Socket closed');
            _isConnected = false;
            notifyListeners();
          },
        );
        
        break;
      } catch (e) {
        attempts++;
        debugPrint('BackendService: Connection attempt $attempts failed: $e');
        if (attempts < maxAttempts) {
          debugPrint('BackendService: Retrying in 1 seconds...');
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }

    if (!_isConnected) {
      debugPrint('BackendService: All connection attempts failed');
      throw Exception('Failed to connect to backend after $maxAttempts attempts');
    }

    notifyListeners();
  }

  Future<void> disconnect() async {
    await _socket?.close();
    _socket = null;
    _isConnected = false;
    notifyListeners();
  }

  Future<void> sendFrame(Uint8List frameData) async {
    if (!_isConnected) {
      debugPrint('Cannot send frame - not connected');
      return;
    }

    try {
      final message = {
        'type': 'frame',
        'data': frameData,
      };
      
      final packed = Uint8List.fromList(msgpack.serialize(message));
      _socket?.add(packed);
      await _socket?.flush();
    } catch (e) {
      debugPrint('Error sending frame: $e');
    }
  }

  void _handleServerMessage(List<int> data) {
    try {
      final dynamic rawMessage = msgpack.deserialize(Uint8List.fromList(data));
      if (rawMessage is Map) {
        final message = Map<String, dynamic>.from(rawMessage);
        if (message['type'] == 'qr_results') {
          final List<dynamic> rawResults = message['data'] as List<dynamic>;
          if (rawResults.isNotEmpty) {
            final qrMap = Map<String, dynamic>.from(rawResults.first as Map);
            final qrResult = QRResult(
              data: qrMap['data'].toString(),
              type: qrMap['type'].toString(),
              rect: (qrMap['rect'] as Map<dynamic, dynamic>).map(
                (key, value) => MapEntry(key.toString(), value as int),
              ),
              polygon: (qrMap['polygon'] as List).map((point) {
                final pts = point as List;
                return [pts[0] as int, pts[1] as int];
              }).toList(),
              timestamp: DateTime.fromMillisecondsSinceEpoch(
                (qrMap['timestamp'] as num).toInt() * 1000,
              ),
            );

            debugPrint('Detected QR code: ${qrResult.data}');
            _resultStreamController.add(qrResult);
            notifyListeners();
          }
        }
      }
    } catch (e, stackTrace) {
      debugPrint('Error handling server message: $e');
      debugPrint('Stack trace: $stackTrace');
      _errorStreamController.add(e.toString());
    }
  }

  @override
  void dispose() {
    disconnect();
    _soundService.dispose();
    super.dispose();
  }
} 