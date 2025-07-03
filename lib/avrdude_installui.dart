import 'package:dmdfx/avrdude_downloader.dart';
import 'package:dmdfx/constants.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

Future<void> checkAvrdudeStatus(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();

  final skipPrompt = prefs.getBool('avrdude_skip_prompt') ?? false;
  if (skipPrompt) return;

  final avrdudePath = await getAvrdudePath(avrdudeVersion);
  if (avrdudePath.isEmpty) {
    Future.microtask(() {
      if (!context.mounted) return;
      showAvrdudePrompt(context, true);
    });
  }
}

void showAvrdudePrompt(BuildContext context, bool showDontAsk) {
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text('Install AVRDUDE'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'AVRDUDE is required for firmware updates, and is licensed under the GPLv2',
            ),
            TextButton(
              child: Text('View License'),
              onPressed: () => showLicenseDialog(context),
            ),
          ],
        ),
        actions: [
          if (showDontAsk)
            TextButton(
              child: Text('Don\'t ask again'),
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('avrdude_skip_prompt', true);
                if (!context.mounted) return;
                Navigator.of(context).pop();
              },
            ),
          TextButton(
            child: Text('Don\'t Install'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          ElevatedButton(
            child: Text('Install'),
            onPressed: () async {
              Navigator.of(context).pop();
              await installAvrdude(context);
            },
          ),
        ],
      );
    },
  );
}

void showAvrdudeRemovePrompt(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text('Uninstall AVRDUDE'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'AVRDUDE is required for firmware updates, are you sure you want to uninstall it?',
            ),
          ],
        ),
        actions: [
          TextButton(
            child: Text('No'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          ElevatedButton(
            child: Text('Yes, I\'m Sure'),
            onPressed: () async {
              Navigator.of(context).pop();
              await uninstallAvrdude(context);
            },
          ),
        ],
      );
    },
  );
}

void showLicenseDialog(BuildContext context) async {
  showDialog(
    context: context,
    builder: (context) {
      return FutureBuilder<http.Response>(
        future: http.get(Uri.parse(avrdudeLicenseUrl)),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return AlertDialog(
              title: Text('License'),
              content: SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.statusCode != 200) {
            return AlertDialog(
              title: Text('License'),
              content: Text('Failed to load license text.'),
            );
          }

          return AlertDialog(
            title: Text('GPL License'),
            content: SingleChildScrollView(
              child: SelectableText(snapshot.data!.body),
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
    },
  );
}

Future<void> installAvrdude(BuildContext context) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder:
        (_) => AlertDialog(
          content: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Installing AVRDUDE...'),
              ],
            ),
          ),
        ),
  );

  try {
    await downloadAndExtractAvrdude();
    if (!context.mounted) return;
    Navigator.of(context).pop(); // Close progress dialog
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('AVRDUDE installed successfully')));
  } catch (e) {
    Navigator.of(context).pop(); // Close progress dialog
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: Text('Installation Failed'),
            content: Text(e.toString()),
            actions: [
              TextButton(
                child: Text('Close'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
    );
  }
}

Future<void> uninstallAvrdude(BuildContext context) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder:
        (_) => AlertDialog(
          content: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Uninstalling AVRDUDE...'),
              ],
            ),
          ),
        ),
  );

  try {
    await removeAvrdude(avrdudeVersion);
    if (!context.mounted) return;
    Navigator.of(context).pop(); // Close progress dialog
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('AVRDUDE uninstalled successfully')));
  } catch (e) {
    Navigator.of(context).pop(); // Close progress dialog
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: Text('Installation Failed'),
            content: Text(e.toString()),
            actions: [
              TextButton(
                child: Text('Close'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
    );
  }
}
