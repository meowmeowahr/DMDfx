import 'dart:async';
import 'dart:convert';
import 'package:uuid/uuid.dart';

import 'package:dmdfx/device_query.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

class FxDeviceConfig {
  int brightness;
  int pageTime;
  int timeBarPos;

  FxDeviceConfig({
    required this.brightness,
    required this.pageTime,
    required this.timeBarPos,
  });

  Future<bool> reload(FxDevice device) async {
    final queryBrightness = await fxQuery(device, "qB", "brightness");
    if (queryBrightness == null) {
      print("Error during brightness fxQuery");
      return false;
    }
    brightness = int.tryParse(queryBrightness) ?? brightness;

    final queryPageTime = await fxQuery(device, "qP", "pagetime");
    if (queryPageTime == null) {
      print("Error during pageTime fxQuery");
      return false;
    }
    pageTime = int.tryParse(queryPageTime) ?? pageTime;

    final queryTimeBarPos = await fxQuery(device, "qT", "timebarpos");
    if (queryTimeBarPos == null) {
      print("Error during timeBarPos fxQuery");
      return false;
    }
    timeBarPos = int.tryParse(queryTimeBarPos) ?? timeBarPos;

    return true;
  }

  Future<void> setBrightness(FxDevice device, int value) async {
    brightness = value;
    device.port.write(Uint8List.fromList("brightness=$brightness".codeUnits));
  }

  Future<void> setPageTime(FxDevice device, int value) async {
    pageTime = value;
    device.port.write(Uint8List.fromList("pagetime=$pageTime".codeUnits));
  }

  Future<void> setTimebarPos(FxDevice device, int value) async {
    timeBarPos = value;
    device.port.write(Uint8List.fromList("timebarpos=$timeBarPos".codeUnits));
  }
}

class FxDeviceMemory {
  int sdFree;
  int sdTotal;

  FxDeviceMemory({required this.sdFree, required this.sdTotal});

  Future<bool> reload(FxDevice device) async {
    final querySdFree = await fxQuery(device, "qSdFree", "sdfree");
    if (querySdFree == null) {
      print("Error during sdFree fxQuery");
      return false;
    }
    sdFree = int.tryParse(querySdFree) ?? sdFree;

    final querySdTotal = await fxQuery(device, "qSdTotal", "sdtotal");
    if (querySdTotal == null) {
      print("Error during sdTotal fxQuery");
      return false;
    }
    sdTotal = int.tryParse(querySdTotal) ?? sdTotal;

    return true;
  }
}

class FxDevice {
  final SerialPort port;
  final String portName;
  final String modelNumber;
  final String cpu;
  final String version;
  final String resolution;
  final FxDeviceConfig config = FxDeviceConfig(
    brightness: 0,
    pageTime: 0,
    timeBarPos: 0,
  );
  final FxDeviceMemory memory = FxDeviceMemory(sdFree: 0, sdTotal: 0);
  final bool isConnected;

  final Map<String, void Function(String key, String value)> _callbacks = {};
  StreamSubscription<Uint8List>? _readerSub;
  final _uuid = Uuid();

  String? _uptimeCallbackId;
  int uptimeMs = 0;

  FxDevice({
    required this.port,
    required this.portName,
    required this.modelNumber,
    required this.cpu,
    required this.version,
    required this.resolution,
    this.isConnected = false,
  });

  bool open() {
    final opened = port.openReadWrite();
    if (opened) {
      _startReading();
    }
    _uptimeCallbackId ??= attachCallback((String key, String value) {
      if (key == "uptime") {
        uptimeMs = int.tryParse(value) ?? uptimeMs;
      }
    });
    return opened;
  }

  bool close() {
    _readerSub?.cancel();
    return port.close();
  }

  void save() {
    port.write(Uint8List.fromList("save\n".codeUnits));
  }

  void rewind() {
    port.write(Uint8List.fromList("rewind\n".codeUnits));
  }

  String attachCallback(void Function(String key, String value) callback) {
    final id = _uuid.v4();
    _callbacks[id] = callback;
    return id;
  }

  void removeCallback(String id) {
    _callbacks.remove(id);
  }

  void _startReading() {
    _readerSub?.cancel();
    final reader = SerialPortReader(port);

    String buffer = '';
    _readerSub = reader.stream.listen((data) {
      buffer += utf8.decode(data);
      int idx;
      while ((idx = buffer.indexOf('\r\n')) != -1) {
        final line = buffer.substring(0, idx);
        buffer = buffer.substring(idx + 2);
        final eqIdx = line.indexOf('=');
        if (eqIdx != -1) {
          final key = line.substring(0, eqIdx);
          final value = line.substring(eqIdx + 1);
          for (final cb in _callbacks.values) {
            cb(key, value);
          }
        }
      }
    });
  }
}
