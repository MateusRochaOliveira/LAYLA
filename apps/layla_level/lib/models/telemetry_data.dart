// lib/models/telemetry_data.dart

class TelemetryData {
  final double pitch;
  final double roll;
  final double temperature;
  final int batteryLevel;
  final bool isCalibrated;
  final bool isHardwareStable;
  final DateTime timestamp;

  const TelemetryData({
    required this.pitch,
    required this.roll,
    required this.temperature,
    required this.batteryLevel,
    required this.isCalibrated,
    required this.isHardwareStable,
    required this.timestamp,
  });

  @override
  String toString() {
    return 'TelemetryData(Pitch: ${pitch.toStringAsFixed(2)}°, Roll: ${roll.toStringAsFixed(2)}°, Temp: ${temperature.toStringAsFixed(1)}°C, Bat: $batteryLevel%)';
  }
}