// lib/main.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_tts/flutter_tts.dart';

// Project Imports
import 'ble_factory.dart';
import 'database_helper.dart';
import 'engineering_standards.dart';
import 'models/telemetry_data.dart';
import 'repositories/audit_repository.dart';
import 'screens/camera_overlay_screen.dart';
import 'services/ble_connection_service.dart';
import 'services/dsp_filter_service.dart';
import 'services/offline_voice_service.dart';
import 'services/pdf_report_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: LaylaHome(),
  ));
}

class LaylaHome extends StatefulWidget {
  const LaylaHome({super.key});

  @override
  State<LaylaHome> createState() => _LaylaHomeState();
}

class _LaylaHomeState extends State<LaylaHome> {
  static const String _gistRawUrl =
      "https://gist.githubusercontent.com/MateusRochaOliveira/c8316d5b5d546866ad326ef3892e8d71/raw/gistfile1.txt";

  BleConnectionService? _bleService;
  StreamSubscription<TelemetryData>? _telemetrySub;
  StreamSubscription<bool>? _connectionSub;

  final _serviceUuid = Uuid.parse("4fa12345-1234-1234-1234-123456789abc");
  final _charUuid = Uuid.parse("beb54321-1234-1234-1234-123456789abc");

  // DSP Filter instance (Alpha 0.15 = Optimal balance between stability and response time)
  final ComplementaryDspFilter _dspFilter = ComplementaryDspFilter(alpha: 0.15);

  // Telemetry payload with Pitch, Roll, Temp, Battery and Flags
  TelemetryData? _telemetry;
  double _pitch = 0.0;
  double _roll = 0.0;
  bool _isConnected = false;

  List<EngineeringStandard> _availableStandards =
      StandardsRegistry.defaultStandards;
  late EngineeringStandard _selectedStandard;
  bool _isLoadingCloudData = false;

  FlutterTts? _ttsInstance;
  final OfflineVoiceService _voiceService = OfflineVoiceService();

  List<InspectionItem> _sessionLogs = [];

  @override
  void initState() {
    super.initState();
    _selectedStandard = _availableStandards.first;

    if (!kIsWeb) {
      _ttsInstance = FlutterTts();
      _ttsInstance?.setLanguage("en-US");
      _initVoiceEngine();
      _loadStoredInspections();
      _initBleService();
    }

    _syncStandardsWithGist();
  }

  /// Initializes the Vosk offline voice engine model
  Future<void> _initVoiceEngine() async {
    await _voiceService.initLanguage(VoiceLanguage.english);
  }

  /// Instantiates the BLE service and subscribes to telemetry + connection streams
  void _initBleService() {
    final ble = BleFactory.instance;
    if (ble == null) return;

    _bleService = BleConnectionService(
      serviceUuid: _serviceUuid.toString(),
      characteristicUuid: _charUuid.toString(),
    );

    _telemetrySub = _bleService!.telemetryStream.listen((rawTelemetry) {
      // 1. DSP filter processing for noise/vibration reduction
      final filteredTelemetry = _dspFilter.process(rawTelemetry);

      if (!mounted) return;
      setState(() {
        _telemetry = filteredTelemetry;
        _pitch = filteredTelemetry.pitch;
        _roll = filteredTelemetry.roll;
      });
    });

    _connectionSub = _bleService!.connectionStateStream.listen((connected) {
      if (!mounted) return;
      setState(() => _isConnected = connected);
    });
  }

  Future<void> _loadStoredInspections() async {
    if (kIsWeb) return;
    try {
      final logs = await DatabaseHelper.instance
          .getAllInspections(_availableStandards);
      if (!mounted) return;
      setState(() {
        _sessionLogs = logs;
      });
    } catch (e) {
      debugPrint('[DB] Failed to load stored inspections: $e');
    }
  }

  Future<void> _syncStandardsWithGist() async {
    setState(() => _isLoadingCloudData = true);
    try {
      final fetched = await StandardsRegistry.fetchFromGist(_gistRawUrl);
      if (!mounted) return;
      setState(() {
        _availableStandards = fetched;
        _selectedStandard = fetched.firstWhere(
          (element) => element.id == _selectedStandard.id,
          orElse: () => fetched.first,
        );
      });
    } catch (e) {
      debugPrint('[Standards] Failed to sync standards: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to sync standards from cloud.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoadingCloudData = false);
      }
    }
  }

