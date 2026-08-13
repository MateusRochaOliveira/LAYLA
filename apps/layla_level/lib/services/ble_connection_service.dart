// lib/services/ble_connection_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import '../models/telemetry_data.dart';
import 'binary_payload_parser.dart';

/// Service managing BLE connectivity, scanning, GATT characteristic subscription,
/// and 10 Hz telemetry streaming for LAYLA Level Pro.
class BleConnectionService {
  final FlutterReactiveBle _ble = FlutterReactiveBle();

  // GATT UUIDs matching the ESP32 firmware configuration
  final Uuid serviceUuid;
  final Uuid characteristicUuid;

  BleConnectionService({
    String? serviceUuid,
    String? characteristicUuid,
  })  : serviceUuid = Uuid.parse(serviceUuid ?? "4fa12345-1234-1234-1234-123456789abc"),
        characteristicUuid = Uuid.parse(
            characteristicUuid ?? "beb54321-1234-1234-1234-123456789abc");

  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription<List<int>>? _notificationSubscription;

  final _telemetryController = StreamController<TelemetryData>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();

  /// Stream emitting parsed telemetry payloads at 10 Hz
  Stream<TelemetryData> get telemetryStream => _telemetryController.stream;

  /// Stream emitting connection state changes (true = connected)
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  String? _connectedDeviceId;

  /// Starts scanning for the ESP32 hardware and connects automatically upon discovery
  void startScanAndConnect({String deviceName = "LAYLA_LEVEL_ESP32"}) {
    if (_isScanning || _isConnected) return;
    _isScanning = true;
    debugPrint('[BLE] Starting discovery scan for LAYLA hardware...');

    _scanSubscription?.cancel();
    _scanSubscription = _ble.scanForDevices(
      withServices: [serviceUuid],
      scanMode: ScanMode.lowLatency,
    ).listen((device) {
      if (device.name == deviceName || device.serviceUuids.contains(serviceUuid)) {
        debugPrint('[BLE] Found device: ${device.id}. Connecting...');
        _scanSubscription?.cancel();
        _isScanning = false;
        _connectToDevice(device.id);
      }
    }, onError: (error) {
      _isScanning = false;
      debugPrint('[BLE] Scan error encountered: $error');
    });
  }

  /// Establishes GATT connection with target device ID
  void _connectToDevice(String deviceId) {
    _connectionSubscription?.cancel();
    _connectionSubscription = _ble
        .connectToDevice(
      id: deviceId,
      connectionTimeout: const Duration(seconds: 10),
    )
        .listen((connectionState) {
      debugPrint('[BLE] Connection state updated: ${connectionState.connectionState}');

      if (connectionState.connectionState == DeviceConnectionState.connected) {
        _isConnected = true;
        _connectedDeviceId = deviceId;
        _connectionStateController.add(true);
        _subscribeToTelemetry(deviceId);
      } else if (connectionState.connectionState == DeviceConnectionState.disconnected) {
        _isConnected = false;
        _connectionStateController.add(false);
        debugPrint('[BLE] Disconnected from hardware. Initiating auto-reconnect...');
        startScanAndConnect();
      }
    }, onError: (error) {
      _isConnected = false;
      _connectionStateController.add(false);
      debugPrint('[BLE] Connection error: $error');
    });
  }

  /// Subscribes to the GATT notification stream delivering 12-byte binary payloads at 10 Hz
  void _subscribeToTelemetry(String deviceId) {
    final characteristic = QualifiedCharacteristic(
      serviceId: serviceUuid,
      characteristicId: characteristicUuid,
      deviceId: deviceId,
    );

    _notificationSubscription?.cancel();
    _notificationSubscription = _ble.subscribeToCharacteristic(characteristic).listen(
      (rawBytes) {
        try {
          // Decode 12-byte raw binary payload using BinaryPayloadParser
          final telemetry = BinaryPayloadParser.parse(rawBytes);
          _telemetryController.add(telemetry);
        } catch (e) {
          debugPrint('[BLE] Failed to parse incoming telemetry payload: $e');
        }
      },
      onError: (error) {
        debugPrint('[BLE] GATT characteristic notification error: $error');
      },
    );
  }

  /// Sends a raw command string to the device (e.g., calibration commands).
  /// Throws [StateError] if not connected.
  Future<void> sendCommand(String command) async {
    if (!_isConnected || _connectedDeviceId == null) {
      throw StateError('BLE not connected');
    }
    final characteristic = QualifiedCharacteristic(
      serviceId: serviceUuid,
      characteristicId: characteristicUuid,
      deviceId: _connectedDeviceId!,
    );
    await _ble.writeCharacteristicWithResponse(
      characteristic,
      value: command.codeUnits,
    );
  }

  /// Cancels active subscriptions and frees BLE resources
  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _notificationSubscription?.cancel();
    if (!_telemetryController.isClosed) _telemetryController.close();
    if (!_connectionStateController.isClosed) _connectionStateController.close();
    _isConnected = false;
    _isScanning = false;
    _connectedDeviceId = null;
  }
}