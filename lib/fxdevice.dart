import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';

class FxDevice {
  final SerialPort _port;
  StreamSubscription<Uint8List>? _dataSubscription;
  final StreamController<String> _dataController = StreamController.broadcast();
  final StreamController<Uint8List> _rawDataController =
      StreamController.broadcast();

  int _baudRate;
  String _displayName;
  String _fxDeviceType;
  Duration _uptime = Duration.zero;
  int _freeMemory = 0;
  int _currentFrame = 0;
  final StringBuffer _buffer = StringBuffer();
  bool _isListening = false;

  // FIFO queue for complete lines
  final Queue<String> _readQueue = Queue<String>();

  // Callback for processing incoming data
  Function(String)? _onDataCallback;

  FxDevice({
    required SerialPort port,
    int baudRate = 19200,
    String displayName = 'Unknown Device',
    String fxDeviceType = 'Unknown Type',
    Function(String)? onDataCallback, // Optional callback
  }) : _port = port,
       _baudRate = baudRate,
       _displayName = displayName,
       _fxDeviceType = fxDeviceType {
    _onDataCallback = onDataCallback;
    _initializeSerialPort();

    // Call the callback if provided
    if (_onDataCallback != null) {
      dataStream.listen((data) {
        _onDataCallback!(data);
      });
    }

    _startListening();
  }

  void _initializeSerialPort() {
    if (!_port.isOpen) {
      try {
        _port.openReadWrite();
      } catch (e) {
        print('Failed to open port ${_port.name}: $e');
        throw Exception('Could not open serial port');
      }
    }
    final config =
        _port.config
          ..baudRate = _baudRate
          ..bits = 8
          ..parity = SerialPortParity.none
          ..stopBits = 1;
    _port.config = config;
  }

  void _startListening() {
    if (_isListening) return;

    final reader = SerialPortReader(_port);
    _dataSubscription = reader.stream.listen(
      (data) {
        try {
          _rawDataController.add(data); // Emit raw data to stream
          final decoded = utf8.decode(data, allowMalformed: true);
          _buffer.write(decoded);
          _processBuffer();
          _updateUptime();
        } catch (e) {
          print('Error decoding data from ${_port.name}: $e');
          _dataController.addError('Data decode error: $e');
        }
      },
      onError: (error) {
        print('Stream error on ${_port.name}: $error');
        _dataController.addError('Stream error: $error');
        _handleDisconnect();
      },
      onDone: () {
        print('Stream closed unexpectedly on ${_port.name}');
        _dataController.addError('Stream closed');
        _handleDisconnect();
      },
      cancelOnError: false,
    );

    _isListening = true;
    print('Started listening on ${_port.name}');
  }

  void _processBuffer() {
    String bufferContent = _buffer.toString();

    while (true) {
      final newlineIndex = bufferContent.indexOf('\n');
      if (newlineIndex == -1) break;

      final line = bufferContent.substring(0, newlineIndex).trim();
      if (line.isNotEmpty) {
        _readQueue.add(line);
        _dataController.add(line);
      }

      bufferContent = bufferContent.substring(newlineIndex + 1);
      _buffer.clear();
      _buffer.write(bufferContent);
    }
  }

  void _handleDisconnect() async {
    if (!_port.isOpen && _isListening) {
      print('Port ${_port.name} closed unexpectedly, attempting to reopen...');
      await stopListening();
      try {
        _initializeSerialPort();
        _startListening();
        print('Reconnected successfully to ${_port.name}');
      } catch (e) {
        print('Reconnection failed for ${_port.name}: $e');
        _dataController.addError('Reconnection failed: $e');
      }
    }
  }

  void _updateUptime() {
    _uptime += const Duration(milliseconds: 100);
  }

  // Getters
  SerialPort get port => _port;
  Stream<String> get dataStream => _dataController.stream; // Lines
  Stream<Uint8List> get rawDataStream => _rawDataController.stream; // Raw bytes
  int get baudRate => _baudRate;
  String get displayName => _displayName;
  String get fxDeviceType => _fxDeviceType;
  Duration get uptime => _uptime;
  int get freeMemory => _freeMemory;
  int get currentFrame => _currentFrame;
  bool get isListening => _isListening;
  int get queueLength => _readQueue.length;

  // Setters
  set baudRate(int value) {
    _baudRate = value;
    if (_port.isOpen) {
      final config = _port.config..baudRate = value;
      _port.config = config;
    }
  }

  set displayName(String value) => _displayName = value;
  set fxDeviceType(String value) => _fxDeviceType = value;
  set uptime(Duration value) => _uptime = value;
  set freeMemory(int value) => _freeMemory = value;
  set currentFrame(int value) => _currentFrame = value;

  set onDataCallback(Function(String)? callback) {
    if (_onDataCallback != null) {
      return;
    }
    _onDataCallback = callback;
    dataStream.listen((data) {
      _onDataCallback!(data);
    });
  }

  void write(String data) {
    if (!_port.isOpen) throw Exception('Port ${_port.name} is not open');
    final bytes = Uint8List.fromList(utf8.encode(data));
    _port.write(bytes);
  }

  Future<String> readLine({
    String delimiter = '\n',
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final completer = Completer<String>();
    StreamSubscription<String>? subscription;

    if (_readQueue.isNotEmpty) {
      final line = _readQueue.removeFirst();
      print('Read from queue: $line');
      return line;
    }

    subscription = _dataController.stream.listen(
      (line) {
        if (!completer.isCompleted) {
          final queuedLine = _readQueue.removeFirst();
          print('Read from queue (stream): $queuedLine');
          completer.complete(queuedLine);
          subscription?.cancel();
        }
      },
      onError: (error) {
        completer.completeError(error);
        subscription?.cancel();
      },
    );

    try {
      return await completer.future.timeout(
        timeout,
        onTimeout: () {
          if (_readQueue.isNotEmpty) {
            final line = _readQueue.removeFirst();
            print('Read from queue (timeout): $line');
            return line;
          }
          throw TimeoutException('Read timeout on ${_port.name}');
        },
      );
    } finally {
      await subscription?.cancel();
    }
  }

  Future<String> sendCommand(
    String command, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    write(command.endsWith('\n') ? command : '$command\n');
    return readLine(timeout: timeout);
  }

  Future<void> stopListening() async {
    if (_isListening) {
      await _dataSubscription?.cancel();
      _dataSubscription = null;
      _isListening = false;
      print('Stopped listening on ${_port.name}');
    }
  }

  Future<void> dispose() async {
    await stopListening();
    await _dataController.close();
    await _rawDataController.close();
    if (_port.isOpen) _port.close();
    _buffer.clear();
    _readQueue.clear();
    print('Device disposed: ${_port.name}');
  }

  bool get isConnected => _port.isOpen;
}
