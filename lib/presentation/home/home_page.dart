import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../core/database/db_helper.dart';
import '../../core/ml/onnx_service.dart';
import '../../core/reports/pdf_service.dart';
import '../../core/video/video_repository.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<Deteccion> _detecciones = [];
  bool _isLoading = false;
  bool _dbStatus = false;
  String _onnxStatus = 'Verificando...';
  bool _onnxModelLoaded = false;
  double _processingProgress = 0.0;
  bool _videoProcessed = false;

  final VideoRepository _videoRepository = DeviceVideoRepository();
  final _caravanaController = TextEditingController(text: 'AR-70821-XP');
  final _loteController = TextEditingController(text: 'LOTE-A1-PATAGONIA');
  VideoPlayerController? _videoPlayerController;
  double? _livePeso;
  double? _liveCondicion;
  double? _liveLlenado;
  double? _lastFramePeso;

  @override
  void initState() {
    super.initState();
    _refreshSystemStatus();
    _loadDetecciones();
  }

  @override
  void dispose() {
    _caravanaController.dispose();
    _loteController.dispose();
    _videoPlayerController?.dispose();
    super.dispose();
  }

  Future<void> _refreshSystemStatus() async {
    if (kIsWeb) {
      setState(() {
        _dbStatus = true;
      });
    } else {
      try {
        final db = await DbHelper.instance.database;
        setState(() {
          _dbStatus = db.isOpen;
        });
      } catch (e) {
        setState(() {
          _dbStatus = false;
        });
      }
    }

    final onnx = OnnxService.instance;
    await onnx.initModel();
    setState(() {
      _onnxStatus = onnx.statusMessage;
      _onnxModelLoaded = onnx.isModelLoaded;
    });
  }

  Future<void> _loadDetecciones() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final list = await DbHelper.instance.getAllDetecciones();
      setState(() {
        _detecciones.clear();
        _detecciones.addAll(list);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cargar datos: $e', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFFD4AF37),
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _ejecutarInferenciaLocal() async {
    if (_caravanaController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingrese un ID de Caravana válido.', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          backgroundColor: Color(0xFFD4AF37),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      double peso = _livePeso ?? 450.0;
      double condicion = _liveCondicion ?? 3.5;
      double llenado = _liveLlenado ?? 3.5;

      if (_livePeso == null) {
        final videoPath = (_videoRepository as DeviceVideoRepository).selectedVideoPath;
        Map<String, double> onnxResults;

        if (videoPath != null && videoPath.toLowerCase().endsWith('.mp4')) {
          onnxResults = await OnnxService.instance.procesarVideoBovino(
            videoPath,
            onProgress: (progress) {
              setState(() {
                _processingProgress = progress;
              });
            },
          );
        } else {
          // Fallback: Ejecuta con features físicas base
          final features = [138.0, 165.0, 142.0];
          onnxResults = await OnnxService.instance.runInference(inputFeatures: features);
        }
        peso = onnxResults['peso_estimado']!;
        condicion = onnxResults['condicion_corporal']!;
        llenado = onnxResults['llenado_ruminal']!;
      }

      final nuevaDeteccion = Deteccion(
        caravanaId: _caravanaController.text.toUpperCase(),
        loteId: _loteController.text.toUpperCase(),
        timestamp: DateTime.now().toLocal().toString().substring(0, 19),
        pesoEstimado: peso,
        condicionCorporal: condicion,
        llenadoRuminal: llenado,
        estado: 'PROCESADO',
      );

      await DbHelper.instance.insertDeteccion(nuevaDeteccion);
      await _loadDetecciones();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Auditoría guardada de forma local.', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          backgroundColor: Color(0xFFD4AF37),
        ),
      );

      _generarNuevaCaravana();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error en análisis local: $e', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFFD4AF37),
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
        _processingProgress = 0.0;
      });
    }
  }

  void _generarNuevaCaravana() {
    final rand = DateTime.now().millisecondsSinceEpoch % 10000;
    setState(() {
      _caravanaController.text = 'AR-70821-XP$rand';
    });
  }

  Future<void> _cambiarEstado(int id, String nuevoEstado) async {
    await DbHelper.instance.updateEstadoDeteccion(id, nuevoEstado);
    _loadDetecciones();
  }

  Future<void> _limpiarHistorial() async {
    await DbHelper.instance.clearDetecciones();
    _loadDetecciones();
  }

  Future<void> _generarPdf() async {
    if (_detecciones.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay registros guardados para exportar en PDF.', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          backgroundColor: Color(0xFFD4AF37),
        ),
      );
      return;
    }
    await PdfService.generateAndPrintReport(_detecciones);
  }

  Future<void> _initializeVideo(String path) async {
    if (_videoPlayerController != null) {
      await _videoPlayerController!.dispose();
      _videoPlayerController = null;
    }

    setState(() {
      _videoProcessed = false;
      _livePeso = null;
      _liveCondicion = null;
      _liveLlenado = null;
      _lastFramePeso = null;
    });

    try {
      final controller = kIsWeb
          ? VideoPlayerController.networkUrl(Uri.parse(path))
          : VideoPlayerController.file(File(path));
      
      _videoPlayerController = controller;
      
      await controller.initialize();
      await controller.setLooping(false); // Reproduce una vez para gatillar el escaneo
      
      int lastProcessedIndex = -1;
      int frameCounter = 0;

      controller.addListener(() {
        if (!controller.value.isInitialized) return;

        final positionMs = controller.value.position.inMilliseconds;
        
        // Procesar cada 300 ms de reproducción para dar fluidez al escaneo frame por frame
        final int intervalIndex = positionMs ~/ 300;
        
        if (intervalIndex != lastProcessedIndex && controller.value.isPlaying) {
          lastProcessedIndex = intervalIndex;
          frameCounter++;
          _procesarFotogramaEnVivo(frameCounter);
        }

        // Al finalizar el video, guardamos automáticamente el último animal si hay datos
        if (positionMs >= controller.value.duration.inMilliseconds && !_videoProcessed && !_isLoading) {
          _videoProcessed = true;
          _guardarAnimalActualAlFinalizar();
        }
      });

      await controller.play();
    } catch (e) {
      debugPrint('Error al inicializar VideoPlayerController: $e');
    }
  }

  Future<void> _procesarFotogramaEnVivo(int frameIndex) async {
    final videoPath = (_videoRepository as DeviceVideoRepository).selectedVideoPath;
    if (videoPath == null) return;

    try {
      final results = await OnnxService.instance.procesarFrame(
        frameIndex: frameIndex,
        videoPath: videoPath,
      );

      final double peso = results['peso_estimado']!;
      final double condicion = results['condicion_corporal']!;
      final double llenado = results['llenado_ruminal']!;

      // Detectar cambio drástico de animal (variación > 150 kg entre frames)
      if (_lastFramePeso != null) {
        final double diff = (peso - _lastFramePeso!).abs();
        if (diff > 150.0) {
          // Guardar el registro acumulado del animal anterior
          await _guardarRegistroAutomatico(
            caravana: _caravanaController.text,
            peso: _lastFramePeso!,
            condicion: _liveCondicion ?? condicion,
            llenado: _liveLlenado ?? llenado,
          );
          
          // Generar caravana del nuevo animal (ej. ternero)
          _generarNuevaCaravana();
        }
      }

      setState(() {
        _livePeso = peso;
        _liveCondicion = condicion;
        _liveLlenado = llenado;
        _lastFramePeso = peso;
      });
    } catch (e) {
      debugPrint('Error procesando fotograma en vivo: $e');
    }
  }

  Future<void> _guardarRegistroAutomatico({
    required String caravana,
    required double peso,
    required double condicion,
    required double llenado,
  }) async {
    try {
      final nuevaDeteccion = Deteccion(
        caravanaId: caravana.toUpperCase(),
        loteId: _loteController.text.toUpperCase(),
        timestamp: DateTime.now().toLocal().toString().substring(0, 19),
        pesoEstimado: peso,
        condicionCorporal: condicion,
        llenadoRuminal: llenado,
        estado: 'PROCESADO',
      );

      await DbHelper.instance.insertDeteccion(nuevaDeteccion);
      await _loadDetecciones();
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Guardado automático: $caravana ($peso kg)', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFFD4AF37),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('Error en guardado automático: $e');
    }
  }

  Future<void> _guardarAnimalActualAlFinalizar() async {
    if (_livePeso != null) {
      await _guardarRegistroAutomatico(
        caravana: _caravanaController.text,
        peso: _livePeso!,
        condicion: _liveCondicion ?? 3.5,
        llenado: _liveLlenado ?? 3.5,
      );
    }
    
    setState(() {
      _isLoading = false;
      _processingProgress = 0.0;
    });
  }

  Future<void> _conectarArchivoVideo() async {
    try {
      final path = await _videoRepository.selectLocalVideo();
      if (path != null) {
        setState(() {
          _videoProcessed = false;
        });
        await _initializeVideo(path);
        setState(() {});
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Archivo de video cargado: ${path.split("/").last}', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            backgroundColor: const Color(0xFFD4AF37),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al conectar video: $e', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFFD4AF37),
        ),
      );
    }
  }

  void _desconectarVideo() {
    _videoRepository.stopStream();
    if (_videoPlayerController != null) {
      try {
        _videoPlayerController!.pause();
      } catch (_) {}
      _videoPlayerController!.dispose();
      _videoPlayerController = null;
    }
    setState(() {
      _processingProgress = 0.0;
      _videoProcessed = false;
      _livePeso = null;
      _liveCondicion = null;
      _liveLlenado = null;
      _lastFramePeso = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    const colorBg = Color(0xFF000000);
    const colorCard = Color(0xFF121212);
    const colorGold = Color(0xFFD4AF37);
    const colorWhite = Color(0xFFFFFFFF);
    const colorGrey = Color(0xFFB3B3B3);

    // Detecciones para alimentar el gráfico
    final lastDetecciones = _detecciones.reversed.toList();
    final List<double> weightData = lastDetecciones.map((d) => d.pesoEstimado).toList();

    return Scaffold(
      backgroundColor: colorBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Header Premium
              _buildHeaderPremium(colorGold, colorWhite, colorGrey),
              const SizedBox(height: 12),

              // 2. Telemetry Section
              _buildTelemetryRow(colorCard, colorGold, colorWhite, colorGrey),
              const SizedBox(height: 12),

              // 3. Monitor Central (Fila Fija: Video a la Izquierda y Gráfico de Líneas Dorado a la Derecha)
              _buildMonitorCentral(colorCard, colorGold, colorBg, colorWhite, colorGrey, weightData),
              const SizedBox(height: 12),

              // 4. Inputs de Caravana y Lote Horizontales y Botones Dorados
              _buildControlPanel(colorCard, colorBg, colorGold, colorWhite, colorGrey),
              const SizedBox(height: 12),

              // 5. Historial de Auditoría
              Expanded(
                child: _buildDetectionsTable(colorCard, colorBg, colorGold, colorWhite, colorGrey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderPremium(Color colorGold, Color colorWhite, Color colorGrey) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFD4AF37), width: 1.0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'AGROVISION IA',
                style: TextStyle(
                  color: Color(0xFFD4AF37),
                  fontSize: 22.0,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: colorGold, width: 0.8),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'MODO OFFLINE',
                  style: TextStyle(color: colorGold, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'SISTEMA DE INFERENCIA Y AUDITORÍA BIOMÉTRICA DE GANADO',
            style: TextStyle(color: colorGold.withAlpha(200), fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryRow(Color colorCard, Color colorGold, Color colorWhite, Color colorGrey) {
    return Row(
      children: [
        Expanded(
          child: _buildTelemetryCard(
            title: 'BASE DE DATOS',
            value: _dbStatus ? 'SQLITE OK' : 'ERROR',
            isActive: _dbStatus,
            colorGold: colorGold,
            colorGrey: colorGrey,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildTelemetryCard(
            title: 'MODELO ONNX',
            value: _onnxModelLoaded ? 'ONLINE' : 'FALLBACK',
            isActive: _onnxModelLoaded,
            statusColor: _onnxModelLoaded ? const Color(0xFF10B981) : Colors.red,
            colorGold: colorGold,
            colorGrey: colorGrey,
            description: _onnxStatus,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildTelemetryCard(
            title: 'CAPTURA VIDEO',
            value: _videoRepository.isStreaming ? 'STREAM OK' : 'SIN SEÑAL',
            isActive: _videoRepository.isStreaming,
            colorGold: colorGold,
            colorGrey: colorGrey,
          ),
        ),
      ],
    );
  }

  Widget _buildTelemetryCard({
    required String title,
    required String value,
    required bool isActive,
    required Color colorGold,
    required Color colorGrey,
    Color? statusColor,
    String? description,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        border: Border.all(color: colorGold, width: 1.0),
        borderRadius: BorderRadius.circular(4.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(color: colorGold, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.5),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.circle,
                color: statusColor ?? (isActive ? colorGold : Colors.red),
                size: 8,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(color: colorGrey, fontSize: 8, fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMonitorCentral(Color colorCard, Color colorGold, Color colorBg, Color colorWhite, Color colorGrey, List<double> weightData) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: colorCard,
        border: Border.all(color: colorGold, width: 1.0),
        borderRadius: BorderRadius.circular(4.0),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // Lado Izquierdo: Cuadro de Video
          Expanded(
            flex: 5,
            child: Container(
              decoration: BoxDecoration(
                color: colorBg,
                border: Border.all(color: colorGold.withAlpha(120), width: 0.8),
                borderRadius: BorderRadius.circular(4.0),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_videoRepository.isStreaming && _videoPlayerController != null && _videoPlayerController!.value.isInitialized) ...[
                    Positioned.fill(
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: _videoPlayerController!.value.aspectRatio,
                          child: VideoPlayer(_videoPlayerController!),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withAlpha(200),
                              Colors.black.withAlpha(60),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 8,
                      left: 8,
                      right: 8,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _videoRepository.currentSourceDescription,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (_processingProgress > 0.0 && _processingProgress < 1.0) ...[
                            const SizedBox(height: 4),
                            SizedBox(
                              width: 150,
                              height: 4,
                              child: LinearProgressIndicator(
                                value: _processingProgress,
                                color: colorGold,
                                backgroundColor: colorCard,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Frame: ${(_processingProgress * 100).toStringAsFixed(0)}%',
                              style: TextStyle(color: colorGold, fontSize: 8, fontWeight: FontWeight.bold),
                            ),
                          ],
                          const SizedBox(height: 6),
                          TextButton.icon(
                            onPressed: _desconectarVideo,
                            icon: const Icon(Icons.power_settings_new, color: Colors.red, size: 12),
                            label: const Text('DETENER', style: TextStyle(color: Colors.red, fontSize: 9, fontWeight: FontWeight.bold)),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              backgroundColor: Colors.black.withAlpha(150),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (_videoRepository.isStreaming) ...[
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.live_tv_rounded, color: Color(0xFFD4AF37), size: 36),
                          const SizedBox(height: 8),
                          Text(
                            _videoRepository.currentSourceDescription,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colorWhite, fontSize: 11, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(colorGold)),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.videocam_off_outlined, color: colorGold.withAlpha(100), size: 36),
                          const SizedBox(height: 8),
                          const Text(
                            'CORRAL OFFLINE',
                            style: TextStyle(color: Color(0xFFD4AF37), fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 34,
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _conectarArchivoVideo,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colorGold,
                                foregroundColor: colorBg,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2.0)),
                                padding: EdgeInsets.zero,
                                elevation: 0,
                              ),
                              icon: const Icon(Icons.folder_open, size: 14, color: Colors.black),
                              label: const Text(
                                '[+] Iniciar Captura de Video Bovino',
                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.black),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Lado Derecho: Gráfico de Líneas Dorado
          Expanded(
            flex: 4,
            child: Container(
              decoration: BoxDecoration(
                color: colorBg,
                border: Border.all(color: colorGold.withAlpha(120), width: 0.8),
                borderRadius: BorderRadius.circular(4.0),
              ),
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _videoRepository.isStreaming ? 'ESCANEANDO EN VIVO' : 'PESO HISTORIAL',
                        style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 8, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _videoRepository.isStreaming
                            ? (_livePeso != null ? '${_livePeso!.toStringAsFixed(1)} kg' : '--')
                            : (_detecciones.isNotEmpty ? '${_detecciones.first.pesoEstimado.toStringAsFixed(1)} kg' : '--'),
                        style: TextStyle(color: colorGold, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  if (_videoRepository.isStreaming && _livePeso != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'COND: ${_liveCondicion!.toStringAsFixed(1)}/5',
                          style: TextStyle(color: colorWhite, fontSize: 7, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'RUMEN: ${_liveLlenado!.toStringAsFixed(1)}/5',
                          style: TextStyle(color: colorWhite, fontSize: 7, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ] else if (_detecciones.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'COND: ${_detecciones.first.condicionCorporal.toStringAsFixed(1)}/5',
                          style: TextStyle(color: colorGrey, fontSize: 7, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'RUMEN: ${_detecciones.first.llenadoRuminal.toStringAsFixed(1)}/5',
                          style: TextStyle(color: colorGrey, fontSize: 7, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Expanded(
                    child: CustomPaint(
                      painter: LineChartPainter(data: weightData, minVal: 300, maxVal: 600),
                      child: Container(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel(Color colorCard, Color colorBg, Color colorGold, Color colorWhite, Color colorGrey) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorCard,
        border: Border.all(color: colorGold, width: 1.0),
        borderRadius: BorderRadius.circular(4.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    controller: _caravanaController,
                    style: TextStyle(color: colorWhite, fontSize: 12, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      labelText: 'CARAVANA ID',
                      labelStyle: TextStyle(color: colorGold, fontSize: 10, fontWeight: FontWeight.bold),
                      filled: true,
                      fillColor: colorBg,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(2.0),
                        borderSide: BorderSide(color: colorGold, width: 1.0),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(2.0),
                        borderSide: BorderSide(color: colorGold, width: 1.5),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    controller: _loteController,
                    style: TextStyle(color: colorWhite, fontSize: 12),
                    decoration: InputDecoration(
                      labelText: 'LOTE ID',
                      labelStyle: TextStyle(color: colorGold, fontSize: 10, fontWeight: FontWeight.bold),
                      filled: true,
                      fillColor: colorBg,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(2.0),
                        borderSide: BorderSide(color: colorGold, width: 1.0),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(2.0),
                        borderSide: BorderSide(color: colorGold, width: 1.5),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 42,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _ejecutarInferenciaLocal,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorGold,
                      foregroundColor: colorBg,
                      disabledBackgroundColor: colorGrey.withAlpha(80),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(2.0),
                        side: BorderSide(color: colorGold, width: 1.0),
                      ),
                      elevation: 0,
                    ),
                    icon: _isLoading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator.adaptive(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.black)),
                          )
                        : const Icon(Icons.bolt, size: 16, color: Colors.black),
                    label: const Text(
                      'GUARDAR REGISTRO LOCALLY',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10, color: Colors.black),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: SizedBox(
                  height: 42,
                  child: OutlinedButton.icon(
                    onPressed: _generarPdf,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorGold,
                      backgroundColor: colorBg,
                      side: BorderSide(color: colorGold, width: 1.0),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2.0)),
                    ),
                    icon: const Icon(Icons.picture_as_pdf, size: 14),
                    label: const Text(
                      'PDF REPORTE',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetectionsTable(Color colorCard, Color colorBg, Color colorGold, Color colorWhite, Color colorGrey) {
    return Container(
      decoration: BoxDecoration(
        color: colorCard,
        border: Border.all(color: colorGold, width: 1.0),
        borderRadius: BorderRadius.circular(4.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.table_chart_outlined, color: colorGold, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'AUDITORÍAS BOVINAS (${_detecciones.length})',
                      style: TextStyle(color: colorGold, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                if (_detecciones.isNotEmpty)
                  SizedBox(
                    height: 24,
                    child: TextButton.icon(
                      onPressed: _limpiarHistorial,
                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 14),
                      label: const Text('LIMPIAR', style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFD4AF37)),
          Expanded(
            child: _isLoading && _detecciones.isEmpty
                ? const Center(child: CircularProgressIndicator.adaptive())
                : _detecciones.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history_outlined, color: colorGold.withAlpha(100), size: 32),
                            const SizedBox(height: 6),
                            Text(
                              'Sin registros locales guardados en SQLite.',
                              style: TextStyle(color: colorGrey, fontSize: 11),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: _detecciones.length,
                        separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFD4AF37)),
                        itemBuilder: (context, index) {
                          final item = _detecciones[index];
                          return _buildDeteccionRow(item, colorWhite, colorGrey, colorGold);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeteccionRow(Deteccion item, Color colorWhite, Color colorGrey, Color colorGold) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.caravanaId,
                  style: TextStyle(color: colorGold, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                ),
                Text(
                  'Lote: ${item.loteId}',
                  style: TextStyle(color: colorGrey, fontSize: 8),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetricText('Peso', '${item.pesoEstimado.round()}kg', colorWhite, colorGrey),
                _buildMetricText('Cond.', item.condicionCorporal.toStringAsFixed(1), colorWhite, colorGrey),
                _buildMetricText('Rumen', item.llenadoRuminal.toStringAsFixed(1), colorWhite, colorGrey),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: item.estado == 'PROCESADO'
                        ? Colors.green.withAlpha(20)
                        : item.estado == 'FALLIDO'
                            ? Colors.red.withAlpha(20)
                            : colorGold.withAlpha(20),
                    border: Border.all(
                      color: item.estado == 'PROCESADO'
                          ? Colors.green
                          : item.estado == 'FALLIDO'
                              ? Colors.red
                              : colorGold,
                      width: 0.8,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    item.estado,
                    style: TextStyle(
                      color: item.estado == 'PROCESADO'
                          ? Colors.green
                          : item.estado == 'FALLIDO'
                              ? Colors.red
                              : colorGold,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (item.id != null) ...[
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: colorGold, size: 16),
                    color: const Color(0xFF121212),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onSelected: (val) => _cambiarEstado(item.id!, val),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'PENDIENTE',
                        child: Text('Pendiente', style: TextStyle(color: Colors.white, fontSize: 11)),
                      ),
                      const PopupMenuItem(
                        value: 'PROCESADO',
                        child: Text('Procesado', style: TextStyle(color: Colors.white, fontSize: 11)),
                      ),
                      const PopupMenuItem(
                        value: 'FALLIDO',
                        child: Text('Fallido', style: TextStyle(color: Colors.white, fontSize: 11)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricText(String label, String value, Color colorWhite, Color colorGrey) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(color: colorWhite, fontSize: 11, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: TextStyle(color: colorGrey, fontSize: 7),
        ),
      ],
    );
  }
}

// CustomPainter para el gráfico de líneas dorado
class LineChartPainter extends CustomPainter {
  final List<double> data;
  final double minVal;
  final double maxVal;

  LineChartPainter({required this.data, required this.minVal, required this.maxVal});

  @override
  void paint(Canvas canvas, Size size) {
    final paintGrid = Paint()
      ..color = const Color(0xFFD4AF37).withAlpha(40)
      ..strokeWidth = 0.5;

    final paintLine = Paint()
      ..color = const Color(0xFFD4AF37)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final paintFill = Paint()
      ..color = const Color(0xFFD4AF37).withAlpha(25)
      ..style = PaintingStyle.fill;

    final paintPoint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.fill;

    final paintPointOutline = Paint()
      ..color = const Color(0xFFD4AF37)
      ..strokeWidth = 1.0;

    // Draw horizontal grid lines
    const int gridLines = 3;
    for (int i = 0; i <= gridLines; i++) {
      final y = size.height * i / gridLines;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paintGrid);
    }

    if (data.isEmpty) return;

    final double xStep = size.width / (data.length > 1 ? data.length - 1 : 1);
    final double range = maxVal - minVal;

    final List<Offset> points = [];
    for (int i = 0; i < data.length; i++) {
      final val = data[i].clamp(minVal, maxVal);
      final y = size.height - ((val - minVal) / range) * size.height;
      final x = data.length > 1 ? i * xStep : size.width / 2;
      points.add(Offset(x, y));
    }

    // Draw path
    final path = Path();
    final fillPath = Path();

    if (data.length > 1) {
      path.moveTo(points[0].dx, points[0].dy);
      fillPath.moveTo(points[0].dx, size.height);
      fillPath.lineTo(points[0].dx, points[0].dy);

      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
        fillPath.lineTo(points[i].dx, points[i].dy);
      }

      fillPath.lineTo(points[points.length - 1].dx, size.height);
      fillPath.close();

      canvas.drawPath(fillPath, paintFill);
      canvas.drawPath(path, paintLine);
    } else {
      // Single point
      canvas.drawCircle(points[0], 4.0, paintPoint);
      canvas.drawCircle(points[0], 4.0, paintPointOutline);
      return;
    }

    // Draw data points (limit to last 6 points for clutter reduction)
    final startIdx = points.length > 6 ? points.length - 6 : 0;
    for (int i = startIdx; i < points.length; i++) {
      canvas.drawCircle(points[i], 3.0, paintPoint);
      canvas.drawCircle(points[i], 3.0, paintPointOutline);
    }
  }

  @override
  bool shouldRepaint(covariant LineChartPainter oldDelegate) {
    return oldDelegate.data != data;
  }
}
