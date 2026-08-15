import 'package:shared_preferences/shared_preferences.dart';
import '../models/channel_config.dart';

class ConfigService {
  static Future<List<ChannelConfig>> load() async {
    final p = await SharedPreferences.getInstance();
    return List.generate(8, (i) {
      final n = i + 1;
      return ChannelConfig(
        name: p.getString('ch${n}_name') ?? 'Channel $n',
        unit: p.getString('ch${n}_unit') ?? 'V',
        scale: p.getDouble('ch${n}_scale') ?? 1.0,
        offset: p.getDouble('ch${n}_offset') ?? 0.0,
      );
    });
  }

  static Future<void> save(int index, ChannelConfig c) async {
    final p = await SharedPreferences.getInstance();
    final n = index + 1;
    await p.setString('ch${n}_name', c.name);
    await p.setString('ch${n}_unit', c.unit);
    await p.setDouble('ch${n}_scale', c.scale);
    await p.setDouble('ch${n}_offset', c.offset);
  }
}
