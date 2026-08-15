import 'package:shared_preferences/shared_preferences.dart';
import '../models/channel_config.dart';

class AppSettings {
  final String loggerName;
  final int sampleRate;
  final String filter;
  final int decimals;
  final double greenEnd;
  final double yellowEnd;
  final double brownEnd;
  final double redEnd;

  const AppSettings({
    this.loggerName = 'IPES 8 CHANNEL DATA LOGGER',
    this.sampleRate = 2500,
    this.filter = 'Low Pass Filter',
    this.decimals = 3,
    this.greenEnd = 20.0,
    this.yellowEnd = 40.0,
    this.brownEnd = 80.0,
    this.redEnd = 100.0,
  });

  AppSettings copyWith({
    String? loggerName,
    int? sampleRate,
    String? filter,
    int? decimals,
    double? greenEnd,
    double? yellowEnd,
    double? brownEnd,
    double? redEnd,
  }) =>
      AppSettings(
        loggerName: loggerName ?? this.loggerName,
        sampleRate: sampleRate ?? this.sampleRate,
        filter: filter ?? this.filter,
        decimals: decimals ?? this.decimals,
        greenEnd: greenEnd ?? this.greenEnd,
        yellowEnd: yellowEnd ?? this.yellowEnd,
        brownEnd: brownEnd ?? this.brownEnd,
        redEnd: redEnd ?? this.redEnd,
      );
}

class ExperimentInfo {
  final String testName;
  final String testPlace;
  final String operatorName;
  final String operatorContact;
  final String operatorEmail;
  final String remark;
  final String testRemark;
  final List<bool> selectedChannels;

  const ExperimentInfo({
    this.testName = '',
    this.testPlace = '',
    this.operatorName = '',
    this.operatorContact = '',
    this.operatorEmail = '',
    this.remark = 'Other',
    this.testRemark = '',
    this.selectedChannels = const [true, true, true, true, true, true, true, true],
  });
}

class ConfigService {
  static Future<List<ChannelConfig>> load() async {
    final p = await SharedPreferences.getInstance();
    return List.generate(8, (i) {
      final n = i + 1;
      return ChannelConfig(
        name: p.getString('ch${n}_name') ?? 'Channel $n',
        parameter: p.getString('ch${n}_parameter') ?? 'Voltage',
        unit: p.getString('ch${n}_unit') ?? 'V',
        scale: p.getDouble('ch${n}_scale') ?? 1.0,
        offset: p.getDouble('ch${n}_offset') ?? 0.0,
        voltageMin: p.getDouble('ch${n}_vmin') ?? 0.0,
        externalMin: p.getDouble('ch${n}_emin') ?? 0.0,
        voltageMax: p.getDouble('ch${n}_vmax') ?? 10.0,
        externalMax: p.getDouble('ch${n}_emax') ?? 10.0,
      );
    });
  }

  static Future<void> save(int index, ChannelConfig c) async {
    final p = await SharedPreferences.getInstance();
    final n = index + 1;
    await p.setString('ch${n}_name', c.name);
    await p.setString('ch${n}_parameter', c.parameter);
    await p.setString('ch${n}_unit', c.unit);
    await p.setDouble('ch${n}_scale', c.scale);
    await p.setDouble('ch${n}_offset', c.offset);
    await p.setDouble('ch${n}_vmin', c.voltageMin);
    await p.setDouble('ch${n}_emin', c.externalMin);
    await p.setDouble('ch${n}_vmax', c.voltageMax);
    await p.setDouble('ch${n}_emax', c.externalMax);
  }

  static Future<AppSettings> loadAppSettings() async {
    final p = await SharedPreferences.getInstance();
    return AppSettings(
      loggerName: p.getString('logger_name') ?? 'IPES 8 CHANNEL DATA LOGGER',
      sampleRate: p.getInt('sample_rate') ?? 2500,
      filter: p.getString('filter') ?? 'Low Pass Filter',
      decimals: p.getInt('decimals') ?? 3,
      greenEnd: p.getDouble('green_end') ?? 20.0,
      yellowEnd: p.getDouble('yellow_end') ?? 40.0,
      brownEnd: p.getDouble('brown_end') ?? 80.0,
      redEnd: p.getDouble('red_end') ?? 100.0,
    );
  }

  static Future<void> saveAppSettings(AppSettings s) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('logger_name', s.loggerName);
    await p.setInt('sample_rate', s.sampleRate);
    await p.setString('filter', s.filter);
    await p.setInt('decimals', s.decimals);
    await p.setDouble('green_end', s.greenEnd);
    await p.setDouble('yellow_end', s.yellowEnd);
    await p.setDouble('brown_end', s.brownEnd);
    await p.setDouble('red_end', s.redEnd);
  }

  static Future<ExperimentInfo> loadExperiment() async {
    final p = await SharedPreferences.getInstance();
    final selected = List<bool>.generate(8, (i) => p.getBool('exp_ch_${i + 1}') ?? true);
    return ExperimentInfo(
      testName: p.getString('exp_test_name') ?? '',
      testPlace: p.getString('exp_test_place') ?? '',
      operatorName: p.getString('exp_operator_name') ?? '',
      operatorContact: p.getString('exp_operator_contact') ?? '',
      operatorEmail: p.getString('exp_operator_email') ?? '',
      remark: p.getString('exp_remark') ?? 'Other',
      testRemark: p.getString('exp_test_remark') ?? '',
      selectedChannels: selected,
    );
  }

  static Future<void> saveExperiment(ExperimentInfo e) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('exp_test_name', e.testName);
    await p.setString('exp_test_place', e.testPlace);
    await p.setString('exp_operator_name', e.operatorName);
    await p.setString('exp_operator_contact', e.operatorContact);
    await p.setString('exp_operator_email', e.operatorEmail);
    await p.setString('exp_remark', e.remark);
    await p.setString('exp_test_remark', e.testRemark);
    for (var i = 0; i < 8; i++) {
      await p.setBool('exp_ch_${i + 1}', e.selectedChannels[i]);
    }
  }
}
