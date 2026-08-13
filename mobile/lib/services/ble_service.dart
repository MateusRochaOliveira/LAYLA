import 'dart:async';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

class BleService {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;

  // UUIDs do seu ESP32 (substitua pelos UUIDs do seu firmware)
  final Uuid serviceUuid = Uuid.parse("4fafc201-1fb5-459e-8fcc-c5c9c331914b");
  final Uuid characteristicUuid = Uuid.parse("beb5483e-36e1-4688-b7f5-ea07361b26a8");

  // Pedir permissões do Android
  Future<bool> requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    return statuses.values.every((status) => status.isGranted);
  }

  // Buscar dispositivos LAYLA
  void startScan(Function(DiscoveredDevice) onDeviceFound) async {
    bool hasPermission = await requestPermissions();
    if (!hasPermission) return;

    _scanSubscription?.cancel();
    _scanSubscription = _ble.scanForDevices(
      withServices: [serviceUuid],
      scanMode: ScanMode.lowLatency,
    ).listen((device) {
      if (device.name.contains("LAYLA")) {
        onDeviceFound(device);
      }
    });
  }

  // Parar busca
  void stopScan() {
    _scanSubscription?.cancel();
  }

  // Conectar ao ESP32
  void connect(String deviceId, Function(bool) onConnectionChanged) {
    stopScan();
    _connectionSubscription?.cancel();
    _connectionSubscription = _ble.connectToDevice(
      id: deviceId,
      connectionTimeout: const Duration(seconds: 5),
    ).listen((connectionState) {
      bool isConnected = connectionState.connectionState == DeviceConnectionState.connected;
      onConnectionChanged(isConnected);
    });
  }

  // Desconectar e limpar da memória
  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
  }
}