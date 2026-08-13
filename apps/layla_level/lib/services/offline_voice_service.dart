// lib/services/offline_voice_service.dart

import 'dart:async';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:vosk_flutter/vosk_flutter.dart';

enum VoiceLanguage { portuguese, english }

class OfflineVoiceService {
  final VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance();
  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _speechService;
  StreamSubscription<dynamic>? _resultSubscription;

  bool _isListening = false;
  bool get isListening => _isListening;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// Extrai o arquivo .zip dos assets para o armazenamento do celular (se ainda não existir)
  Future<String> _loadAndUnzipModel(String zipAssetName, String targetFolderName) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final targetDir = Directory('${docsDir.path}/$targetFolderName');

    // Se a pasta descompactada já existe no celular, apenas retorna o caminho
    if (await targetDir.exists()) {
      return targetDir.path;
    }

    // Se não existe, lê o .zip dos assets e extrai
    final byteData = await rootBundle.load('assets/models/$zipAssetName');
    final bytes = byteData.buffer.asUint8List();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final file in archive) {
      final filename = file.name;
      if (file.isFile) {
        final data = file.content as List<int>;
        final outFile = File('${targetDir.path}/$filename');
        await outFile.create(recursive: true);
        await outFile.writeAsBytes(data);
      } else {
        await Directory('${targetDir.path}/$filename').create(recursive: true);
      }
    }

    return targetDir.path;
  }

  /// Inicializa o modelo de voz extraindo o .zip correto
  Future<void> initLanguage(VoiceLanguage language) async {
    try {
      final zipName = language == VoiceLanguage.portuguese
          ? 'vosk_pt.zip'
          : 'vosk_en.zip';
      final folderName = language == VoiceLanguage.portuguese
          ? 'vosk_pt'
          : 'vosk_en';

      // 1. Extrai o zip e obtém o caminho local no aparelho
      final modelPath = await _loadAndUnzipModel(zipName, folderName);

      // 2. Carrega o modelo no Vosk a partir do caminho descompactado
      _model = await _vosk.createModel(modelPath);

      _recognizer = await _vosk.createRecognizer(
        model: _model!,
        sampleRate: 16000,
      );

      _speechService = await _vosk.initSpeechService(_recognizer!);
      _isInitialized = true;
    } catch (e) {
      _isInitialized = false;
      debugPrint('[OfflineVoiceService] Failed to initialize voice engine: $e');
    }
  }

  /// Inicia a escuta do microfone
  Future<void> startListening(Function(String text) onResult) async {
    if (_speechService == null || !_isInitialized) return;

    _isListening = true;
    await _speechService!.start();

    _resultSubscription?.cancel();
    _resultSubscription = _speechService!.onResult().listen((result) {
      onResult(result.toLowerCase());
    });
  }

  /// Para de escutar o microfone
  Future<void> stopListening() async {
    if (_speechService != null && _isListening) {
      await _speechService!.stop();
      _isListening = false;
    }
  }

  void dispose() {
    _resultSubscription?.cancel();
    _speechService?.dispose();
    _recognizer?.dispose();
    _isListening = false;
    _isInitialized = false;
    // O Model não precisa de dispose no vosk_flutter
  }
}