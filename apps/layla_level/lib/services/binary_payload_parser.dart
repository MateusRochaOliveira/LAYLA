// lib/services/binary_payload_parser.dart

import 'dart:typed_data';
import '../models/telemetry_data.dart';

class BinaryPayloadParser {
  static const int expectedLength = 12;

  static TelemetryData parse(List<int> rawBytes) {
    if (rawBytes.length < expectedLength) {
      throw FormatException(
        'Payload BLE inválido: esperado $expectedLength bytes, recebido ${rawBytes.length}',
      );
    }

    final byteData = ByteData.sublistView(Uint8List.fromList(rawBytes));

    final int rawPitch = byteData.getInt16(0, Endian.little);
    final int rawRoll = byteData.getInt16(2, Endian.little);
    final int rawTemp = byteData.getInt16(4, Endian.little);

    final double pitch = rawPitch / 100.0;
    final double roll = rawRoll / 100.0;
    final double temperature = rawTemp / 100.0;

    final int battery = byteData.getUint8(6).clamp(0, 100);
    final int flags = byteData.getUint8(7);

    final bool isCalibrated = (flags & 0x01) != 0;
    final bool isHardwareStable = (flags & 0x02) != 0;

    return TelemetryData(
      pitch: pitch,
      roll: roll,
      temperature: temperature,
      batteryLevel: battery,
      isCalibrated: isCalibrated,
      isHardwareStable: isHardwareStable,
      timestamp: DateTime.now(),
    );
  }
}