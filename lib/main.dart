import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/channel_config.dart';
import 'models/logger_frame.dart';
import 'services/config_service.dart';
import 'services/csv_logger.dart';
import 'services/serial_service.dart';

const _gold = Color(0xFFFFD765);
const _goldDark = Color(0xFFE7B93A);
const _blue = Color(0xFF0099D5);
const _ink = Color(0xFF111111);
const _border = Color(0xFF5D8FB9);
const _field = Color(0xFFF9D8C4);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const IpesLoggerApp());
}

class IpesLoggerApp extends StatelessWidget {
  const IpesLoggerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'IPES 8CH Data Logger',
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          colorScheme: ColorScheme.fromSeed(seedColor: _goldDark),
          fontFamily: 'Roboto',
          scaffoldBackgroundColor: Colors.white,
          inputDecorationTheme: InputDecorationTheme(
            isDense: true,
            filled: true,
            fillColor: _field,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(2),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          ),
        ),
        home: const LoggerShell(),
      );
}

enum LoggerPage {
  home,
  experiment,
  digitalReadout,
  scope,
  peak,
  historical,
  setting,
  calibration,
  memory,
  recording,
}

class LoggerShell extends StatefulWidget {
  const LoggerShell({super.key});

  @override
  State<LoggerShell> createState() => _LoggerShellState();
}

class _LoggerShellState extends State<LoggerShell> {
  final SerialService serial = SerialService();
  final CsvLogger csv = CsvLogger();

  LoggerFrame frame = LoggerFrame.empty();
  List<ChannelConfig> configs = List.generate(
    8,
    (i) => ChannelConfig(name: 'Channel ${i + 1}', unit: 'V'),
  );
  AppSettings settings = const AppSettings();
  ExperimentInfo experiment = const ExperimentInfo();

  final history = List.generate(8, (_) => <double>[]);
  final peaks = List<double?>.filled(8, null);
  final scopeSelected = List<bool>.filled(8, true);
  bool scopePlaying = true;
  bool scopeMaximized = false;
  String usbStatus = 'STARTING';
  LoggerPage page = LoggerPage.home;
  StreamSubscription? _frameSub;
  StreamSubscription? _statusSub;
  Timer? _clock;
  bool _blink = false;

  final _expTestName = TextEditingController();
  final _expPlace = TextEditingController();
  final _expOperator = TextEditingController();
  final _expContact = TextEditingController();
  final _expEmail = TextEditingController();
  final _expRemark = TextEditingController();
  final _expTestRemark = TextEditingController();

  static const parameters = [
    'Displacement', 'Distance', 'RPM', 'Temperature', 'Force', 'Weight',
    'Pressure', 'Strain', 'Humidity', 'Flow', 'Current', 'Voltage', 'Angle',
    'Acceleration', 'Volume', 'Angular Velocity', 'Speed', 'Torque',
    'Resistance', 'Consumption', 'Density', 'Power', 'Sound', 'Mileage', 'Others',
  ];

  static const units = [
    'mm', 'meter', 'cm', 'RPM', 'gram', 'Km', 'kN', 'C', 'Kg', 'mV', 'F', 'N', 'ms',
    'Volt', '%', 'Deg', 'psi', 'mA', 'watt', 'bar', 'Ampere', 'Kilowatt', 'N.m.', 'Kpa',
    'ml/s', 'ml/h', 'dB', 'ml/m', 'Km/h', 'rad/s', 'gm/ml', 'ohm', 'm3', 'g', 'm/s2',
    'km/l', 'Other'
  ];

