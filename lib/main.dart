import 'dart:convert';

import 'package:dmdfx/fx.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'fxdevice.dart';

void main() {
  runApp(DMDfxApp());
}

class DMDfxApp extends StatelessWidget {
  const DMDfxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DMDfx',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.greenAccent,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  final FxDeviceController fx = FxDeviceController();
  // void _openPort(String devicePath) {
  //   SerialPort port = SerialPort(devicePath);
  //   port.openReadWrite();
  //   SerialPortConfig config = port.config;
  //   config.baudRate = 19200;
  //   port.config = config;

  //   SerialPortReader reader = SerialPortReader(port);

  //   _openedPorts[devicePath] = reader;
  // }

  // void _closePort(String devicePath) {
  //   SerialPortReader? reader = _openedPorts[devicePath];
  //   if (reader == null) {
  //     return;
  //   }
  //   reader.port.close();
  //   _openedPorts.remove(devicePath);
  // }

  // Future<String> _getFxModelNumber(String devicePath) async {
  //   SerialPortReader? reader = _openedPorts[devicePath];
  //   if (reader == null) {
  //     return Future.value("Error: Port not open");
  //   }

  //   reader.port.write(utf8.encode("GET\n"));
  //   // buffer to accumulate data

  //   // wait until we get a string beginning in modelno=
  //   await for (var raw in reader.stream) {
  //     String data = '';
  //     try {
  //       data = utf8.decode(raw);
  //     } on FormatException {
  //       continue;
  //     }
  //     buffer += data;

  //     // check if buffer contains a complete line
  //     if (buffer.contains('\n')) {
  //       List<String> lines = buffer.split('\n');
  //       for (var line in lines.getRange(0, lines.length - 1)) {
  //         print(line);
  //         if (line.startsWith('modelno=')) {
  //           return line;
  //         }
  //       }
  //       // keep the last incomplete line in the buffer
  //       buffer = lines.last;
  //     }
  //   }
  //   await Future.delayed(Duration(seconds: 10));
  //   return "";
  // }

  void testing() async {
    // Discover devices
    print('Scanning for FX devices...');
    final discoveredPorts = await fx.discoverDevices();
    print('Found devices on ports: $discoveredPorts');

    // Access a device
    if (discoveredPorts.isNotEmpty) {
      final device = fx.getDevice(discoveredPorts.first);
      if (device != null) {
        print('Device: ${device.displayName}, Type: ${device.fxDeviceType}');

        // Listen to data
        device.dataStream.listen(
          (data) => print('Data: $data'),
          onError: (e) => print('Error: $e'),
        );

        // Send a command
        try {
          final response = await device.sendCommand('STATUS');
          print('Status: $response');
        } catch (e) {
          print('Command failed: $e');
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    testing();
  }

  @override
  void dispose() {
    super.dispose();
    fx.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text.rich(
          TextSpan(
            text: 'DMD',
            children: <TextSpan>[
              TextSpan(
                text: 'fx',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
      ),
      body: Row(
        children: [
          Flexible(
            flex: 1,
            child: Material(
              elevation: 2,
              child: ListView(
                children: [
                  Card(
                    child: SizedBox.fromSize(
                      size: Size(double.infinity, 128),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10.0),
                        onTap: () {
                          print("Tapped");
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Row(
                            children: [
                              FlutterLogo(size: 64),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "DMDfx Panel 32x32",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 18),
                                    ),
                                    Text(
                                      "Fw Ver: 1.0.0",
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    Text(
                                      "Serial: 1234567890",
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    Text(
                                      "Port: COM3",
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          VerticalDivider(thickness: 1),
          Flexible(
            flex: 3,
            // child: Center(child: Text("Select a connected DMDfx device")),
            child: Card(
              elevation: 3,
              child: Column(
                children: [
                  AppBar(
                    elevation: 4,
                    title: Text("DMDfx Device Demo"),
                    actionsPadding: EdgeInsets.all(8.0),
                    centerTitle: true,
                    actions: [
                      IconButton(icon: Icon(Icons.close), onPressed: () {}),
                    ],
                  ),
                  Expanded(child: Text("DMDfx")),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
