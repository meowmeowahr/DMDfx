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
