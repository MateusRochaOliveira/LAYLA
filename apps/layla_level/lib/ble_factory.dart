import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

/// Factory responsible for ensuring the native BLE instance 
/// is NEVER loaded or instantiated in Web environments.
class BleFactory {
  static FlutterReactiveBle? _bleInstance;

  static FlutterReactiveBle? get instance {
    if (kIsWeb) {
      return null; // Returns null in Web without triggering static BLE loaders
    }
    
    // Lazy instantiation strictly for Mobile platforms (Android/iOS)
    _bleInstance ??= FlutterReactiveBle();
    return _bleInstance;
  }
}