import 'dart:convert';
import 'package:dmdfx/fx.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'fxdevice.dart';

// Providers
final fxDeviceControllerProvider = Provider<FxDeviceController>((ref) {
  final controller = FxDeviceController();
  _initializeController(controller);

  // Run cleanup when provider is disposed (hot restart or app close)
  ref.onDispose(() {
    print('FxDeviceController provider disposing... Running cleanup');
    controller.dispose(); // Already handles device cleanup
  });

  return controller;
});

// Initialization function
void _initializeController(FxDeviceController controller) async {
  print('Initializing FxDeviceController...');
  final discoveredPorts = await controller.discoverDevices();
  print('Initial discovery found devices on ports: $discoveredPorts');
  if (discoveredPorts.isNotEmpty) {
    final device = controller.getDevice(discoveredPorts.first);
    if (device != null) {
      print(
        'Initial device: ${device.displayName}, Type: ${device.fxDeviceType}',
      );
      device.onDataCallback = (data) => print('Initial Data: $data');
    }
  }
}

final discoveredDevicesProvider = FutureProvider<List<String>>((ref) => []);

final selectedDeviceProvider = StateProvider<FxDevice?>((ref) => null);

void main() {
  runApp(ProviderScope(child: DMDfxApp()));
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

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Register lifecycle observer
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // Unregister observer
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fxController = ref.watch(fxDeviceControllerProvider);
    final devicesAsync = ref.watch(discoveredDevicesProvider);
    final selectedDevice = ref.watch(selectedDeviceProvider);

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
            child: Column(
              children: [
                ElevatedButton.icon(
                  onPressed:
                      !FxDeviceController.discoveryRunning
                          ? () => ref.refresh(discoveredDevicesProvider)
                          : null,
                  label: Text("Reload"),
                  icon: Icon(Icons.refresh),
                ),
                Expanded(
                  child: Material(
                    elevation: 2,
                    child: devicesAsync.when(
                      data:
                          (ports) => ListView.builder(
                            itemCount: ports.length,
                            itemBuilder: (context, index) {
                              final device = fxController.getDevice(
                                ports[index],
                              );
                              return FxDeviceCard(
                                device: device,
                                onTap: () {
                                  ref
                                      .read(selectedDeviceProvider.notifier)
                                      .state = device;
                                },
                              );
                            },
                          ),
                      loading: () => Center(child: CircularProgressIndicator()),
                      error: (err, stack) => Center(child: Text('Error: $err')),
                    ),
                  ),
                ),
              ],
            ),
          ),
          VerticalDivider(thickness: 1),
          Flexible(
            flex: 3,
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Connect to an Fx device to view info",
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                      Image.asset("assets/plug.png", height: 280),
                    ],
                  ),
                ),
                AnimatedSwitcher(
                  duration: Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) {
                    return SlideTransition(
                      position: Tween<Offset>(
                        begin: Offset(1.0, 0.0),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeInOut,
                        ),
                      ),
                      child: child,
                    );
                  },
                  child:
                      selectedDevice != null
                          ? DeviceDemoPopup(
                            key: ValueKey(selectedDevice),
                            device: selectedDevice,
                            onClose: () {
                              ref.read(selectedDeviceProvider.notifier).state =
                                  null;
                            },
                          )
                          : SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class FxDeviceCard extends StatelessWidget {
  final FxDevice? device;
  final VoidCallback? onTap;

  const FxDeviceCard({super.key, this.device, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SizedBox.fromSize(
        size: Size(double.infinity, 128),
        child: InkWell(
          borderRadius: BorderRadius.circular(10.0),
          onTap: () {
            print("Tapped ${device?.displayName}");
            onTap?.call();
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
                        device?.displayName ?? "Unknown Device",
                        style: TextStyle(fontSize: 18),
                      ),
                      Text(
                        "Type: ${device?.fxDeviceType ?? 'Unknown'}",
                        style: TextStyle(fontSize: 12),
                      ),
                      Text(
                        "Port: ${device?.port.name ?? 'N/A'}",
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
    );
  }
}

class DeviceDemoPopup extends StatelessWidget {
  final FxDevice device;
  final VoidCallback onClose;

  const DeviceDemoPopup({
    super.key,
    required this.device,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      child: Column(
        children: [
          AppBar(
            elevation: 4,
            title: Text("DMDfx Device Demo"),
            centerTitle: true,
            actions: [IconButton(icon: Icon(Icons.close), onPressed: onClose)],
          ),
          Expanded(
            child: Center(
              child: Text(
                "Connected to ${device.displayName}",
                style: TextStyle(fontSize: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
