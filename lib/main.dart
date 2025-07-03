import 'package:dmdfx/avrdude_downloader.dart';
import 'package:dmdfx/avrdude_installui.dart';
import 'package:dmdfx/constants.dart';
import 'package:dmdfx/device.dart';
import 'package:dmdfx/device_query.dart';
import 'package:dmdfx/util.dart';
import 'package:dmdfx/video_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:proper_filesize/proper_filesize.dart';
import 'dart:async';

void main() {
  runApp(DMDfxApp());
}

class DMDfxApp extends StatelessWidget {
  const DMDfxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DMDfx Manager',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.dark,
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: DMDfxHomePage(),
    );
  }
}

class DMDfxHomePage extends StatefulWidget {
  const DMDfxHomePage({super.key});

  @override
  DMDfxHomePageState createState() => DMDfxHomePageState();
}

class DMDfxHomePageState extends State<DMDfxHomePage> {
  List<FxDevice> discoveredDevices = [];
  bool isScanning = false;
  FxDevice? selectedDevice;
  Timer? _deviceCheckTimer;

  Future<bool>? reloadFuture;

  @override
  void initState() {
    super.initState();
    checkAvrdudeStatus(context);
    discoverDevices();

    // Start periodic check every 2 seconds
    _deviceCheckTimer = Timer.periodic(Duration(seconds: 2), (_) {
      checkSelectedDeviceStillConnected();
    });
  }

  @override
  void dispose() {
    _deviceCheckTimer?.cancel();
    super.dispose();
  }

