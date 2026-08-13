import 'dart:convert';
import 'package:http/http.dart' as http;

class EngineeringStandard {
  final String id;
  final String code;
  final String title;
  final double thresholdDeg;
  final bool isFreeMode;

  const EngineeringStandard({
    required this.id,
    required this.code,
    required this.title,
    required this.thresholdDeg,
    this.isFreeMode = false,
  });

  bool isCompliant(double pitch) {
    if (isFreeMode) return true;
    return pitch.abs() <= thresholdDeg;
  }

  String getStatusMessage(double pitch) {
    if (isFreeMode) return "Free measurement mode (No limit)";
    bool ok = isCompliant(pitch);
    return ok 
        ? "COMPLIANT: ${pitch.abs().toStringAsFixed(2)}° <= $thresholdDeg° ($code)" 
        : "NON-COMPLIANT: Exceeds limit of $thresholdDeg° ($code)";
  }

  factory EngineeringStandard.fromJson(Map<String, dynamic> json) {
    return EngineeringStandard(
      id: json['id'] ?? 'FREE',
      code: json['code'] ?? 'FREE',
      title: json['title'] ?? 'Free Mode',
      thresholdDeg: (json['thresholdDeg'] as num?)?.toDouble() ?? 0.0,
      isFreeMode: json['isFreeMode'] ?? false,
    );
  }
}

class StandardsRegistry {
  static const List<EngineeringStandard> defaultStandards = [
    EngineeringStandard(
      id: "FREE",
      code: "FREE",
      title: "Free Measurement Mode",
      thresholdDeg: 0.0,
      isFreeMode: true,
    ),
    EngineeringStandard(
      id: "NBR_9050_RAMPS",
      code: "NBR 9050",
      title: "Accessibility Ramps (Max 8.33%)",
      thresholdDeg: 4.76,
      isFreeMode: false,
    ),
  ];

  static Future<List<EngineeringStandard>> fetchFromGist(String rawGistUrl) async {
    try {
      final response = await http.get(Uri.parse(rawGistUrl)).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);
        return jsonList.map((j) => EngineeringStandard.fromJson(j)).toList();
      }
    } catch (_) {}
    return defaultStandards;
  }
}