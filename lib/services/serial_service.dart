import 'dart:async';
import 'dart:typed_data';

import 'package:usb_serial/transaction.dart';
import 'package:usb_serial/usb_serial.dart';

import '../models/logger_frame.dart';

class SerialService {
  UsbPort? _port;
  UsbDevice? _device;
  Transaction<String>? _transaction;
  StreamSubscription<String>? _lineSub;
  StreamSubscription<UsbEvent>? _usbSub;

  final frameController = StreamController<LoggerFrame>.broadcast();
  final statusController = StreamController<String>.broadcast();

  bool get connected => _port != null;
  String get deviceName => _device?.productName ?? _device?.deviceName ?? 'USB Logger';

  Future<void> start() async {
    _usbSub ??= UsbSerial.usbEventStream?.listen((_) => reconnect());
    await reconnect();
  }

  Future<void> reconnect() async {
    final devices = await UsbSerial.listDevices();
    if (devices.isEmpty) {
      await disconnect();
      statusController.add('USB DISCONNECTED');
      return;
    }
    if (_device != null && _port != null && devices.any((d) => d.deviceName == _device!.deviceName)) {
      return;
    }
    await connect(devices.first);
  }

  Future<bool> connect(UsbDevice device) async {
    await disconnect();
    statusController.add('CONNECTING');
    final port = await device.create();
    if (port == null || await port.open() != true) {
      statusController.add('USB OPEN FAILED');
      return false;
    }
    await port.setDTR(true);
    await port.setRTS(true);
    await port.setPortParameters(115200, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);
    final input = port.inputStream;
    if (input == null) {
      await port.close();
      statusController.add('USB INPUT FAILED');
      return false;
    }
    _port = port;
    _device = device;
    _transaction = Transaction.stringTerminated(input, Uint8List.fromList([13, 10]));
    _lineSub = _transaction!.stream.listen((line) {
      try {
        frameController.add(LoggerFrame.parse(line));
      } catch (_) {}
    }, onError: (_) {
      statusController.add('USB ERROR');
    });
    statusController.add('CONNECTED');
    return true;
  }

  Future<void> send(String command) async {
    final p = _port;
    if (p == null) return;
    await p.write(Uint8List.fromList('$command\r\n'.codeUnits));
  }

  Future<void> disconnect() async {
    await _lineSub?.cancel();
    _lineSub = null;
    _transaction?.dispose();
    _transaction = null;
    await _port?.close();
    _port = null;
    _device = null;
  }

  Future<void> dispose() async {
    await disconnect();
    await _usbSub?.cancel();
    await frameController.close();
    await statusController.close();
  }
}