  void _scanAndConnect() {
    if (kIsWeb || _bleService == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Bluetooth BLE features require installing the mobile app (Android/iOS).",
          ),
        ),
      );
      return;
    }
    _bleService!.startScanAndConnect();
  }

  Future<void> _sendCalibrationCommand(String cmd) async {
    String msg = cmd == '1'
        ? "Position A recorded. Rotate the sensor 180 degrees."
        : (cmd == '2'
            ? "Calibration completed successfully!"
            : "Offsets reset.");

    try {
      if (_bleService != null && _isConnected) {
        await _bleService!.sendCommand(cmd);
      } else {
        msg = "Device not connected. Calibration command ignored.";
      }
    } catch (e) {
      msg = "Failed to send calibration command: $e";
      debugPrint('[BLE] Calibration write failed: $e');
    }

    if (!kIsWeb) await _ttsInstance?.speak(msg);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _captureMeasurement() async {
    bool isFree = _selectedStandard.isFreeMode;
    bool isCompliant = _selectedStandard.isCompliant(_pitch);

    final newItem = InspectionItem(
      pitch: _pitch,
      roll: _roll,
      standard: _selectedStandard,
      timestamp: DateTime.now(),
    );

    try {
      if (kIsWeb) {
        setState(() {
          _sessionLogs.add(newItem);
        });
      } else {
        await DatabaseHelper.instance.insertInspection(newItem);
        await _loadStoredInspections();
        String speechFeedback = isFree
            ? "Measured pitch: ${_pitch.abs().toStringAsFixed(1)} degrees."
            : (isCompliant
                ? "Measurement approved according to standard ${_selectedStandard.code}."
                : "Warning: Measurement non-compliant with standard.");
        await _ttsInstance?.speak(speechFeedback);
      }
    } catch (e) {
      debugPrint('[DB] Failed to persist measurement: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save measurement: $e')),
      );
      return;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          isFree
              ? "📐 FREE MEASUREMENT"
              : (isCompliant ? "✅ COMPLIANT" : "❌ NON-COMPLIANT"),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Applied Standard: ${_selectedStandard.code}"),
            const SizedBox(height: 8),
            Text("Measured Pitch: ${_pitch.toStringAsFixed(2)}°"),
            Text("Measured Roll: ${_roll.toStringAsFixed(2)}°"),
            if (_telemetry != null) ...[
              Text("Hardware Temp: ${_telemetry!.temperature.toStringAsFixed(1)}°C"),
              Text("Battery: ${_telemetry!.batteryLevel}%"),
            ],
            if (!isFree)
              Text("Standard Threshold: ${_selectedStandard.thresholdDeg}°"),
            const SizedBox(height: 12),
            Text(
              _selectedStandard.getStatusMessage(_pitch),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          )
        ],
      ),
    );
  }

  Future<void> _clearLogsHistory() async {
    try {
      if (kIsWeb) {
        setState(() {
          _sessionLogs.clear();
        });
      } else {
        await DatabaseHelper.instance.clearAllInspections();
        await _loadStoredInspections();
      }
    } catch (e) {
      debugPrint('[DB] Failed to clear history: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to clear history: $e')),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("History cleared successfully.")),
    );
  }

  Future<void> _generatePdfReport() async {
    try {
      if (kIsWeb) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "PDF report generation is available on the mobile application.",
            ),
          ),
        );
        return;
      }

      final formattedMeasurements = _sessionLogs.map((log) {
        return {
          'standard': log.standard.code,
          'pitch': "${log.pitch.toStringAsFixed(2)}°",
          'roll': "${log.roll.toStringAsFixed(2)}°",
          'compliance': log.standard.isFreeMode
              ? 'FREE'
              : (log.standard.isCompliant(log.pitch) ? 'PASS' : 'FAIL'),
        };
      }).toList();

      await PdfReportService.generateAndShareReport(
        projectName: "Field Audit A1",
        inspectorName: "Engineering Team",
        measurements: formattedMeasurements,
      );
    } catch (e) {
      debugPrint('[PDF] Report generation failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to generate report: $e')),
      );
    }
  }

  Future<void> _openCamera() async {
    final photoPath = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => CameraOverlayScreen(
          pitch: _pitch,
          roll: _roll,
          selectedStandard: _selectedStandard,
        ),
      ),
    );

    if (!mounted || photoPath == null) return;

    // Persist a forensic audit record linking the captured photo to the measurement
    try {
      await AuditRepository().insertAudit(
        AuditRecord(
          pitch: _pitch,
          roll: _roll,
          isCompliant: _selectedStandard.isCompliant(_pitch),
          gpsCoordinates: "Lat: -19.617, Long: -43.227",
          timestampUtc: DateTime.now().toUtc().toIso8601String(),
          imagePath: photoPath,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Audit photo captured & saved: $photoPath')),
      );
    } catch (e) {
      debugPrint('[Audit] Failed to persist audit record: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Photo captured but audit record failed: $e')),
      );
    }
  }

  /// Toggles speech recognition using Vosk
  Future<void> _listenVoice() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Voice recognition is available on the mobile application."),
        ),
      );
      return;
    }

    if (_voiceService.isListening) {
      await _voiceService.stopListening();
      setState(() {});
    } else {
      setState(() {});
      await _voiceService.startListening((recognizedText) {
        if (recognizedText.contains("measure") ||
            recognizedText.contains("capture") ||
            recognizedText.contains("check")) {
          _voiceService.stopListening();
          setState(() {});
          _captureMeasurement();
        }
      });
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isFree = _selectedStandard.isFreeMode;
    bool isCompliant = _selectedStandard.isCompliant(_pitch);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: Text("LAYLA (${_sessionLogs.length})"),
        backgroundColor: Colors.black,
        actions: [
          if (_sessionLogs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.white54),
              tooltip: "Clear History",
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text("Clear History"),
                    content: const Text(
                      "Are you sure you want to delete all saved measurements?",
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Cancel"),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _clearLogsHistory();
                        },
                        child: const Text(
                          "Delete",
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          IconButton(
            icon: Icon(
              Icons.picture_as_pdf,
              color: _sessionLogs.isEmpty ? Colors.white24 : Colors.redAccent,
            ),
            onPressed:
                _sessionLogs.isEmpty ? null : () => _generatePdfReport(),
          ),
          IconButton(
            icon: Icon(
              _isConnected
                  ? Icons.bluetooth_connected
                  : Icons.bluetooth_searching,
              color: _isConnected ? Colors.green : Colors.amber,
            ),
            onPressed: _scanAndConnect,
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<EngineeringStandard>(
                        value: _selectedStandard,
                        dropdownColor: const Color(0xFF222222),
                        isExpanded: true,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 15),
                        items: _availableStandards.map((std) {
                          return DropdownMenuItem<EngineeringStandard>(
                            value: std,
                            child: Text(
                              std.isFreeMode
                                  ? "📐 ${std.code} (${std.title})"
                                  : "${std.code} — ${std.title}",
                            ),
                          );
                        }).toList(),
                        onChanged: (newStd) {
                          if (newStd != null) {
                            setState(() => _selectedStandard = newStd);
                          }
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: _isLoadingCloudData
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.amber,
                          ),
                        )
                      : const Icon(Icons.cloud_sync, color: Colors.amber),
                  onPressed: _syncStandardsWithGist,
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Center(
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isFree
                                ? Colors.amber
                                : (isCompliant ? Colors.green : Colors.red),
                            width: 5,
                          ),
                          color: Colors.black45,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "${_pitch.toStringAsFixed(2)}°",
                              style: TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.bold,
                                color: isFree
                                    ? Colors.amber
                                    : (isCompliant ? Colors.green : Colors.red),
                              ),
                            ),
                            Text(
                              _selectedStandard.code,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "Roll: ${_roll.toStringAsFixed(2)}°",
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                              ),
                            ),
                            if (_telemetry != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                "🌡️ ${_telemetry!.temperature.toStringAsFixed(1)}°C | 🔋 ${_telemetry!.batteryLevel}%",
                                style: const TextStyle(
                                  color: Colors.white24,
                                  fontSize: 10,
                                ),
                              ),
                            ]
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        _selectedStandard.getStatusMessage(_pitch),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isFree
                              ? Colors.amberAccent
                              : (isCompliant
                                  ? Colors.greenAccent
                                  : Colors.redAccent),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ExpansionTile(
            title: const Text(
              "⚙️ Hardware Calibration (180°)",
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: () => _sendCalibrationCommand('1'),
                    child: const Text("Pos A"),
                  ),
                  ElevatedButton(
                    onPressed: () => _sendCalibrationCommand('2'),
                    child: const Text("Pos B (180°)"),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.redAccent),
                    onPressed: () => _sendCalibrationCommand('R'),
                  )
                ],
              ),
              const SizedBox(height: 6),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16, top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FloatingActionButton(
                  heroTag: "btn_mic",
                  backgroundColor: _voiceService.isListening ? Colors.red : Colors.blueGrey,
                  onPressed: _listenVoice,
                  child: Icon(
                    _voiceService.isListening ? Icons.mic : Icons.mic_none,
                    size: 26,
                  ),
                ),
                FloatingActionButton.large(
                  heroTag: "btn_check",
                  backgroundColor: Colors.amber[800],
                  onPressed: _captureMeasurement,
                  child: const Icon(Icons.check, size: 38, color: Colors.white),
                ),
                FloatingActionButton(
                  heroTag: "btn_camera",
                  backgroundColor: Colors.indigo,
                  onPressed: _openCamera,
                  child: const Icon(
                    Icons.camera_alt,
                    size: 26,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _telemetrySub?.cancel();
    _connectionSub?.cancel();
    _bleService?.dispose();
    _ttsInstance?.stop();
    _voiceService.dispose();
    _dspFilter.reset();
    super.dispose();
  }
}