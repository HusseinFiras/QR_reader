import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:flutter/foundation.dart';

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

class BackendService with ChangeNotifier {
  static const String _host = '127.0.0.1';
  static const int _port = 5000;
  
  Socket? _socket;
  bool _isConnected = false;
  final StreamController<QRResult> _resultStreamController = StreamController<QRResult>.broadcast();
  final StreamController<String> _errorStreamController = StreamController<String>.broadcast();

  Stream<QRResult> get resultStream => _resultStreamController.stream;
  Stream<String> get errorStream => _errorStreamController.stream;
  bool get isConnected => _isConnected;

  Future<void> connect() async {
    debugPrint('BackendService: Connecting to $_host:$_port...');
    int attempts = 0;
    const maxAttempts = 5;
    const retryDelay = Duration(seconds: 1);
    
    while (attempts < maxAttempts) {
      try {
        _socket = await Socket.connect(_host, _port);
        _isConnected = true;
        notifyListeners();
        debugPrint('BackendService: Connected successfully');

        // Start listening for responses
        _socket!.listen(
          (data) {
            try {
              debugPrint('BackendService: Received data from server');
              final response = msgpack.deserialize(data);
              debugPrint('BackendService: Deserialized response type: ${response['type']}');
              
              if (response['type'] == 'qr_results' && 
                  response['data'] != null && 
                  response['data'].isNotEmpty) {
                
                final results = response['data'] as List;
                debugPrint('BackendService: Got ${results.length} QR results');
                
                if (results.isNotEmpty) {
                  for (var result in results) {
                    try {
                      final qrData = result['data']?.toString() ?? '';
                      if (qrData.isNotEmpty) {
                        debugPrint('BackendService: Processing QR result: $qrData');
                        final qrResult = QRResult.fromJson(result as Map<dynamic, dynamic>);
                        debugPrint('BackendService: Successfully created QRResult object');
                        _resultStreamController.add(qrResult);
                        debugPrint('BackendService: Added QR result to stream');
                      }
                    } catch (e, stackTrace) {
                      debugPrint('BackendService: Error processing individual QR result: $e');
                      debugPrint('BackendService: Stack trace: $stackTrace');
                    }
                  }
                }
              }
            } catch (e, stackTrace) {
              debugPrint('BackendService: Error processing response: $e');
              debugPrint('BackendService: Stack trace: $stackTrace');
              _errorStreamController.add('Error processing response: $e');
            }
          },
          onError: (error) {
            debugPrint('BackendService: Socket error: $error');
            _errorStreamController.add('Socket error: $error');
            _disconnect();
          },
          onDone: () {
            debugPrint('BackendService: Socket connection closed');
            _disconnect();
          },
        );
        
        // If we get here, connection was successful
        return;
        
      } catch (e) {
        attempts++;
        debugPrint('BackendService: Connection attempt $attempts failed: $e');
        if (attempts < maxAttempts) {
          debugPrint('BackendService: Retrying in ${retryDelay.inSeconds} seconds...');
          await Future.delayed(retryDelay);
        }
      }
    }
    
    // If we get here, all attempts failed
    debugPrint('BackendService: All connection attempts failed');
    _errorStreamController.add('Failed to connect after $maxAttempts attempts');
    throw Exception('Failed to connect to backend after $maxAttempts attempts');
  }

  Future<void> sendFrame(Uint8List frameData) async {
    if (!_isConnected || _socket == null) {
      debugPrint('BackendService: Cannot send frame - not connected');
      throw Exception('Not connected to backend');
    }

    try {
      debugPrint('BackendService: Sending frame of size ${frameData.length} bytes');
      final message = msgpack.serialize({
        'type': 'frame',
        'data': frameData,
        'timestamp': DateTime.now().millisecondsSinceEpoch / 1000,
      });
      _socket!.add(message);
      debugPrint('BackendService: Frame sent successfully');
    } catch (e) {
      debugPrint('BackendService: Error sending frame: $e');
      _errorStreamController.add('Error sending frame: $e');
    }
  }

  void _disconnect() {
    debugPrint('BackendService: Disconnecting...');
    _socket?.close();
    _socket = null;
    _isConnected = false;
    notifyListeners();
    debugPrint('BackendService: Disconnected');
  }

  Future<void> disconnect() async {
    debugPrint('BackendService: Cleaning up...');
    _disconnect();
    await _resultStreamController.close();
    await _errorStreamController.close();
    debugPrint('BackendService: Cleanup completed');
  }
} 