import 'dart:async';
import 'dart:typed_data';

import 'package:dmdfx/device.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

Future<bool> isPortAccessible(String portName) async {
  try {
    // Simple check - try to create a SerialPort object and see if we can get basic info
    final port = SerialPort(portName);

    // Try to open read-only first as a test
    bool canOpen = false;
    try {
      canOpen = port.openRead();
      if (canOpen) {
        port.close();
        return true;
      }
    } catch (e) {
      // If read-only fails, the port likely doesn't exist or isn't accessible
      return false;
    }

    return canOpen;
  } catch (e) {
    print('Port $portName accessibility check failed: $e');
    return false;
  }
}

bool configureOpenPort(SerialPort port) {
  try {
    final config = SerialPortConfig();
    config.baudRate = 19200;
    config.bits = 8;
    config.parity = SerialPortParity.none;
    config.stopBits = 1;
    config.dtr = 1;
    config.setFlowControl(SerialPortFlowControl.none);

    port.config = config;
    return true;
  } catch (e) {
    print('Error configuring open port ${port.name}: $e');
    return false;
  }
}

Future<String?> fxQuery(FxDevice dev, String inp, String out) async {
  try {
    // Small delay to ensure port is ready
    await Future.delayed(Duration(milliseconds: 50));

    // Send query command
    final command = '$inp\n';
    final data = Uint8List.fromList(command.codeUnits);

    dev.port.flush();
    int bytesWritten = dev.port.write(data);
    if (bytesWritten != data.length) {
      print('Warning: Only wrote $bytesWritten of ${data.length} bytes');
    }

    // Force transmission
    dev.port.drain();

    // Use dev.attachCallback(out) to wait for a response
    final completer = Completer<String?>();
    String? callbackId;
    // Attach the callback and handle the response
    callbackId = dev.attachCallback((String key, String response) {
      if (key == out) {
        completer.complete(response);
      }
    });

    // Timeout after 2 seconds if no response
    Future.delayed(Duration(seconds: 2)).then((_) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    });

    // Remove the callback after the future completes
    final result = await completer.future;
    dev.removeCallback(callbackId);
    return result;
  } catch (e) {
    print('Error querying device model on ${dev.port.name}: $e');
    return null;
  }
}

Future<String?> portQuery(SerialPort port, String inp, String out) async {
  try {
    // Small delay to ensure port is ready
    await Future.delayed(Duration(milliseconds: 50));

    // Send query command
    final command = '$inp\n';
    final data = Uint8List.fromList(command.codeUnits);

    port.flush();
    int bytesWritten = port.write(data);
    if (bytesWritten != data.length) {
      print('Warning: Only wrote $bytesWritten of ${data.length} bytes');
    }

    // Force transmission
    port.drain();

    // Wait for response with timeout
    final completer = Completer<String?>();
    final buffer = StringBuffer();
    bool responseReceived = false;

    Timer? timeout = Timer(Duration(seconds: 1), () {
      if (!completer.isCompleted) {
        print('Timeout waiting for response from ${port.name}, $inp');
        completer.complete(null);
      }
    });

    // Read response until we see \r\n
    final startTime = DateTime.now();
    while (!responseReceived &&
        DateTime.now().difference(startTime).inSeconds < 1) {
      try {
        final available = port.bytesAvailable;
        if (available > 0) {
          final data = port.read(available);
          if (data.isNotEmpty) {
            final response = String.fromCharCodes(data);
            buffer.write(response);

            // Check if buffer contains a full line ending with \r\n
            final bufferStr = buffer.toString();
            int lineEnd = bufferStr.indexOf('\r\n');
            if (lineEnd != -1) {
              final line = bufferStr.substring(0, lineEnd);
              print(
                'Received from ${port.name}: ${line.replaceAll('\n', '\\n').replaceAll('\r', '\\r')}',
              );
              if (line.contains('$out=')) {
                final modelMatch = RegExp('$out=([^\\r\\n]+)').firstMatch(line);
                if (modelMatch != null) {
                  timeout.cancel();
                  responseReceived = true;
                  if (!completer.isCompleted) {
                    completer.complete(modelMatch.group(1)?.trim());
                  }
                  break;
                }
              }
              // Remove processed line from buffer
              buffer.clear();
              buffer.write(bufferStr.substring(lineEnd + 2));
            }
          }
        }
        // Small delay to avoid busy waiting
        await Future.delayed(Duration(milliseconds: 10));
      } catch (e) {
        print('Error reading from ${port.name}: $e');
        break;
      }
    }

    if (!responseReceived && !completer.isCompleted) {
      timeout.cancel();
      completer.complete(null);
    }

    return await completer.future;
  } catch (e) {
    print('Error querying device model on ${port.name}: $e');
    return null;
  }
}
