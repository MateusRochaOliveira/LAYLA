// lib/screens/camera_overlay_screen.dart

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../engineering_standards.dart';

class CameraOverlayScreen extends StatefulWidget {
  final double pitch;
  final double roll;
  final EngineeringStandard selectedStandard;
  final String gpsCoordinates;

  const CameraOverlayScreen({
    super.key,
    required this.pitch,
    required this.roll,
    required this.selectedStandard,
    this.gpsCoordinates = "Lat: -19.617, Long: -43.227",
  });

  /// True when the current measurement is compliant with the selected standard.
  bool get isCompliant => selectedStandard.isCompliant(pitch);

  @override
  State<CameraOverlayScreen> createState() => _CameraOverlayScreenState();
}

class _CameraOverlayScreenState extends State<CameraOverlayScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isCapturing = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    setState(() {
      _hasError = false;
      _isInitialized = false;
    });

    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        _controller = CameraController(
          _cameras!.first,
          ResolutionPreset.high,
          enableAudio: false,
        );

        await _controller!.initialize();
        if (mounted) {
          setState(() {
            _isInitialized = true;
          });
        }
      } else {
        if (mounted) setState(() => _hasError = true);
      }
    } catch (e) {
      debugPrint('[Camera] Error initializing camera: $e');
      if (mounted) setState(() => _hasError = true);
    }
  }

  Future<void> _captureForensicPhoto() async {
    if (_controller == null || !_controller!.value.isInitialized || _isCapturing) {
      return;
    }

    setState(() => _isCapturing = true);

    try {
      final XFile photo = await _controller!.takePicture();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Forensic audit photo saved: ${photo.path}'),
            backgroundColor: Colors.green,
          ),
        );
        // Return the photo path (String) so the caller can persist it;
        // avoids importing dart:io so this screen stays web-compatible.
        Navigator.pop(context, photo.path);
      }
    } catch (e) {
      debugPrint('[Camera] Error capturing photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error capturing photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCapturing = false);
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.no_photography, color: Colors.white38, size: 64),
              const SizedBox(height: 16),
              const Text(
                'Camera unavailable',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _initializeCamera,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.amber),
        ),
      );
    }

    final String timestampUtc =
        DateTime.now().toUtc().toIso8601String().substring(0, 19);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Camera Viewfinder
          CameraPreview(_controller!),

          // 2. Forensic Metadata Stamp Overlay
          Positioned(
            left: 16,
            right: 16,
            top: 48,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: widget.isCompliant ? Colors.green : Colors.red,
                  width: 2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'LAYLA LEVEL PRO — AUDIT',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: widget.isCompliant ? Colors.green : Colors.red,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          widget.isCompliant ? 'COMPLIANT' : 'NON_COMPLIANT',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white24, height: 12),
                  Text(
                    'PITCH: ${widget.pitch.toStringAsFixed(2)}°  |  ROLL: ${widget.roll.toStringAsFixed(2)}°',
                    style: const TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'GPS: ${widget.gpsCoordinates}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  Text(
                    'UTC: $timestampUtc Z',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),

          // 3. Shutter Button
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: FloatingActionButton.large(
                backgroundColor: widget.isCompliant ? Colors.amber : Colors.red,
                onPressed: _isCapturing ? null : _captureForensicPhoto,
                child: _isCapturing
                    ? const CircularProgressIndicator(color: Colors.black)
                    : const Icon(Icons.camera_alt, color: Colors.black, size: 36),
              ),
            ),
          ),
        ],
      ),
    );
  }
}