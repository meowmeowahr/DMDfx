import 'dart:async';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'fxdevice.dart';

class FxDeviceController {
  final Map<String, FxDevice> _devices = {};
  final Map<String, SerialPort> _openPorts = {};
  static const int _defaultBaudRate = 19200;
  static const Duration _defaultTimeout = Duration(seconds: 5);
  static const int _maxReadAttempts = 50;
  static bool discoveryRunning = false;

  Map<String, FxDevice> get devices => Map.unmodifiable(_devices);

  List<String> getAvailablePorts() {
    return SerialPort.availablePorts;
  }

  Future<bool> _testDevicePort(
    String portPath, {
    int baudRate = _defaultBaudRate,
  }) async {
    SerialPort port;
    FxDevice? device;

    try {
      // If device already exists, don't test it
      if (_devices.containsKey(portPath)) {
        return true;
      }

      // If port is already open but no device exists, use existing port
      if (_openPorts.containsKey(portPath)) {
        port = _openPorts[portPath]!;
        device = FxDevice(port: port, baudRate: baudRate);
        _devices[portPath] = device;
        return true;
      }

      // New port detection
      port = SerialPort(portPath);
      if (!port.openReadWrite()) {
        print('Failed to open port $portPath');
        return false;
      }

      final config = port.config..baudRate = baudRate;
      port.config = config;
      _openPorts[portPath] = port;
      device = FxDevice(port: port, baudRate: baudRate);

      print('Testing new port $portPath: Sending X command');
      device.write('X\n');

      final startTime = DateTime.now();
      int attempts = 0;

      while (attempts < _maxReadAttempts &&
          DateTime.now().difference(startTime) < _defaultTimeout) {
        try {
          final response = await device.readLine(
            timeout: const Duration(seconds: 1),
          );
          print('Response $attempts from $portPath: $response');

          if (response.contains('modelno=')) {
            final modelNo = _extractValue("modelno", response);
            if (modelNo.isNotEmpty) {
              device.fxDeviceType = modelNo;
              _devices[portPath] = device;
              return true;
            }
          } else if (response.contains('name=')) {
            final dispName = _extractValue("name", response);
            if (dispName.isNotEmpty) {
              device.displayName = dispName;
              _devices[portPath] = device;
              return true;
            }
          }
          attempts++;
        } catch (e) {
          print('Read attempt $attempts failed on $portPath: $e');
          attempts++;
          if (e is TimeoutException) continue;
          break;
        }
      }

      // If we get here, treat as unknown FX device
      device.displayName = 'FX Device (Unknown @ $portPath)';
      _devices[portPath] = device;
      return true;
    } catch (e) {
      print('Error testing port $portPath: $e');
      await device?.dispose();
      if (_openPorts.containsKey(portPath)) {
        _openPorts[portPath]!.close();
        _openPorts.remove(portPath);
      }
      return false;
    }
  }

  String _extractValue(String command, String response) {
    final match = RegExp('$command=([^\\s]+)').firstMatch(response);
    return match?.group(1) ?? '';
  }

  Future<List<String>> discoverDevices({
    int baudRate = _defaultBaudRate,
    Duration timeoutPerPort = _defaultTimeout,
  }) async {
    if (discoveryRunning) return _devices.keys.toList();
    discoveryRunning = true;

    final availablePorts = getAvailablePorts();
    final foundPorts = <String>[];

    for (final portPath in availablePorts) {
      if (_devices.containsKey(portPath)) {
        foundPorts.add(portPath);
        continue;
      }

      if (await _testDevicePort(portPath, baudRate: baudRate)) {
        foundPorts.add(portPath);
      } else {
        if (_openPorts.containsKey(portPath) &&
            !_devices.containsKey(portPath)) {
          _openPorts[portPath]!.close();
          _openPorts.remove(portPath);
        }
      }
    }

    discoveryRunning = false;
    return foundPorts;
  }

  FxDevice? getDevice(String portPath) => _devices[portPath];

  Future<void> removeDevice(String portPath) async {
    final device = _devices[portPath];
    if (device != null) {
      await device.dispose();
      _devices.remove(portPath);
    }
    if (_openPorts.containsKey(portPath)) {
      _openPorts[portPath]!.close();
      _openPorts.remove(portPath);
    }
  }

  Future<void> closeAllPorts() async {
    final devicePaths = List.from(_devices.keys);
    for (final portPath in devicePaths) {
      await removeDevice(portPath);
    }
    _devices.clear();
    _openPorts.clear();
  }

  Future<void> dispose() async {
    await closeAllPorts();
  }
}