  @override
  void initState() {
    super.initState();
    _initialize();
    _clock = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      setState(() => _blink = !_blink);
    });
  }

  Future<void> _initialize() async {
    configs = await ConfigService.load();
    settings = await ConfigService.loadAppSettings();
    experiment = await ConfigService.loadExperiment();
    _expTestName.text = experiment.testName;
    _expPlace.text = experiment.testPlace;
    _expOperator.text = experiment.operatorName;
    _expContact.text = experiment.operatorContact;
    _expEmail.text = experiment.operatorEmail;
    _expRemark.text = experiment.remark;
    _expTestRemark.text = experiment.testRemark;
    _statusSub = serial.statusController.stream.listen((s) {
      if (mounted) setState(() => usbStatus = s);
    });
    _frameSub = serial.frameController.stream.listen((f) {
      if (csv.active) csv.add(f, configs);
      frame = f;
      for (var i = 0; i < 8; i++) {
        final v = configs[i].apply(f.channels[i]);
        if (v == null) continue;
        if (scopePlaying) {
          history[i].add(v);
          if (history[i].length > 240) history[i].removeAt(0);
        }
        final peak = peaks[i];
        if (peak == null || v.abs() > peak.abs()) peaks[i] = v;
      }
      if (mounted) setState(() {});
    });
    await serial.start();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _clock?.cancel();
    _frameSub?.cancel();
    _statusSub?.cancel();
    csv.stop();
    serial.dispose();
    _expTestName.dispose();
    _expPlace.dispose();
    _expOperator.dispose();
    _expContact.dispose();
    _expEmail.dispose();
    _expRemark.dispose();
    _expTestRemark.dispose();
    super.dispose();
  }

  String _value(int i) {
    final v = configs[i].apply(frame.channels[i]);
    return v == null ? '--' : v.toStringAsFixed(settings.decimals);
  }

  String _peak(int i) {
    final v = peaks[i];
    return v == null ? '--' : v.toStringAsFixed(settings.decimals);
  }

  String _dateText() {
    final d = DateTime.now();
    return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
  }

  String _timeText() {
    final d = DateTime.now();
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: _watermark()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  _header(),
                  const SizedBox(height: 5),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _navigation(),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.94),
                              border: Border.all(color: _border, width: 1.2),
                            ),
                            child: _pageBody(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 3,
            child: IgnorePointer(
              child: Text(
                'IPES',
                style: TextStyle(
                  color: _blue.withOpacity(0.95),
                  fontSize: 29,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _watermark() => Container(
        color: Colors.white,
        child: Center(
          child: Transform.scale(
            scale: 1.4,
            child: Icon(Icons.two_wheeler, size: 330, color: _blue.withOpacity(0.035)),
          ),
        ),
      );

  Widget _header() => SizedBox(
        height: 42,
        child: Row(
          children: [
            _goldBox('Date : ${_dateText()}', width: 128, center: true),
            const SizedBox(width: 7),
            Expanded(
              child: GestureDetector(
                onTap: _editLoggerName,
                child: Container(
                  height: 42,
                  color: _gold,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    settings.loggerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 7),
            _goldBox('Time : ${_timeText()}', width: 128, center: true),
          ],
        ),
      );

  Widget _navigation() {
    final memory = frame.memoryKb == null ? 'MEMORY' : 'MEMORY\n${frame.memoryKb!.toStringAsFixed(0)} kb';
    return SizedBox(
      width: 142,
      child: Column(
        children: [
          Row(
            children: [
              _iconNav(Icons.home, () => setState(() => page = LoggerPage.home)),
              const SizedBox(width: 5),
              _iconNav(Icons.arrow_back, () => setState(() => page = LoggerPage.home)),
            ],
          ),
          const SizedBox(height: 4),
          _menuButton(LoggerPage.experiment, 'EXPERIMENT'),
          _menuButton(LoggerPage.digitalReadout, 'DIGITAL READ OUT'),
          _menuButton(LoggerPage.scope, 'SCOPE PLOT'),
          _menuButton(LoggerPage.peak, 'PEAK VALUES'),
          _menuButton(LoggerPage.historical, 'HISTORICAL GRAPH'),
          _menuButton(LoggerPage.setting, 'SETTING'),
          _menuButton(LoggerPage.calibration, 'CALIBRATION'),
          _menuButton(LoggerPage.memory, memory),
          _menuButton(LoggerPage.recording, 'Data Recording'),
          const Spacer(),
          Container(
            width: double.infinity,
            height: 29,
            color: _gold,
            alignment: Alignment.center,
            child: const Text('IPES', style: TextStyle(color: _blue, fontWeight: FontWeight.w900, fontSize: 20)),
          ),
        ],
      ),
    );
  }

  Widget _iconNav(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 29,
          color: const Color(0xFFE6EEF5),
          alignment: Alignment.center,
          child: Icon(icon, size: 19, color: const Color(0xFF34495E)),
        ),
      );

  Widget _menuButton(LoggerPage target, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: InkWell(
          onTap: () => setState(() => page = target),
          child: Container(
            height: label.contains('\n') ? 42 : 32,
            width: double.infinity,
            color: page == target ? const Color(0xFFFFC83D) : _gold,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              style: const TextStyle(color: _ink, fontSize: 10.5, fontWeight: FontWeight.w600, height: 1.15),
            ),
          ),
        ),
      );

  Widget _pageBody() {
    switch (page) {
      case LoggerPage.experiment:
        return _experimentPage();
      case LoggerPage.digitalReadout:
        return _digitalPage();
      case LoggerPage.scope:
        return _scopePage();
      case LoggerPage.peak:
        return _peakPage();
      case LoggerPage.historical:
        return _historicalPage();
      case LoggerPage.setting:
        return _settingsPage();
      case LoggerPage.calibration:
        return _calibrationPage();
      case LoggerPage.memory:
        return _memoryPage();
      case LoggerPage.recording:
        return _recordingPage();
      case LoggerPage.home:
        return _homePage();
    }
  }

  Widget _homePage() => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('IPES 8 CHANNEL ANALOG DATA LOGGER', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Row(
              children: [
                _infoCard('USB', usbStatus, usbStatus == 'CONNECTED' ? Colors.green : Colors.orange),
                _infoCard('POWER', frame.powerSource == 'UNKNOWN' ? '--' : frame.powerSource, Colors.blue),
                _infoCard('BATTERY', frame.batteryPercent == null ? '--' : '${frame.batteryPercent!.toStringAsFixed(0)}%', Colors.green),
                _infoCard('SAMPLE', '${frame.sampleRate?.toStringAsFixed(0) ?? settings.sampleRate} Hz', Colors.deepPurple),
              ],
            ),
            const SizedBox(height: 14),
            const Text('Select a function from the left menu.', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 8),
            const Text('The display layout follows the supplied 5-inch IPES HMI concept and is fixed to exactly 8 analog channels.', style: TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
      );

  Widget _infoCard(String title, String value, Color color) => Expanded(
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: color.withOpacity(0.09), border: Border.all(color: color.withOpacity(0.35))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 10, color: Colors.black54)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
          ]),
        ),
      );

  Widget _experimentPage() {
    return StatefulBuilder(
      builder: (context, localSet) => SingleChildScrollView(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('New Experiment'),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _labeledField('Test Date', _dateText(), readOnly: true)),
              const SizedBox(width: 10),
              Expanded(child: _labeledController('Test Name', _expTestName)),
            ]),
            const SizedBox(height: 7),
            Row(children: [
              Expanded(child: _labeledController('Test Place', _expPlace)),
              const SizedBox(width: 10),
              Expanded(child: _labeledController('Operator Name', _expOperator)),
            ]),
            const SizedBox(height: 7),
            Row(children: [
              Expanded(child: _labeledController('Operator Contact No', _expContact, keyboard: TextInputType.phone)),
              const SizedBox(width: 10),
              Expanded(child: _labeledController('Operator email ID', _expEmail, keyboard: TextInputType.emailAddress)),
            ]),
            const SizedBox(height: 7),
            Row(children: [
              Expanded(child: _labeledController('Remark', _expRemark)),
              const SizedBox(width: 10),
              Expanded(child: _labeledController('Test Remark if any', _expTestRemark)),
            ]),
            const SizedBox(height: 9),
            Row(
              children: [
                _actionButton('Select Channel', () async { await _selectExperimentChannels(localSet); }),
                const SizedBox(width: 8),
                Text('${experiment.selectedChannels.where((v) => v).length} of 8 channels selected', style: const TextStyle(fontSize: 11)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(8, (i) => _channelSetupChip(i)),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _actionButton('Cancel', () => setState(() => page = LoggerPage.home), secondary: true),
                const SizedBox(width: 8),
                _actionButton('Save', () async {
                  experiment = ExperimentInfo(
                    testName: _expTestName.text.trim(),
                    testPlace: _expPlace.text.trim(),
                    operatorName: _expOperator.text.trim(),
                    operatorContact: _expContact.text.trim(),
                    operatorEmail: _expEmail.text.trim(),
                    remark: _expRemark.text.trim().isEmpty ? 'Other' : _expRemark.text.trim(),
                    testRemark: _expTestRemark.text.trim(),
                    selectedChannels: List<bool>.from(experiment.selectedChannels),
                  );
                  await ConfigService.saveExperiment(experiment);
                  if (mounted) setState(() {});
                  _toast('Experiment saved');
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _channelSetupChip(int i) => GestureDetector(
        onLongPress: () => _renameChannel(i),
        onTap: () => _configureChannel(i),
        child: Container(
          width: 132,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          color: experiment.selectedChannels[i] ? _gold : Colors.grey.shade300,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('CH${i + 1}  ${configs[i].name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
            Text('${configs[i].parameter}  |  ${configs[i].unit}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9)),
          ]),
        ),
      );

  Future<void> _selectExperimentChannels(StateSetter localSet) async {
    var working = List<bool>.from(experiment.selectedChannels);
    final result = await showDialog<List<bool>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDialog) => AlertDialog(
          title: const Text('Select Channel'),
          content: SizedBox(
            width: 470,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(8, (i) => FilterChip(
                label: Text('Channel ${i + 1}'),
                selected: working[i],
                onSelected: (v) => setDialog(() => working[i] = v),
              )),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, working), child: const Text('Save & Next')),
          ],
        ),
      ),
    );
    if (result != null) {
      experiment = ExperimentInfo(
        testName: experiment.testName,
        testPlace: experiment.testPlace,
        operatorName: experiment.operatorName,
        operatorContact: experiment.operatorContact,
        operatorEmail: experiment.operatorEmail,
        remark: experiment.remark,
        testRemark: experiment.testRemark,
        selectedChannels: result,
      );
      localSet(() {});
      setState(() {});
    }
  }

  Widget _digitalPage() => Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Expanded(
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 3.15,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: 8,
                itemBuilder: (_, i) => _digitalTile(i),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _actionButton('Save', () => _toast('Digital readout settings saved')),
                const SizedBox(width: 8),
                _actionButton('Cancel', () => setState(() => page = LoggerPage.home), secondary: true),
              ],
            ),
          ],
        ),
      );

  Widget _digitalTile(int i) => InkWell(
        onTap: () => _configureChannel(i),
        onLongPress: () => _renameChannel(i),
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: _border.withOpacity(0.65))),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Container(
                  color: const Color(0xFFD3E4F6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('Ch. ${i + 1} ${configs[i].parameter}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Row(children: [
                      Text(_value(i), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                      const SizedBox(width: 6),
                      Text(configs[i].unit, style: const TextStyle(fontSize: 10)),
                    ]),
                  ]),
                ),
              ),
              Expanded(
                flex: 4,
                child: Container(
                  color: _field,
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('Ch. ${i + 1}. Peak Value', style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700)),
                    Row(children: [
                      Expanded(child: Text(_peak(i), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
                      TextButton(
                        onPressed: () => setState(() => peaks[i] = null),
                        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: const Size(42, 26)),
                        child: const Text('Reset', style: TextStyle(fontSize: 9)),
                      ),
                    ]),
                  ]),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _scopePage() {
    final selected = [for (var i = 0; i < 8; i++) if (scopeSelected[i]) i];
    return Padding(
      padding: const EdgeInsets.all(7),
      child: Column(
        children: [
          Row(children: [
            _actionButton('Graph Selection', _selectScopeChannels),
            const SizedBox(width: 6),
            _actionButton(scopePlaying ? 'Pause' : 'Play', () => setState(() => scopePlaying = !scopePlaying)),
            const SizedBox(width: 6),
            _actionButton('Refresh', () => setState(() { for (final h in history) h.clear(); })),
            const SizedBox(width: 6),
            _actionButton(scopeMaximized ? 'Minimize' : 'Maximize', () => setState(() => scopeMaximized = !scopeMaximized)),
            const Spacer(),
            Text('USB: $usbStatus', style: const TextStyle(fontSize: 10, color: Colors.black54)),
          ]),
          const SizedBox(height: 6),
          if (!scopeMaximized)
            SizedBox(
              height: 39,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: selected.length,
                separatorBuilder: (_, __) => const SizedBox(width: 5),
                itemBuilder: (_, k) {
                  final i = selected[k];
                  return Container(
                    width: 103,
                    padding: const EdgeInsets.all(5),
                    color: const Color(0xFFD3E4F6),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Ch.${i + 1} ${configs[i].parameter}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700)),
                      Text('${_value(i)} ${configs[i].unit}', style: const TextStyle(fontSize: 10.5)),
                    ]),
                  );
                },
              ),
            ),
          if (!scopeMaximized) const SizedBox(height: 5),
          Expanded(
            child: Container(
              color: const Color(0xFFF2F4FA),
              child: CustomPaint(
                painter: MultiGraphPainter(histories: history, selected: scopeSelected),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Row(children: [
            _actionButton('Change Graph Channel', _selectScopeChannels),
            const SizedBox(width: 6),
            _actionButton('Close Graph', () => setState(() => page = LoggerPage.home), secondary: true),
          ]),
        ],
      ),
    );
  }

  Future<void> _selectScopeChannels() async {
    var work = List<bool>.from(scopeSelected);
    final result = await showDialog<List<bool>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDialog) => AlertDialog(
          title: const Text('Graph Selection'),
          content: SizedBox(
            width: 500,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(8, (i) => FilterChip(
                selected: work[i],
                label: Text('Channel ${i + 1} ${configs[i].parameter}'),
                onSelected: (v) => setDialog(() => work[i] = v),
              )),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, work), child: const Text('Show Graph')),
          ],
        ),
      ),
    );
    if (result != null) setState(() => scopeSelected.setAll(0, result));
  }

  Widget _peakPage() => Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Expanded(
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 4.5,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: 8,
                itemBuilder: (_, i) => Container(
                  color: const Color(0xFFD3E4F6),
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  child: Row(children: [
                    Expanded(child: Text('Ch. ${i + 1} ${configs[i].parameter}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700))),
                    Text('${_peak(i)} ${configs[i].unit}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                    const SizedBox(width: 8),
                    _smallButton('Reset', () => setState(() => peaks[i] = null)),
                  ]),
                ),
              ),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              _actionButton('Peak Value Reset', () => setState(() { for (var i = 0; i < 8; i++) peaks[i] = null; })),
              const SizedBox(width: 8),
              _actionButton('Cancel', () => setState(() => page = LoggerPage.home), secondary: true),
            ]),
          ],
        ),
      );

  Widget _historicalPage() => Padding(
        padding: const EdgeInsets.all(7),
        child: Column(
          children: [
            Row(children: [
              _actionButton('Graph Selection', _selectScopeChannels),
              const SizedBox(width: 6),
              _actionButton('Graph Setting', _historicalSettings),
              const SizedBox(width: 6),
              _actionButton('Refresh', () => setState(() {})),
            ]),
            const SizedBox(height: 7),
            Expanded(
              child: CustomPaint(
                painter: HistoricalBarPainter(
                  values: List<double>.generate(8, (i) => (peaks[i] ?? configs[i].apply(frame.channels[i]) ?? 0).abs()),
                  selected: scopeSelected,
                  greenEnd: settings.greenEnd,
                  yellowEnd: settings.yellowEnd,
                  brownEnd: settings.brownEnd,
                  redEnd: settings.redEnd,
                ),
                child: const SizedBox.expand(),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(8, (i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('Ch.${i + 1}', style: const TextStyle(fontSize: 9)),
              )),
            ),
          ],
        ),
      );

  Future<void> _historicalSettings() async {
    final green = TextEditingController(text: settings.greenEnd.toStringAsFixed(2));
    final yellow = TextEditingController(text: settings.yellowEnd.toStringAsFixed(2));
    final brown = TextEditingController(text: settings.brownEnd.toStringAsFixed(2));
    final red = TextEditingController(text: settings.redEnd.toStringAsFixed(2));
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Historical Graph Setting'),
        content: SizedBox(
          width: 560,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _rangeRow('Start Green Color', '0.00', 'End Green Color', green),
            _rangeRow('Start Yellow Color', '${settings.greenEnd + 0.01}', 'End Yellow Color', yellow),
            _rangeRow('Start Brown Color', '${settings.yellowEnd + 0.01}', 'End Brown Color', brown),
            _rangeRow('Start Red Color', '${settings.brownEnd + 0.01}', 'End Red Color', red),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved == true) {
      settings = settings.copyWith(
        greenEnd: double.tryParse(green.text) ?? settings.greenEnd,
        yellowEnd: double.tryParse(yellow.text) ?? settings.yellowEnd,
        brownEnd: double.tryParse(brown.text) ?? settings.brownEnd,
        redEnd: double.tryParse(red.text) ?? settings.redEnd,
      );
      await ConfigService.saveAppSettings(settings);
      if (mounted) setState(() {});
    }
  }

  Widget _rangeRow(String a, String start, String b, TextEditingController end) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(children: [
          Expanded(child: Text(a, style: const TextStyle(fontSize: 11))),
          SizedBox(width: 75, child: TextField(controller: TextEditingController(text: start), readOnly: true)),
          const SizedBox(width: 8),
          Expanded(child: Text(b, style: const TextStyle(fontSize: 11))),
          SizedBox(width: 75, child: TextField(controller: end, keyboardType: TextInputType.number)),
        ]),
      );

  Widget _settingsPage() => Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Sample Rate Selection', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  DropdownButtonFormField<int>(
                    value: settings.sampleRate,
                    items: const [250, 500, 1000, 2500].map((v) => DropdownMenuItem(value: v, child: Text('$v Hz'))).toList(),
                    onChanged: (v) async {
                      if (v == null) return;
                      settings = settings.copyWith(sampleRate: v);
                      await ConfigService.saveAppSettings(settings);
                      await serial.send('SET SRATE $v');
                      if (mounted) setState(() {});
                    },
                  ),
                ]),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Noise Filter Selection', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  DropdownButtonFormField<String>(
                    value: settings.filter,
                    items: const ['Low Pass Filter', 'High Pass Filter', 'Butterworth Filter', 'Linear Phase Filter']
                        .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                    onChanged: (v) async {
                      if (v == null) return;
                      settings = settings.copyWith(filter: v);
                      await ConfigService.saveAppSettings(settings);
                      await serial.send('SET FILTER ${v.toUpperCase().replaceAll(' ', '_')}');
                      if (mounted) setState(() {});
                    },
                  ),
                ]),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Decimal', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  DropdownButtonFormField<int>(
                    value: settings.decimals,
                    items: List.generate(6, (i) => i + 1).map((v) => DropdownMenuItem(value: v, child: Text('0.${List.filled(v, '0').join()}'))).toList(),
                    onChanged: (v) async {
                      if (v == null) return;
                      settings = settings.copyWith(decimals: v);
                      await ConfigService.saveAppSettings(settings);
                      if (mounted) setState(() {});
                    },
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 18),
            const Text('Channel Setup', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 4.7, crossAxisSpacing: 8, mainAxisSpacing: 7),
                itemCount: 8,
                itemBuilder: (_, i) => InkWell(
                  onTap: () => _configureChannel(i),
                  onLongPress: () => _renameChannel(i),
                  child: Container(
                    color: _gold,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(children: [
                      Text('Ch.${i + 1}', style: const TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(width: 8),
                      Expanded(child: Text('${configs[i].name} • ${configs[i].parameter} • ${configs[i].unit}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10))),
                      const Icon(Icons.edit, size: 16),
                    ]),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _calibrationPage() => Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(children: [
              const Text('Calibration Setting', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text('Two-point calibration + offset', style: TextStyle(fontSize: 10, color: Colors.grey.shade700)),
            ]),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: 8,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) => InkWell(
                  onTap: () => _calibrateChannel(i),
                  child: Container(
                    color: i.isEven ? const Color(0xFFE8F0FA) : const Color(0xFFFFF1DD),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    child: Row(children: [
                      SizedBox(width: 165, child: Text('Channel ${i + 1}. ${configs[i].parameter}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700))),
                      Expanded(child: Text('Voltage Min ${configs[i].voltageMin.toStringAsFixed(4)} → ${configs[i].externalMin.toStringAsFixed(4)} ${configs[i].unit}', style: const TextStyle(fontSize: 9.5))),
                      Expanded(child: Text('Voltage Max ${configs[i].voltageMax.toStringAsFixed(4)} → ${configs[i].externalMax.toStringAsFixed(4)} ${configs[i].unit}', style: const TextStyle(fontSize: 9.5))),
                      Text('Offset ${configs[i].offset.toStringAsFixed(4)}', style: const TextStyle(fontSize: 9.5)),
                      const SizedBox(width: 8),
                      const Icon(Icons.tune, size: 17),
                    ]),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  Future<void> _calibrateChannel(int i) async {
    final c = configs[i];
    final v1 = TextEditingController(text: c.voltageMin.toString());
    final e1 = TextEditingController(text: c.externalMin.toString());
    final v2 = TextEditingController(text: c.voltageMax.toString());
    final e2 = TextEditingController(text: c.externalMax.toString());
    final additionalOffset = TextEditingController(text: '0.0');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Calibration Setting - Channel ${i + 1}. ${c.parameter}'),
        content: SizedBox(
          width: 600,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(child: _dialogField('Voltage Minimum', v1)),
              const SizedBox(width: 8),
              Expanded(child: _dialogField('External Value / Define Value', e1)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _dialogField('Voltage Maximum', v2)),
              const SizedBox(width: 8),
              Expanded(child: _dialogField('External Value / Define Value', e2)),
            ]),
            const SizedBox(height: 8),
            _dialogField('Offset Value', additionalOffset),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved != true) return;
    final rv1 = double.tryParse(v1.text) ?? c.voltageMin;
    final re1 = double.tryParse(e1.text) ?? c.externalMin;
    final rv2 = double.tryParse(v2.text) ?? c.voltageMax;
    final re2 = double.tryParse(e2.text) ?? c.externalMax;
    final extra = double.tryParse(additionalOffset.text) ?? 0.0;
    var scale = c.scale;
    var offset = c.offset;
    if ((rv2 - rv1).abs() > 1e-12) {
      scale = (re2 - re1) / (rv2 - rv1);
      offset = re1 - rv1 * scale + extra;
    }
    configs[i] = c.copyWith(
      scale: scale,
      offset: offset,
      voltageMin: rv1,
      externalMin: re1,
      voltageMax: rv2,
      externalMax: re2,
    );
    await ConfigService.save(i, configs[i]);
    if (mounted) setState(() {});
    _toast('Channel ${i + 1} calibration saved');
  }

  Widget _memoryPage() => Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Memory'),
            const SizedBox(height: 10),
            Row(children: [
              _infoCard('LOGGER MEMORY', frame.memoryKb == null ? '-- kb' : '${frame.memoryKb!.toStringAsFixed(0)} kb', Colors.blue),
              _infoCard('USB', usbStatus, usbStatus == 'CONNECTED' ? Colors.green : Colors.orange),
              _infoCard('LOCAL RECORD', csv.active ? 'RECORDING' : 'STOPPED', csv.active ? Colors.green : Colors.red),
            ]),
            const SizedBox(height: 14),
            Wrap(spacing: 9, runSpacing: 9, children: [
              _actionButton('Check Memory Card Status', () async { await serial.send('MEM_STATUS'); _toast('Memory status command sent'); }),
              _actionButton('Erase Memory Card', () => _confirmMemoryAction('Erase Memory Card', 'MEM_ERASE')),
              _actionButton('Format Memory Card', () => _confirmMemoryAction('Format Memory Card', 'MEM_FORMAT')),
            ]),
            const SizedBox(height: 12),
            Text('Commands are sent to the data logger over USB. The logger firmware must support MEM_STATUS / MEM_ERASE / MEM_FORMAT for remote SD-card control.', style: TextStyle(fontSize: 10, color: Colors.grey.shade700)),
          ],
        ),
      );

  Future<void> _confirmMemoryAction(String title, String command) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: const Text('This operation can delete recorded data on the logger memory card. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
        ],
      ),
    );
    if (ok == true) {
      await serial.send(command);
      _toast('$title command sent');
    }
  }

  Widget _recordingPage() {
    final active = csv.active;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Data Recording'),
          const SizedBox(height: 14),
          Row(children: [
            _actionButton('Recording Start', active ? null : _startRecording),
            const SizedBox(width: 18),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: active ? (_blink ? Colors.green : Colors.green.withOpacity(0.15)) : Colors.red,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Text(active ? 'Green LED Flashes Continuously' : 'RED LED Continuous ON', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            const SizedBox(width: 18),
            _actionButton('Recording Stop', active ? _stopRecording : null, secondary: true),
          ]),
          const SizedBox(height: 18),
          Text(active ? 'Recording file: ${csv.currentFile?.path.split('/').last ?? ''}' : 'Recording is stopped.', style: const TextStyle(fontSize: 11)),
          const SizedBox(height: 7),
          Text('Selected channels: ${experiment.selectedChannels.where((v) => v).length}/8   •   Sample Rate: ${settings.sampleRate} Hz   •   Filter: ${settings.filter}', style: const TextStyle(fontSize: 10, color: Colors.black54)),
          const SizedBox(height: 6),
          Text('Power: ${frame.powerSource}   •   Battery: ${frame.batteryVoltage?.toStringAsFixed(2) ?? '--'} V / ${frame.batteryPercent?.toStringAsFixed(0) ?? '--'}%', style: const TextStyle(fontSize: 10, color: Colors.black54)),
        ],
      ),
    );
  }

  Future<void> _startRecording() async {
    await csv.start(configs);
    await serial.send('REC_START');
    if (mounted) setState(() {});
  }

  Future<void> _stopRecording() async {
    await csv.stop();
    await serial.send('REC_STOP');
    if (mounted) setState(() {});
  }

  Future<void> _editLoggerName() async {
    final c = TextEditingController(text: settings.loggerName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Data Logger Name'),
        content: SizedBox(width: 420, child: TextField(controller: c, autofocus: true)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      settings = settings.copyWith(loggerName: name);
      await ConfigService.saveAppSettings(settings);
      if (mounted) setState(() {});
    }
  }

  Future<void> _renameChannel(int i) async {
    final c = TextEditingController(text: configs[i].name);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Rename Channel ${i + 1}'),
        content: SizedBox(width: 420, child: TextField(controller: c, autofocus: true)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (value != null && value.isNotEmpty) {
      configs[i] = configs[i].copyWith(name: value);
      await ConfigService.save(i, configs[i]);
      if (mounted) setState(() {});
    }
  }

  Future<void> _configureChannel(int i) async {
    var parameter = configs[i].parameter;
    var unit = configs[i].unit;
    final name = TextEditingController(text: configs[i].name);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDialog) => AlertDialog(
          title: Text('Channel ${i + 1} Setup'),
          content: SizedBox(
            width: 640,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Channel Name - Long Press Rename also supported')),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: parameters.contains(parameter) ? parameter : 'Others',
                    decoration: const InputDecoration(labelText: 'Select Parameter'),
                    items: parameters.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                    onChanged: (v) => setDialog(() => parameter = v ?? parameter),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: units.contains(unit) ? unit : 'Other',
                    decoration: const InputDecoration(labelText: 'Unit Selection'),
                    items: units.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                    onChanged: (v) => setDialog(() => unit = v ?? unit),
                  ),
                ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save & Next')),
          ],
        ),
      ),
    );
    if (result == true) {
      configs[i] = configs[i].copyWith(
        name: name.text.trim().isEmpty ? 'Channel ${i + 1}' : name.text.trim(),
        parameter: parameter,
        unit: unit,
      );
      await ConfigService.save(i, configs[i]);
      if (mounted) setState(() {});
    }
  }

  Widget _goldBox(String text, {double? width, bool center = false}) => Container(
        width: width,
        height: 33,
        color: _gold,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: center ? Alignment.center : Alignment.centerLeft,
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: _ink)),
      );

  Widget _sectionTitle(String text) => Container(
        color: _gold,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
      );

  Widget _labeledField(String label, String value, {bool readOnly = false}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          TextField(controller: TextEditingController(text: value), readOnly: readOnly),
        ],
      );

  Widget _labeledController(String label, TextEditingController controller, {TextInputType? keyboard}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          TextField(controller: controller, keyboardType: keyboard),
        ],
      );

  Widget _dialogField(String label, TextEditingController controller) => TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        decoration: InputDecoration(labelText: label),
      );

  Widget _actionButton(String text, VoidCallback? onTap, {bool secondary = false}) => SizedBox(
        height: 31,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: secondary ? const Color(0xFF8DB4D5) : _gold,
            foregroundColor: _ink,
            disabledBackgroundColor: Colors.grey.shade300,
            disabledForegroundColor: Colors.grey.shade600,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
          ),
          child: Text(text, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700)),
        ),
      );

  Widget _smallButton(String text, VoidCallback onTap) => SizedBox(
        height: 25,
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(backgroundColor: _gold, foregroundColor: _ink, padding: const EdgeInsets.symmetric(horizontal: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2))),
          child: Text(text, style: const TextStyle(fontSize: 9)),
        ),
      );

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }
}

