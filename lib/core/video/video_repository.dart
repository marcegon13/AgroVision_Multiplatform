import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// CONTRATO DE ORIGEN DE VIDEO (WEB CAM / IP CAMERA / LOCAL STREAM)
///
/// Desacopla la lógica de presentación de los detalles físicos de captura de video,
/// permitiendo alternar entre selecciones de archivos de galería en móviles y streaming RTSP/HTTP.
abstract class VideoRepository {
  /// Selecciona un archivo de video local guardado en el dispositivo usando la galería o selector nativo.
  Future<String?> selectLocalVideo();

  /// Establece conexión con una dirección IP de red local (ej: `rtsp://192.168.1.50:554/stream`).
  Future<String?> connectIpCamera(String url);

  /// Obtiene la descripción del origen de video activo actual.
  String get currentSourceDescription;

  /// Indica si el flujo de video/streaming está activo en este momento.
  bool get isStreaming;

  /// Detiene el flujo de video actual.
  void stopStream();
}

/// IMPLEMENTACIÓN CON FILE PICKER REAL PARA ALMACENAMIENTO LOCAL Y GALERÍA
class DeviceVideoRepository implements VideoRepository {
  String _sourceDescription = 'Sin origen de video conectado';
  bool _isStreaming = false;
  String? _selectedVideoPath;

  String? get selectedVideoPath => _selectedVideoPath;

  @override
  String get currentSourceDescription => _sourceDescription;

  @override
  bool get isStreaming => _isStreaming;

  @override
  Future<String?> selectLocalVideo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        _selectedVideoPath = file.path ?? file.name; // En Web file.path es nulo
        _sourceDescription = 'Video: ${file.name}';
        _isStreaming = true;
        return _selectedVideoPath;
      }
    } catch (e) {
      debugPrint('DEVICE_VIDEO_REPOSITORY: Error al seleccionar video de galería: $e');
    }
    return null;
  }

  @override
  Future<String?> connectIpCamera(String url) async {
    // Simulación de latencia de red al conectar cámara IP real
    await Future.delayed(const Duration(milliseconds: 600));

    if (url.isEmpty || (!url.startsWith('rtsp://') && !url.startsWith('http://'))) {
      throw Exception('Formato de dirección IP / RTSP inválido. Debe comenzar con rtsp:// o http://');
    }

    _selectedVideoPath = url;
    _sourceDescription = 'Streaming IP: $url';
    _isStreaming = true;

    return url;
  }

  @override
  void stopStream() {
    _sourceDescription = 'Sin origen de video conectado';
    _isStreaming = false;
    _selectedVideoPath = null;
  }
}