  void _showSettings() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FutureBuilder<bool>(
                future: getAvrdudeExists(avrdudeVersion),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return ListTile(
                      leading: Icon(Icons.system_update),
                      title: Text('Please Wait...'),
                      subtitle: Text('Checking AVRDUDE status...'),
                      enabled: false,
                    );
                  } else if (snapshot.data == false) {
                    return ListTile(
                      leading: Icon(Icons.system_update),
                      title: Text('Install AVRDUDE'),
                      subtitle: Text('Tool for firmware updates'),
                      onTap: () {
                        Navigator.of(context).pop();
                        showAvrdudePrompt(context, false);
                      },
                    );
                  } else {
                    return ListTile(
                      leading: Icon(Icons.system_update),
                      title: Text('Uninstall AVRDUDE'),
                      subtitle: Text('Tool for firmware updates'),
                      onTap: () {
                        Navigator.of(context).pop();
                        showAvrdudeRemovePrompt(context);
                      },
                    );
                  }
                },
              ),
              ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('About'),
                subtitle: Text('About DMDfx Manager'),
                onTap: () {
                  showAboutDialog(
                    context: context,
                    applicationVersion: '1.0.0',
                    applicationIcon: Icon(
                      Icons.usb,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    children: [
                      Text('A tool for managing DMDfx-powered LED displays.'),
                    ],
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              child: Text('Close'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  Future<void> checkSelectedDeviceStillConnected() async {
    final currentPorts = SerialPort.availablePorts.toSet();

    // Filter out devices no longer present
    final removedPorts =
        discoveredDevices
            .where((d) => !currentPorts.contains(d.portName))
            .map((d) => d.portName)
            .toList();

    if (removedPorts.isNotEmpty) {
      print('Removed devices: $removedPorts');

      setState(() {
        discoveredDevices.removeWhere((d) => removedPorts.contains(d.portName));

        // If the selected device was removed, clear selection
        if (selectedDevice != null &&
            removedPorts.contains(selectedDevice!.portName)) {
          selectedDevice = null;
        }
      });
    }
  }

  Future<void> discoverDevices() async {
    setState(() {
      isScanning = true;
      discoveredDevices.clear();
      _closeDevice();
    });

    try {
      // Get all available serial ports
      final availablePorts = SerialPort.availablePorts;
      print('Found ${availablePorts.length} serial ports: $availablePorts');

      for (String portName in availablePorts) {
        try {
          final port = SerialPort(portName);

          // Check if port exists and is accessible before doing anything
          if (!await isPortAccessible(portName)) {
            print('Port $portName is not accessible, skipping...');
            continue;
          }

          // Try to open the port first
          bool opened = false;
          try {
            opened = port.openReadWrite();
            if (!opened) {
              final error = SerialPort.lastError;
              print(
                'Failed to open port $portName: ${error?.message ?? 'Unknown error'}',
              );
              continue;
            }
          } catch (e) {
            print('Exception opening port $portName: $e');
            continue;
          }

          // Configure port settings after opening
          if (opened && !configureOpenPort(port)) {
            print('Failed to configure port $portName, skipping...');
            try {
              port.close();
            } catch (e) {
              print('Error closing port $portName after config failure: $e');
            }
            continue;
          }

          if (opened) {
            print('Successfully opened port $portName, querying model...');
            String? modelNumber = await portQuery(port, "X", "modelno");
            String? cpu = await portQuery(port, "I", "board_id");
            String? version = await portQuery(port, "V", "version");
            String? resolution = await portQuery(port, "qR", "res");

            if (modelNumber != null &&
                cpu != null &&
                version != null &&
                resolution != null) {
              print('Found device on $portName with model: $modelNumber, $cpu');
              setState(() {
                discoveredDevices.add(
                  FxDevice(
                    port: port,
                    portName: portName,
                    modelNumber: modelNumber,
                    cpu: cpu,
                    version: version,
                    resolution: resolution,
                  ),
                );
              });
            } else {
              print('No valid response from device on $portName');
            }

            try {
              port.close();
            } catch (e) {
              print('Error closing port $portName: $e');
            }
          }
        } catch (e) {
          print('Error with port $portName: $e');
        }

        // Small delay between port checks to avoid overwhelming the system
        await Future.delayed(Duration(milliseconds: 100));
      }
    } catch (e) {
      print('Error discovering devices: $e');
    }

    setState(() {
      isScanning = false;
    });
  }

  void selectDevice(FxDevice device) {
    if (selectedDevice != null &&
        device.portName == selectedDevice!.portName &&
        selectedDevice!.port.isOpen) {
      return;
    }
    setState(() {
      if (selectedDevice != null &&
          device.portName != selectedDevice!.portName) {
        selectedDevice!.close();
      }
      selectedDevice = device;
      selectedDevice!.open();
      reloadFuture = selectedDevice!.config.reload(selectedDevice!);
    });
  }

  void _closeDevice() {
    setState(() {
      if (selectedDevice != null) {
        if (selectedDevice!.close()) {
          selectedDevice = null;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("DMDfx Manager"),
        actions: [
          IconButton(onPressed: _showSettings, icon: Icon(Icons.settings)),
        ],
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      ),
      body: Row(
        children: [
          // Sidebar
          Container(
            constraints: BoxConstraints(minWidth: 240, maxWidth: 280),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
            ),
            child: Column(
              children: [
                // Header
                Container(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Serial Devices',
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color:
                              Theme.of(
                                context,
                              ).colorScheme.onSecondaryContainer,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.refresh,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        onPressed: isScanning ? null : discoverDevices,
                      ),
                    ],
                  ),
                ),

                // Scanning indicator
                if (isScanning)
                  Container(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text('Scanning for devices...'),
                      ],
                    ),
                  ),

                // Device list
                Expanded(
                  child: ListView.builder(
                    itemCount: discoveredDevices.length,
                    itemBuilder: (context, index) {
                      final device = discoveredDevices[index];
                      final isSelected = selectedDevice == device;

                      return Container(
                        margin: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color:
                              isSelected
                                  ? Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer
                                  : Theme.of(context).colorScheme.surface,
                          border: Border.all(
                            color:
                                isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).dividerColor,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListTile(
                          leading: Icon(Icons.usb),
                          title: Text(
                            device.modelNumber,
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text('Port: ${device.portName}'),
                          onTap: () => selectDevice(device),
                        ),
                      );
                    },
                  ),
                ),

                // Status bar
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      SizedBox(width: 8),
                      Text(
                        '${discoveredDevices.length} device(s) found',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Main content area
          Expanded(
            child: Container(
              padding: EdgeInsets.all(16),
              child:
                  selectedDevice != null
                      ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Card(
                            elevation: 2,
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.display_settings,
                                    size: 48,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                  SizedBox(width: 16),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        selectedDevice!.modelNumber,
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Port: ${selectedDevice!.portName}',
                                        style: TextStyle(fontSize: 16),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Version: ${selectedDevice!.version}',
                                        style: TextStyle(fontSize: 16),
                                      ),
                                    ],
                                  ),
                                  Spacer(),
                                  Column(
                                    children: [
                                      IconButton(
                                        onPressed: () {
                                          _closeDevice();
                                        },
                                        icon: Icon(Icons.close),
                                      ),
                                      IconButton(
                                        onPressed: () {
                                          showDialog(
                                            context: context,
                                            builder: (BuildContext context) {
                                              final port = selectedDevice!.port;
                                              return AlertDialog(
                                                title: Text('Device Info'),
                                                content: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    TextField(
                                                      controller: TextEditingController(
                                                        text:
                                                            'Model: ${selectedDevice!.modelNumber}\n'
                                                            'Resolution: ${selectedDevice!.resolution}\n'
                                                            'Port: ${selectedDevice!.portName}\n'
                                                            'CPU: ${selectedDevice!.cpu}\n'
                                                            'Uptime: ${formatUptime(selectedDevice!.uptimeMs)}\n'
                                                            'Version: ${selectedDevice!.version}\n'
                                                            'VID: 0x${port.vendorId?.toRadixString(16).padLeft(4, '0') ?? "----"}\n'
                                                            'PID: 0x${port.productId?.toRadixString(16).padLeft(4, '0') ?? "----"}\n'
                                                            'Serial Number: ${port.serialNumber ?? "Unknown"}\n'
                                                            'Manufacturer: ${port.manufacturer ?? "Unknown"}\n'
                                                            'Description: ${port.description ?? "Unknown"}',
                                                      ),
                                                      maxLines: null,
                                                      readOnly: true,
                                                      decoration:
                                                          InputDecoration(
                                                            border:
                                                                InputBorder
                                                                    .none,
                                                          ),
                                                      style: TextStyle(
                                                        fontFamily: 'monospace',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                actions: [
                                                  TextButton(
                                                    child: Text('Close'),
                                                    onPressed:
                                                        () =>
                                                            Navigator.of(
                                                              context,
                                                            ).pop(),
                                                  ),
                                                ],
                                              );
                                            },
                                          );
                                        },
                                        icon: Icon(Icons.info),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(height: 8),
                          Expanded(
                            child: Card(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  16,
                                ), // Match ClipRRect's radius
                              ),
                              clipBehavior:
                                  Clip.antiAlias, // Ensure content inside Card is clipped
                              child: DefaultTabController(
                                length: 3,
                                child: Column(
                                  children: [
                                    TabBar(
                                      labelColor:
                                          Theme.of(context).colorScheme.primary,
                                      unselectedLabelColor:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                      indicator: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      tabs: [
                                        Tab(
                                          text: 'Configure',
                                          icon: Icon(Icons.settings),
                                        ),
                                        Tab(
                                          text: 'Editor',
                                          icon: Icon(Icons.edit),
                                        ),
                                        Tab(
                                          text: 'Storage',
                                          icon: Icon(Icons.sd_card),
                                        ),
                                      ],
                                      onTap: (index) {
                                        if (index == 0) {
                                          setState(() {
                                            reloadFuture = selectedDevice!
                                                .config
                                                .reload(selectedDevice!);
                                          });
                                        } else if (index == 2) {
                                          setState(() {
                                            reloadFuture = selectedDevice!
                                                .memory
                                                .reload(selectedDevice!);
                                          });
                                        }
                                      },
                                    ),
                                    Expanded(
                                      child: TabBarView(
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.all(16.0),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Text(
                                                      'Device Configuration',
                                                      style: TextStyle(
                                                        fontSize: 18,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                    Spacer(),
                                                    OutlinedButton.icon(
                                                      onPressed: () {
                                                        if (selectedDevice!
                                                            .port
                                                            .isOpen) {
                                                          selectedDevice!
                                                              .rewind();
                                                        }
                                                      },
                                                      icon: Icon(
                                                        Icons.fast_rewind,
                                                      ),
                                                      label: Text('Rewind'),
                                                    ),
                                                    SizedBox(width: 8),
                                                    OutlinedButton.icon(
                                                      onPressed: () {
                                                        setState(() {
                                                          // Reset and assign new Future in one setState
                                                          reloadFuture =
                                                              selectedDevice!
                                                                  .config
                                                                  .reload(
                                                                    selectedDevice!,
                                                                  );
                                                        });
                                                      },
                                                      icon: Icon(Icons.refresh),
                                                      label: Text('Reload'),
                                                    ),
                                                    SizedBox(width: 8),
                                                    FilledButton.icon(
                                                      onPressed: () {
                                                        if (selectedDevice!
                                                            .port
                                                            .isOpen) {
                                                          selectedDevice!
                                                              .save();
                                                        }
                                                      },
                                                      icon: Icon(Icons.save),
                                                      label: Text('Save'),
                                                    ),
                                                  ],
                                                ),
                                                SizedBox(height: 24),
                                                FutureBuilder(
                                                  future: reloadFuture,
                                                  builder: (
                                                    BuildContext context,
                                                    AsyncSnapshot snapshot,
                                                  ) {
                                                    if (snapshot
                                                            .connectionState ==
                                                        ConnectionState
                                                            .waiting) {
                                                      return Expanded(
                                                        child: Center(
                                                          child:
                                                              CircularProgressIndicator(),
                                                        ),
                                                      );
                                                    } else if (snapshot
                                                        .hasError) {
                                                      return Text(
                                                        'Error: ${snapshot.error}',
                                                      );
                                                    } else if (snapshot
                                                        .hasData) {
                                                      return Expanded(
                                                        child: ListView(
                                                          children: [
                                                            Row(
                                                              children: [
                                                                Text(
                                                                  "Brightness",
                                                                ),
                                                                Expanded(
                                                                  child: Listener(
                                                                    onPointerUp: (
                                                                      _,
                                                                    ) async {
                                                                      // Only submit change on mouse up
                                                                      await selectedDevice!.config.setBrightness(
                                                                        selectedDevice!,
                                                                        (selectedDevice!.config.brightness)
                                                                            .round(),
                                                                      );
                                                                    },
                                                                    child: Slider(
                                                                      divisions:
                                                                          255,
                                                                      value:
                                                                          selectedDevice!
                                                                              .config
                                                                              .brightness /
                                                                          255,
                                                                      onChanged: (
                                                                        value,
                                                                      ) {
                                                                        setState(() {
                                                                          selectedDevice!
                                                                              .config
                                                                              .brightness = (value *
                                                                                      255)
                                                                                  .round();
                                                                        });
                                                                      },
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                            Divider(),
                                                            Row(
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .spaceBetween,
                                                              children: [
                                                                Text(
                                                                  "Milliseconds per Page",
                                                                  style: TextStyle(
                                                                    fontSize:
                                                                        16,
                                                                  ), // Optional: Ensure text size is reasonable
                                                                ),
                                                                SizedBox(
                                                                  width: 16,
                                                                ), // Replace Spacer with SizedBox for controlled spacing
                                                                Flexible(
                                                                  child: ConstrainedBox(
                                                                    constraints: BoxConstraints(
                                                                      minWidth:
                                                                          120,
                                                                      maxWidth:
                                                                          200,
                                                                    ),
                                                                    child: TextField(
                                                                      controller:
                                                                          TextEditingController(
                                                                            text:
                                                                                selectedDevice!.config.pageTime.toString(),
                                                                          ),
                                                                      keyboardType:
                                                                          TextInputType
                                                                              .number,
                                                                      inputFormatters: [
                                                                        FilteringTextInputFormatter
                                                                            .digitsOnly,
                                                                        TextInputFormatter.withFunction((
                                                                          oldValue,
                                                                          newValue,
                                                                        ) {
                                                                          if (newValue
                                                                              .text
                                                                              .isEmpty) {
                                                                            return newValue;
                                                                          }
                                                                          final intValue = int.tryParse(
                                                                            newValue.text,
                                                                          );
                                                                          if (intValue ==
                                                                                  null ||
                                                                              intValue <
                                                                                  0 ||
                                                                              intValue >
                                                                                  25000) {
                                                                            return oldValue;
                                                                          }
                                                                          return newValue;
                                                                        }),
                                                                      ],
                                                                      decoration: InputDecoration(
                                                                        border:
                                                                            OutlineInputBorder(),
                                                                        suffix:
                                                                            Text(
                                                                              "ms",
                                                                            ),
                                                                      ),
                                                                      onSubmitted: (
                                                                        value,
                                                                      ) async {
                                                                        final intValue =
                                                                            int.tryParse(
                                                                              value,
                                                                            );
                                                                        if (intValue !=
                                                                                null &&
                                                                            intValue >=
                                                                                0 &&
                                                                            intValue <=
                                                                                25000) {
                                                                          await selectedDevice!.config.setPageTime(
                                                                            selectedDevice!,
                                                                            intValue,
                                                                          );
                                                                          setState(
                                                                            () {
                                                                              selectedDevice!.config.pageTime = intValue;
                                                                            },
                                                                          );
                                                                        }
                                                                      },
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                            Divider(),
                                                            Row(
                                                              children: [
                                                                Text(
                                                                  "Time Bar",
                                                                ),
                                                                Spacer(),
                                                                SegmentedButton(
                                                                  segments: [
                                                                    ButtonSegment(
                                                                      value: 2,
                                                                      label: Text(
                                                                        "Top",
                                                                      ),
                                                                      icon: Icon(
                                                                        Icons
                                                                            .align_vertical_top,
                                                                      ),
                                                                    ),
                                                                    ButtonSegment(
                                                                      value: 1,
                                                                      label: Text(
                                                                        "Bottom",
                                                                      ),
                                                                      icon: Icon(
                                                                        Icons
                                                                            .align_vertical_bottom,
                                                                      ),
                                                                    ),
                                                                    ButtonSegment(
                                                                      value: 0,
                                                                      label: Text(
                                                                        "Disabled",
                                                                      ),
                                                                      icon: Icon(
                                                                        Icons
                                                                            .block,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                  selected: {
                                                                    selectedDevice!
                                                                        .config
                                                                        .timeBarPos,
                                                                  },
                                                                  emptySelectionAllowed:
                                                                      false,
                                                                  multiSelectionEnabled:
                                                                      false,
                                                                  onSelectionChanged: (
                                                                    Set<int>
                                                                    selection,
                                                                  ) {
                                                                    print(
                                                                      selection
                                                                          .first,
                                                                    );
                                                                    setState(() {
                                                                      selectedDevice!.config.setTimebarPos(
                                                                        selectedDevice!,
                                                                        selection
                                                                            .first,
                                                                      );
                                                                    });
                                                                  },
                                                                ),
                                                              ],
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    } else {
                                                      return Text(
                                                        'No data available',
                                                      );
                                                    }
                                                  },
                                                ),
                                              ],
                                            ),
                                          ),
                                          Center(
                                            child: VideoEditor(
                                              device: selectedDevice!,
                                            ),
                                          ),
                                          Center(
                                            child: Padding(
                                              padding: const EdgeInsets.all(
                                                16.0,
                                              ),
                                              child: Column(
                                                children: [
                                                  Row(
                                                    children: [
                                                      Text(
                                                        'Storage Information',
                                                        style: TextStyle(
                                                          fontSize: 18,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                      Spacer(),
                                                      OutlinedButton.icon(
                                                        onPressed: () {
                                                          setState(() {
                                                            // Reset and assign new Future in one setState
                                                            reloadFuture =
                                                                selectedDevice!
                                                                    .memory
                                                                    .reload(
                                                                      selectedDevice!,
                                                                    );
                                                          });
                                                        },
                                                        icon: Icon(
                                                          Icons.refresh,
                                                        ),
                                                        label: Text('Reload'),
                                                      ),
                                                    ],
                                                  ),
                                                  SizedBox(height: 24),
                                                  FutureBuilder(
                                                    future: reloadFuture,
                                                    builder: (
                                                      BuildContext context,
                                                      AsyncSnapshot snapshot,
                                                    ) {
                                                      if (snapshot
                                                              .connectionState ==
                                                          ConnectionState
                                                              .waiting) {
                                                        return Expanded(
                                                          child: Center(
                                                            child:
                                                                CircularProgressIndicator(),
                                                          ),
                                                        );
                                                      } else if (snapshot
                                                          .hasError) {
                                                        return Text(
                                                          'Error: ${snapshot.error}',
                                                        );
                                                      } else if (snapshot
                                                          .hasData) {
                                                        return Expanded(
                                                          child: ListView(
                                                            children: [
                                                              Card(
                                                                color:
                                                                    Theme.of(
                                                                          context,
                                                                        )
                                                                        .colorScheme
                                                                        .surfaceContainerHigh,
                                                                child: Padding(
                                                                  padding:
                                                                      const EdgeInsets.all(
                                                                        16.0,
                                                                      ),
                                                                  child: Row(
                                                                    children: [
                                                                      Icon(
                                                                        Icons
                                                                            .sd_storage,
                                                                        size:
                                                                            64,
                                                                        color:
                                                                            Theme.of(
                                                                              context,
                                                                            ).colorScheme.primary,
                                                                      ),
                                                                      SizedBox(
                                                                        width:
                                                                            12,
                                                                      ),
                                                                      Column(
                                                                        crossAxisAlignment:
                                                                            CrossAxisAlignment.start,
                                                                        children: [
                                                                          Text(
                                                                            "SD Card",
                                                                            style: TextStyle(
                                                                              fontSize:
                                                                                  18,
                                                                              fontWeight:
                                                                                  FontWeight.bold,
                                                                              color:
                                                                                  Theme.of(
                                                                                    context,
                                                                                  ).colorScheme.primary,
                                                                            ),
                                                                          ),
                                                                          SizedBox(
                                                                            height:
                                                                                8,
                                                                          ),
                                                                          Text(
                                                                            "${FileSize.fromBytes(selectedDevice!.memory.sdFree).toString(decimals: 2)} Free of ${FileSize.fromBytes(selectedDevice!.memory.sdTotal).toString(decimals: 2)}",
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        );
                                                      } else {
                                                        return Text(
                                                          'No data available',
                                                        );
                                                      }
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                      : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.asset("assets/plug.png"),
                            SizedBox(height: 16),
                            Text(
                              'No device selected',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Select a device from the sidebar to view details',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      ),
            ),
          ),
        ],
      ),
    );
  }
}
