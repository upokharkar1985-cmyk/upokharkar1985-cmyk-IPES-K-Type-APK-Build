import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/channel_config.dart';
import 'models/logger_frame.dart';
import 'services/config_service.dart';
import 'services/csv_logger.dart';
import 'services/serial_service.dart';
import 'widgets/channel_tile.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const IpesLoggerApp());
}

class IpesLoggerApp extends StatelessWidget {
  const IpesLoggerApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'IPES 8CH Data Logger',
        theme: ThemeData.dark(useMaterial3: true).copyWith(
          scaffoldBackgroundColor: const Color(0xFF0B1118),
          colorScheme: const ColorScheme.dark(primary: Color(0xFF2E9BFF), secondary: Color(0xFF35D07F)),
        ),
        home: const DashboardPage(),
      );
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final SerialService serial = SerialService();
  final CsvLogger logger = CsvLogger();
  LoggerFrame frame = LoggerFrame.empty();
  List<ChannelConfig> configs = List.generate(8, (i) => ChannelConfig(name: 'Channel ${i + 1}', unit: 'V'));
  StreamSubscription? frameSub;
  StreamSubscription? statusSub;
  String usbStatus = 'STARTING';
  int page = 0;
  final history = List.generate(8, (_) => <double>[]);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    configs = await ConfigService.load();
    statusSub = serial.statusController.stream.listen((s) {
      if (mounted) setState(() => usbStatus = s);
    });
    frameSub = serial.frameController.stream.listen((f) {
      if (logger.active) logger.add(f, configs);
      for (var i = 0; i < 8; i++) {
        final v = configs[i].apply(f.channels[i]);
        if (v != null) {
          history[i].add(v);
          if (history[i].length > 120) history[i].removeAt(0);
        }
      }
      if (mounted) setState(() => frame = f);
    });
    await serial.start();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    frameSub?.cancel();
    statusSub?.cancel();
    logger.stop();
    serial.dispose();
    super.dispose();
  }

  Future<void> _toggleRecord() async {
    if (logger.active) {
      await logger.stop();
    } else {
      await logger.start(configs);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          _topBar(),
          Expanded(
            child: Row(children: [
              _nav(),
              Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(8, 6, 10, 8), child: _page())),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _topBar() => Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        color: const Color(0xFF101923),
        child: Row(children: [
          const Text('IPES', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFF2E9BFF), letterSpacing: 1.2)),
          const SizedBox(width: 12),
          const Text('8 CHANNEL ANALOG DATA LOGGER', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const Spacer(),
          _statusChip(Icons.usb, usbStatus, usbStatus == 'CONNECTED'),
          const SizedBox(width: 8),
          _statusChip(Icons.power, frame.powerSource == 'UNKNOWN' ? 'POWER --' : frame.powerSource, frame.powerSource.contains('MAIN')),
          const SizedBox(width: 8),
          _statusChip(Icons.battery_5_bar, frame.batteryPercent == null ? 'BAT --' : '${frame.batteryPercent!.toStringAsFixed(0)}%', (frame.batteryPercent ?? 100) > 20),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _toggleRecord,
            icon: Icon(logger.active ? Icons.stop_circle : Icons.fiber_manual_record, size: 18),
            label: Text(logger.active ? 'STOP' : 'RECORD'),
            style: FilledButton.styleFrom(backgroundColor: logger.active ? const Color(0xFFD94A4A) : const Color(0xFF1D8A54)),
          ),
        ]),
      );

  Widget _statusChip(IconData icon, String text, bool ok) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(color: ok ? const Color(0xFF123B2B) : const Color(0xFF252B32), borderRadius: BorderRadius.circular(8)),
        child: Row(children: [Icon(icon, size: 16, color: ok ? const Color(0xFF55D790) : Colors.white54), const SizedBox(width: 5), Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))]),
      );

  Widget _nav() => Container(
        width: 82,
        color: const Color(0xFF0F1720),
        child: Column(children: [
          _navButton(0, Icons.dashboard, 'LIVE'),
          _navButton(1, Icons.show_chart, 'GRAPH'),
          _navButton(2, Icons.tune, 'SETUP'),
          const Spacer(),
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('v1.0', style: TextStyle(fontSize: 10, color: Colors.grey.shade600))),
        ]),
      );

  Widget _navButton(int index, IconData icon, String label) => InkWell(
        onTap: () => setState(() => page = index),
        child: Container(
          height: 72,
          color: page == index ? const Color(0xFF17314A) : Colors.transparent,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: page == index ? const Color(0xFF55B6FF) : Colors.white54), const SizedBox(height: 4), Text(label, style: TextStyle(fontSize: 10, color: page == index ? Colors.white : Colors.white54))]),
        ),
      );

  Widget _page() {
    if (page == 1) return _graphs();
    if (page == 2) return _settings();
    return _live();
  }

  Widget _live() => Column(children: [
        Expanded(
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 3.35, crossAxisSpacing: 8, mainAxisSpacing: 8),
            itemCount: 8,
            itemBuilder: (_, i) => ChannelTile(number: i + 1, name: configs[i].name, unit: configs[i].unit, value: configs[i].apply(frame.channels[i])),
          ),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Text('Battery: ${frame.batteryVoltage?.toStringAsFixed(2) ?? '--'} V', style: const TextStyle(fontSize: 11, color: Colors.white60)),
          const SizedBox(width: 18),
          Text('Sample: ${frame.sampleRate?.toStringAsFixed(0) ?? '--'} sps', style: const TextStyle(fontSize: 11, color: Colors.white60)),
          const Spacer(),
          Text(logger.active ? 'Saving: ${logger.currentFile?.path.split('/').last ?? ''}' : 'Local CSV recording stopped', style: TextStyle(fontSize: 10, color: logger.active ? const Color(0xFF55D790) : Colors.white38)),
        ]),
      ]);

  Widget _graphs() => GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 2.5, crossAxisSpacing: 8, mainAxisSpacing: 8),
        itemCount: 8,
        itemBuilder: (_, i) => Container(
          decoration: BoxDecoration(color: const Color(0xFF151D27), borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.all(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('CH${i + 1}  ${configs[i].name}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            Expanded(child: CustomPaint(painter: _MiniGraphPainter(history[i]), child: const SizedBox.expand())),
          ]),
        ),
      );

  Widget _settings() => ListView.builder(
        itemCount: 8,
        itemBuilder: (_, i) => Card(
          color: const Color(0xFF151D27),
          child: ListTile(
            dense: true,
            leading: CircleAvatar(backgroundColor: const Color(0xFF203247), child: Text('${i + 1}')),
            title: Text(configs[i].name),
            subtitle: Text('Unit ${configs[i].unit}   Scale ${configs[i].scale}   Offset ${configs[i].offset}'),
            trailing: const Icon(Icons.edit, size: 18),
            onTap: () => _editChannel(i),
          ),
        ),
      );

  Future<void> _editChannel(int i) async {
    final name = TextEditingController(text: configs[i].name);
    final unit = TextEditingController(text: configs[i].unit);
    final scale = TextEditingController(text: configs[i].scale.toString());
    final offset = TextEditingController(text: configs[i].offset.toString());
    final result = await showDialog<ChannelConfig>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Channel ${i + 1} setup'),
        content: SizedBox(
          width: 420,
          child: Row(children: [
            Expanded(child: TextField(controller: name, decoration: const InputDecoration(labelText: 'Name'))),
            const SizedBox(width: 8),
            SizedBox(width: 80, child: TextField(controller: unit, decoration: const InputDecoration(labelText: 'Unit'))),
            const SizedBox(width: 8),
            SizedBox(width: 90, child: TextField(controller: scale, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Scale'))),
            const SizedBox(width: 8),
            SizedBox(width: 90, child: TextField(controller: offset, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Offset'))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          FilledButton(
            onPressed: () => Navigator.pop(context, ChannelConfig(name: name.text.trim().isEmpty ? 'Channel ${i + 1}' : name.text.trim(), unit: unit.text.trim().isEmpty ? 'V' : unit.text.trim(), scale: double.tryParse(scale.text) ?? 1.0, offset: double.tryParse(offset.text) ?? 0.0)),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
    if (result != null) {
      configs[i] = result;
      await ConfigService.save(i, result);
      if (mounted) setState(() {});
    }
  }
}

class _MiniGraphPainter extends CustomPainter {
  final List<double> values;
  _MiniGraphPainter(this.values);
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = const Color(0xFF25303B)..strokeWidth = 1;
    for (var y = 1; y < 4; y++) canvas.drawLine(Offset(0, size.height * y / 4), Offset(size.width, size.height * y / 4), grid);
    if (values.length < 2) return;
    var min = values.reduce((a, b) => a < b ? a : b);
    var max = values.reduce((a, b) => a > b ? a : b);
    if ((max - min).abs() < 1e-9) { min -= 1; max += 1; }
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height - (values[i] - min) / (max - min) * size.height;
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    canvas.drawPath(path, Paint()..color = const Color(0xFF2E9BFF)..strokeWidth = 1.8..style = PaintingStyle.stroke);
  }
  @override
  bool shouldRepaint(covariant _MiniGraphPainter oldDelegate) => true;
}
