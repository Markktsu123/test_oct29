import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';

class BluetoothService {
  final _messageCtrl = StreamController<String>.broadcast();   // legacy text lines (optional)
  final _byteCtrl = StreamController<Uint8List>.broadcast();   // raw bytes (for frames)
  final _connCtrl = StreamController<bool>.broadcast();
  final _debugCtrl = StreamController<String>.broadcast();

  BluetoothConnection? _connection;
  bool get isConnected => _connection?.isConnected == true;

  Stream<String> get messageStream => _messageCtrl.stream;
  Stream<Uint8List> get byteStream => _byteCtrl.stream;
  Stream<bool> get connectionStream => _connCtrl.stream;
  Stream<String> get debugStream => _debugCtrl.stream;

  Future<List<BluetoothDevice>> getPairedDevices() async {
    try {
      return (await FlutterBluetoothSerial.instance.getBondedDevices());
    } catch (e) {
      _debugCtrl.add('getPairedDevices error: $e');
      return [];
    }
  }

  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      _debugCtrl.add('Connecting to ${device.address}...');
      _connection = await BluetoothConnection.toAddress(device.address);
      _debugCtrl.add('Connected to ${device.name ?? device.address}');
      _connCtrl.add(true);

      _connection!.input?.listen((Uint8List data) {
        // Feed raw bytes for binary frames:
        _byteCtrl.add(Uint8List.fromList(data));

        // Optional: also assemble lines for legacy logs
        final str = String.fromCharCodes(data);
        for (final line in str.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty) _messageCtrl.add(trimmed);
        }
      }).onDone(() {
        _debugCtrl.add('Disconnected (remote closed).');
        _connCtrl.add(false);
      });

      return true;
    } catch (e) {
      _debugCtrl.add('Connect error: $e');
      _connCtrl.add(false);
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      await _connection?.finish();
      _connection?.dispose();
      _connection = null;
      _connCtrl.add(false);
    } catch (e) {
      _debugCtrl.add('Disconnect error: $e');
    }
  }

  // Legacy text helper (still used by debug console)
  Future<bool> sendMessage(String text) async {
    if (!isConnected) return false;
    try {
      _connection!.output.add(Uint8List.fromList((text + '\n').codeUnits));
      await _connection!.output.allSent;
      return true;
    } catch (e) {
      _debugCtrl.add('sendMessage error: $e');
      return false;
    }
  }

  // NEW: send raw bytes (binary frame)
  Future<bool> sendBytes(Uint8List bytes) async {
    if (!isConnected) return false;
    try {
      _connection!.output.add(bytes);
      await _connection!.output.allSent;
      return true;
    } catch (e) {
      _debugCtrl.add('sendBytes error: $e');
      return false;
    }
  }

  void dispose() {
    _connection?.dispose();
    _messageCtrl.close();
    _byteCtrl.close();
    _connCtrl.close();
    _debugCtrl.close();
  }
}
