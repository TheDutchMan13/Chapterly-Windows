import 'package:flutter/material.dart';

import '../data/app_settings.dart';

// The same file is in the Android app.

/// "20:00".
String formatMinutes(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

/// The daily reading reminder: on or off, and when. It only says something
/// on days you're behind this year's goal.
class ReminderSettings extends StatelessWidget {
  const ReminderSettings({
    super.key,
    required this.settings,
    required this.where,
    this.askPermission,
  });

  final AppSettings settings;

  /// Where the reminder appears ("as a notification").
  final String where;

  /// Asks to show notifications; false when that was refused.
  final Future<bool> Function()? askPermission;

  Future<void> _switch(BuildContext context, bool on) async {
    final messenger = ScaffoldMessenger.of(context);
    if (on && askPermission != null && !await askPermission!()) {
      messenger.showSnackBar(const SnackBar(
        content: Text(
          'Notifications are off for Chapterly. Turn them on in the '
          "phone's settings to get the reminder.",
        ),
      ));
      return;
    }
    settings.setReminder(on: on);
  }

  Future<void> _pickTime(BuildContext context) async {
    final minutes = settings.reminderMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    );
    if (picked != null) settings.setReminder(minutes: picked.hour * 60 + picked.minute);
  }

  @override
  Widget build(BuildContext context) {
    final time = formatMinutes(settings.reminderMinutes);
    return Column(
      children: [
        SwitchListTile(
          title: const Text('Reading reminder'),
          subtitle: Text(
            settings.reminderOn
                ? "Every day at $time, $where, but only when you're behind "
                    "this year's goal"
                : "A daily nudge when you're behind this year's goal",
          ),
          value: settings.reminderOn,
          onChanged: (on) => _switch(context, on),
        ),
        if (settings.reminderOn)
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Reminder time'),
            trailing: Text(time),
            onTap: () => _pickTime(context),
          ),
      ],
    );
  }
}
