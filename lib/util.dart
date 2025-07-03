import 'dart:typed_data';

import 'package:image/image.dart' as img;

String formatUptime(int milliseconds) {
  Duration duration = Duration(milliseconds: milliseconds);

  int days = duration.inDays;
  int hours = duration.inHours % 24; // Remainder after full days
  int minutes = duration.inMinutes % 60; // Remainder after full hours
  int seconds = duration.inSeconds % 60; // Remainder after full minutes

  List<String> parts = [];

  if (days > 0) {
    parts.add('$days day${days == 1 ? '' : 's'}');
  }
  if (hours > 0) {
    parts.add('$hours hour${hours == 1 ? '' : 's'}');
  }
  if (minutes > 0) {
    parts.add('$minutes minute${minutes == 1 ? '' : 's'}');
  }
  if (seconds > 0 || parts.isEmpty) {
    // Include seconds even if 0, if no other parts exist
    parts.add('$seconds second${seconds == 1 ? '' : 's'}');
  }

  return parts.join(' ');
}

// Helper function to apply 1-bit grayscale conversion
Uint8List applyGrayscaleThreshold(Uint8List originalBytes, int threshold) {
  final image = img.decodeImage(originalBytes);
  if (image == null) return originalBytes;

  final grayscaleImage = img.grayscale(image);
  final outputImage = img.Image(
    width: grayscaleImage.width,
    height: grayscaleImage.height,
  );

  for (int y = 0; y < grayscaleImage.height; y++) {
    for (int x = 0; x < grayscaleImage.width; x++) {
      final pixel = grayscaleImage.getPixel(x, y);
      final lum = img.getLuminanceRgb(pixel.r, pixel.g, pixel.b);
      if (lum > threshold) {
        outputImage.setPixelRgb(x, y, 255, 255, 255); // White
      } else {
        outputImage.setPixelRgb(x, y, 0, 0, 0); // Black
      }
    }
  }
  return Uint8List.fromList(img.encodePng(outputImage));
}