class MultiGraphPainter extends CustomPainter {
  final List<List<double>> histories;
  final List<bool> selected;
  const MultiGraphPainter({required this.histories, required this.selected});

  static const colors = [
    Color(0xFF21A8E0), Color(0xFFE59B35), Color(0xFF77B94D), Color(0xFFC854A4),
    Color(0xFF8B6FC6), Color(0xFF24B69B), Color(0xFFE04C4C), Color(0xFF606D7A),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = const Color(0xFFD9DEE8)..strokeWidth = 1;
    for (var x = 0; x <= 10; x++) {
      final px = size.width * x / 10;
      canvas.drawLine(Offset(px, 0), Offset(px, size.height), grid);
    }
    for (var y = 0; y <= 8; y++) {
      final py = size.height * y / 8;
      canvas.drawLine(Offset(0, py), Offset(size.width, py), grid);
    }
    final all = <double>[];
    for (var i = 0; i < 8; i++) {
      if (selected[i]) all.addAll(histories[i]);
    }
    if (all.isEmpty) return;
    var min = all.reduce((a, b) => a < b ? a : b);
    var max = all.reduce((a, b) => a > b ? a : b);
    if ((max - min).abs() < 1e-12) { min -= 1; max += 1; }
    final span = max - min;
    for (var ch = 0; ch < 8; ch++) {
      if (!selected[ch] || histories[ch].length < 2) continue;
      final vals = histories[ch];
      final path = Path();
      for (var i = 0; i < vals.length; i++) {
        final x = size.width * i / (vals.length - 1);
        final y = size.height - ((vals[i] - min) / span) * size.height;
        if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
      }
      canvas.drawPath(path, Paint()..color = colors[ch]..style = PaintingStyle.stroke..strokeWidth = 1.7);
    }
  }

