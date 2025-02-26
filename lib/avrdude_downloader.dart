import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class AssetNotFoundException implements Exception {
  final String message;

  AssetNotFoundException(this.message);

  @override
  String toString() {
    return "AssetNotFoundException: $message";
  }
}

class PlatformNotSupportedException implements Exception {
  final String message;

  PlatformNotSupportedException(this.message);

  @override
  String toString() {
    return "PlatformNotSupportedException: $message";
  }
}

class GithubApiException implements Exception {
  final String message;

  GithubApiException(this.message);

  @override
  String toString() {
    return "GithubApiException: $message";
  }
}

Future<String> getAvrdudeDownloadUrl(String version) async {
  // GitHub API endpoint to get release assets
  final String apiUrl =
      "https://api.github.com/repos/avrdudes/avrdude/releases/tags/v$version";

  // Fetch the release data
  final response = await http.get(Uri.parse(apiUrl));

  if (response.statusCode != 200) {
    throw GithubApiException("Failed to load release data from GitHub");
  }

  // Parse the release JSON response
  final Map<String, dynamic> releaseData = json.decode(response.body);
  final assets = releaseData['assets'];

  String downloadUrl = "";

  // Check and set the download URL based on platform
  if (Platform.isWindows) {
    if (Platform.version.contains("x64")) {
      downloadUrl = _getAssetUrl(assets, "avrdude-v$version-windows-x64.zip");
    } else if (Platform.version.contains("x86")) {
      downloadUrl = _getAssetUrl(assets, "avrdude-v$version-windows-x86.zip");
    } else if (Platform.version.contains("arm64")) {
      downloadUrl = _getAssetUrl(assets, "avrdude-v$version-windows-arm64.zip");
    }
  } else if (Platform.isMacOS) {
    downloadUrl = _getAssetUrl(
      assets,
      "avrdude_v${version}_macOS_64bit.tar.gz",
    );
  } else if (Platform.isLinux) {
    if (Platform.version.contains("x64")) {
      downloadUrl = _getAssetUrl(
        assets,
        "avrdude_v${version}_Linux_64bit.tar.gz",
      );
    } else if (Platform.version.contains("arm64")) {
      downloadUrl = _getAssetUrl(
        assets,
        "avrdude_v${version}_Linux_ARM64.tar.gz",
      );
    } else {
      throw PlatformNotSupportedException(
        "Your CPU architecture is not supported",
      );
    }
  }

  if (downloadUrl.isEmpty) {
    throw PlatformNotSupportedException(
      "No valid download URL found for the platform",
    );
  }

  return downloadUrl;
}

// Helper function to check if the asset exists and get the URL
String _getAssetUrl(List<dynamic> assets, String filename) {
  final asset = assets.firstWhere(
    (a) => a['name'] == filename,
    orElse: () => null,
  );

  if (asset != null) {
    return asset['browser_download_url'];
  } else {
    throw AssetNotFoundException("Asset not found: $filename");
  }
}

Future<String> downloadAndExtractAvrdude() async {
  final dir = await getApplicationSupportDirectory();
  final tempDir = await getTemporaryDirectory();
  final filePath = "${tempDir.path}/avrdude_download";
  final avrdudePath = "${dir.path}/avrdude/8.0";
  Directory(avrdudePath).createSync(recursive: true);

  // Skip download if already exists
  if (await File(avrdudePath).exists()) {
    return avrdudePath;
  }

  // Download avrdude
  final url = getAvrdudeDownloadUrl("8.0");
  final response = await http.get(Uri.parse(await url));
  final file = File(filePath);
  await file.writeAsBytes(response.bodyBytes);

  // Extract based on OS
  if (Platform.isWindows) {
    Process.runSync("powershell", [
      "Expand-Archive",
      "-Path",
      filePath,
      "-DestinationPath",
      avrdudePath,
    ]);
  } else {
    Process.runSync("tar", ["-xzf", filePath, "-C", avrdudePath]);
  }

  return avrdudePath;
}

Future<String> getAvrdudePath(String version) async {
  final dir = await getApplicationSupportDirectory();
  late String path;
  try {
    if (Platform.isLinux || Platform.isMacOS) {
      path =
          "${(await (await Directory("${dir.path}/avrdude/$version/").create()).list().toList()).first.absolute.path}/bin/avrdude";
    } else if (Platform.isWindows) {
      path = "${dir.path}/$version/avrdude.exe";
    } else {
      path = "";
    }
    if (!(await File(path).exists())) {
      return "";
    }
  } on StateError {
    return "";
  }
  return path;
}
