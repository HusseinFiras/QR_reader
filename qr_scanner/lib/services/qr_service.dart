import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';

class QRService {
  static final QRService _instance = QRService._internal();
  factory QRService() => _instance;
  QRService._internal();

  Future<String> generateAndSaveQRCode(String fighterId, String fighterName) async {
    try {
      // Get the application documents directory
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String qrDir = path.join(appDir.path, 'qr_codes');
      
      // Create qr_codes directory if it doesn't exist
      await Directory(qrDir).create(recursive: true);
      
      // Generate a unique filename using fighter name and ID
      final String fileName = '$fighterName.png';
      final String filePath = path.join(qrDir, fileName);
      
      // Create a QR code painter
      final qrPainter = QrPainter(
        data: fighterId,
        version: QrVersions.auto,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Color(0xFF90B4FF),
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Color(0xFF90B4FF),
        ),
        gapless: false,
        embeddedImage: null,
        embeddedImageStyle: null,
        errorCorrectionLevel: QrErrorCorrectLevel.H,
      );
      
      // Convert QR code to image
      final ui.Image qrImage = await qrPainter.toImage(200);
      final ByteData? byteData = await qrImage.toByteData(format: ui.ImageByteFormat.png);
      
      if (byteData != null) {
        // Save the image
        final File file = File(filePath);
        await file.writeAsBytes(byteData.buffer.asUint8List());
        return filePath;
      }
      
      throw Exception('Failed to generate QR code image');
    } catch (e) {
      debugPrint('Error generating QR code: $e');
      rethrow;
    }
  }

  Future<void> deleteQRCode(String fighterName) async {
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String qrDir = path.join(appDir.path, 'qr_codes');
      final String filePath = path.join(qrDir, '$fighterName.png');
      
      final File file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Error deleting QR code: $e');
      rethrow;
    }
  }
} 