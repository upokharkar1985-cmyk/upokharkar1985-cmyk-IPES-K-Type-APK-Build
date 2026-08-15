class LoggerFrame {
  final DateTime timestamp;
  final List<double?> channels;
  final double? batteryVoltage;
  final double? batteryPercent;
  final String powerSource;
  final double? sampleRate;
  final double? memoryKb;

  const LoggerFrame({
    required this.timestamp,
    required this.channels,
    this.batteryVoltage,
    this.batteryPercent,
    this.powerSource = 'UNKNOWN',
    this.sampleRate,
    this.memoryKb,
  });

  factory LoggerFrame.empty() => LoggerFrame(
        timestamp: DateTime.now(),
        channels: List<double?>.filled(8, null),
      );

  factory LoggerFrame.parse(String line) {
    final text = line.trim();
    final values = <String, String>{};

    if (text.startsWith('{') && text.endsWith('}')) {
      final body = text.substring(1, text.length - 1);
      for (final part in body.split(',')) {
        final i = part.indexOf(':');
        if (i <= 0) continue;
        final k = part.substring(0, i).replaceAll(RegExp(r'["\s]'), '').toUpperCase();
        final v = part.substring(i + 1).replaceAll(RegExp(r'["\s]'), '');
        values[k] = v;
      }
    } else {
      for (final part in text.split('&')) {
        final i = part.indexOf('_');
        if (i <= 0) continue;
        values[part.substring(0, i).trim().toUpperCase()] = part.substring(i + 1).trim();
      }
    }

    double? number(String key) => double.tryParse(values[key] ?? '');
    final channels = List<double?>.generate(8, (i) => number('V${i + 1}'));
    final power = (values['PWR'] ?? values['POWER'] ?? values['SOURCE'] ?? 'UNKNOWN').toUpperCase();

    return LoggerFrame(
      timestamp: DateTime.now(),
      channels: channels,
      batteryVoltage: number('BVOLT') ?? number('BATV'),
      batteryPercent: number('BCAP') ?? number('BATSOC'),
      powerSource: power,
      sampleRate: number('SRATE') ?? number('SPS'),
      memoryKb: number('MEMKB') ?? number('MEM') ?? number('MEMORY'),
    );
  }
}