  @override
  bool shouldRepaint(covariant MultiGraphPainter oldDelegate) => true;
}

class HistoricalBarPainter extends CustomPainter {
  final List<double> values;
  final List<bool> selected;
  final double greenEnd;
  final double yellowEnd;
  final double brownEnd;
  final double redEnd;

  const HistoricalBarPainter({
    required this.values,
    required this.selected,
    required this.greenEnd,
    required this.yellowEnd,
    required this.brownEnd,
    required this.redEnd,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final axis = Paint()..color = Colors.black45..strokeWidth = 1;
    canvas.drawLine(Offset(30, 10), Offset(30, size.height - 20), axis);
    canvas.drawLine(Offset(30, size.height - 20), Offset(size.width - 10, size.height - 20), axis);
    final maxRange = redEnd <= 0 ? 100.0 : redEnd;
    final usableH = size.height - 35;
    final barW = (size.width - 70) / 8 * 0.58;
    for (var i = 0; i < 8; i++) {
      final cx = 50 + (size.width - 70) * (i + 0.5) / 8;
      final value = selected[i] ? values[i].clamp(0, maxRange) : 0.0;
      final totalH = usableH * value / maxRange;
      var bottom = size.height - 20;
      void segment(double start, double end, Color color) {
        final capped = value.clamp(start, end);
        final amount = (capped - start).clamp(0, end - start);
        if (amount <= 0) return;
        final h = usableH * amount / maxRange;
        canvas.drawRect(Rect.fromLTWH(cx - barW / 2, bottom - h, barW, h), Paint()..color = color);
        bottom -= h;
      }
      segment(0, greenEnd, const Color(0xFF52B84A));
      segment(greenEnd, yellowEnd, const Color(0xFFFFE33D));
      segment(yellowEnd, brownEnd, const Color(0xFFC86B18));
      segment(brownEnd, redEnd, const Color(0xFFE31B23));
      if (totalH == 0 && selected[i]) {
        canvas.drawRect(Rect.fromLTWH(cx - barW / 2, bottom - 2, barW, 2), Paint()..color = Colors.grey.shade400);
      }
    }
  }

  @override
  bool shouldRepaint(covariant HistoricalBarPainter oldDelegate) => true;
}
