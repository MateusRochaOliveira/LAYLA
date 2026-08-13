// lib/services/hands_free_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vosk_flutter/vosk_flutter.dart';

/// Hands-Free Human-Computer Interaction (HCI) Service for LAYLA Level Pro.
/// Handles fully offline Speech-To-Text (STT) command recognition via Vosk 
/// and Text-To-Speech (TTS) auditory feedback.
class HandsFreeService {
  final VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance();
  final FlutterTts _flutterTts = FlutterTts();
  StreamSubscription<dynamic>? _partialSubscription;

  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _speechService;

  bool _isListening = false;
  bool _isInitialized = false;

  bool get isListening => _isListening;
  bool get isInitialized => _isInitialized;

  /// Initializes TTS audio output and loads the local offline Vosk language model.
  Future<void> initialize({
    String modelAssetPath = 'assets/models/vosk-model-small-pt-0.3.zip',
    String languageCode = 'pt-BR',
  }) async {
    if (_isInitialized) return;

    try {
      // 1. Configure Text-To-Speech (Audio Output)
      await _flutterTts.setLanguage(languageCode);
      await _flutterTts.setSpeechRate(0.5); // Natural speech rate
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      // 2. Load Offline Vosk Model from Local Assets
      final modelLoader = ModelLoader();
      final String modelPath = await modelLoader.loadFromAssets(modelAssetPath);
      _model = await _vosk.createModel(modelPath);

      // Constrain vocabulary (Grammar) using a List<String> for high accuracy and minimal RAM footprint
      final List<String> grammar = ['medir', 'capturar', 'salvar', 'cancelar', '[unk]'];

      _recognizer = await _vosk.createRecognizer(
        model: _model!,
        sampleRate: 16000,
        grammar: grammar,
      );

      _speechService = await _vosk.initSpeechService(_recognizer!);
      _isInitialized = true;

      debugPrint('[HandsFreeService] Successfully initialized offline TTS and Vosk STT.');
    } catch (e) {
      _isInitialized = false;
      debugPrint('[HandsFreeService] Initialization error: $e');
    }
  }

  /// Provides auditory feedback to the operator regarding the current measurement.
  Future<void> speakMeasurement({
    required double pitch,
    required double roll,
    required bool isCompliant,
  }) async {
    final String statusText = isCompliant ? 'Compliant' : 'Non-compliant';
    final String textToSpeak =
        'Slope: ${pitch.abs().toStringAsFixed(1)} degrees. Status: $statusText.';

    await _flutterTts.stop();
    await _flutterTts.speak(textToSpeak);
  }

  /// Speaks a custom message directly to the operator.
  Future<void> speak(String text) async {
    await _flutterTts.stop();
    await _flutterTts.speak(text);
  }

  /// Starts listening for voice commands in an offline background stream.
  Future<void> startListening({
    required Function(String command) onCommandRecognized,
  }) async {
    if (!_isInitialized || _speechService == null || _isListening) return;

    _isListening = true;

    try {
      // Listen to partial or final transcription results from Vosk
      _partialSubscription?.cancel();
      _partialSubscription = _speechService!.onPartial().listen((String partialJson) {
        final String recognizedText = partialJson.toLowerCase();

        if (recognizedText.contains('medir') ||
            recognizedText.contains('capturar') ||
            recognizedText.contains('measure')) {
          onCommandRecognized('measure');
          stopListening();
        } else if (recognizedText.contains('salvar') ||
                   recognizedText.contains('save')) {
          onCommandRecognized('save');
          stopListening();
        }
      });

      await _speechService!.start();
      debugPrint('[HandsFreeService] Started listening for voice commands...');
    } catch (e) {
      debugPrint('[HandsFreeService] Error starting speech service: $e');
      _isListening = false;
    }
  }

  /// Stops listening to the device microphone.
  Future<void> stopListening() async {
    if (_speechService != null && _isListening) {
      await _speechService!.stop();
      _isListening = false;
      debugPrint('[HandsFreeService] Stopped listening.');
    }
  }

  /// Releases resources when disposing the service.
  void dispose() {
    _partialSubscription?.cancel();
    _flutterTts.stop();
    _speechService?.dispose();
    _recognizer?.dispose();
    _isListening = false;
    _isInitialized = false;
  }
}