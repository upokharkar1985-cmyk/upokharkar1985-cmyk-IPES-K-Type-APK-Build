import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/logger_frame.dart';
import '../models/channel_config.dart';

class CsvLogger {
  IOSink? _sink;
  File? currentFile;
  bool get active => _sink != null;

  Future<File> start(List<ChannelConfig> configs) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/IPES_8CH_LOGS');
    await folder.create(recursive: true);
    final now = DateTime.now();
    final stamp = '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final file = File('${folder.path}/IPES_8CH_$stamp.csv');
    _sink = file.openWrite();
    currentFile = file;
    _sink!.writeln(['Timestamp', ...configs.map((c) => '${c.name} (${c.unit})'), 'Battery V', 'Battery %', 'Power Source'].join(','));
    return file;
  }

  void add(LoggerFrame frame, List<ChannelConfig> configs) {
    if (_sink == null) return;
    final values = <String>[frame.timestamp.toIso8601String()];
    for (var i = 0; i < 8; i++) {
      final v = configs[i].apply(frame.channels[i]);
      values.add(v?.toStringAsFixed(6) ?? '');
    }
    values.add(frame.batteryVoltage?.toStringAsFixed(3) ?? '');
    values.add(frame.batteryPercent?.toStringAsFixed(1) ?? '');
    values.add(frame.powerSource);
    _sink!.writeln(values.join(','));
  }

  Future<void> stop() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
  }
}
