import '../models/telemetry_data.dart';

/// Filtro DSP de Borda (Low-Pass Exponential Smoothing)
/// Suaviza oscilações de vibração mecânica de obras mantendo resposta rápida
class ComplementaryDspFilter {
  final double alpha; // Fator de suavização (0.0 a 1.0)
  
  double? _filteredPitch;
  double? _filteredRoll;

  /// [alpha] de 0.1 a 0.2 entrega excelente remoção de ruído mecânico a 10 Hz
  ComplementaryDspFilter({this.alpha = 0.15});

  TelemetryData process(TelemetryData raw) {
    if (_filteredPitch == null || _filteredRoll == null) {
      _filteredPitch = raw.pitch;
      _filteredRoll = raw.roll;
    } else {
      // Fórmula: y[k] = alpha * x[k] + (1 - alpha) * y[k-1]
      _filteredPitch = (alpha * raw.pitch) + ((1.0 - alpha) * _filteredPitch!);
      _filteredRoll = (alpha * raw.roll) + ((1.0 - alpha) * _filteredRoll!);
    }

    return TelemetryData(
      pitch: _filteredPitch!,
      roll: _filteredRoll!,
      temperature: raw.temperature,
      batteryLevel: raw.batteryLevel,
      isCalibrated: raw.isCalibrated,
      isHardwareStable: raw.isHardwareStable,
      timestamp: raw.timestamp,
    );
  }

  void reset() {
    _filteredPitch = null;
    _filteredRoll = null;
  }
}