import 'package:flutter/material.dart';

import '../data/date_format.dart';
import '../server/server_client.dart';

// The same screen is in the Android app.

/// "Active now", "12 min ago", "3 h ago", or the date.
String lastSeenText(DateTime? seen, DateTime now) {
  if (seen == null) return 'never';
  final minutes = now.difference(seen).inMinutes;
  if (minutes < 5) return 'active now';
  if (minutes < 60) return '$minutes min ago';
  if (minutes < 24 * 60) return '${minutes ~/ 60} h ago';
  return formatDateTime(seen);
}

/// The apps that have signed in to your book server, and when each last did.
class ServerDevicesScreen extends StatefulWidget {
  const ServerDevicesScreen({super.key, required this.client, this.now});

  final ServerClient client;

  /// For tests.
  final DateTime Function()? now;

  @override
  State<ServerDevicesScreen> createState() => _ServerDevicesScreenState();
}

class _ServerDevicesScreenState extends State<ServerDevicesScreen> {
  List<ServerDevice>? _devices;
  String? _problem;
  bool _loading = false;

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _problem = null;
    });
    try {
      final devices = await widget.client.devices();
      if (!mounted) return;
      setState(() => _devices = devices);
    } on ServerFailure catch (failure) {
      if (!mounted) return;
      setState(() => _problem = failure.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forget(ServerDevice device) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Take "${device.name}" off the list?'),
        content: const Text(
          'It only leaves this list. It comes back the next time that app '
          'connects to the server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Take off'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.client.forgetDevice(device);
    } on ServerFailure catch (failure) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message)));
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final devices = _devices;
    final people = {for (final d in devices ?? const <ServerDevice>[]) d.person};
    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices on the book server'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _problem != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_problem!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _load, child: const Text('Try again')),
                  ],
                ),
              ),
            )
          : devices == null
              ? const Center(child: CircularProgressIndicator())
              : devices.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No devices yet. Each app shows up here after it '
                          'connects to the server (update the app if it does not).',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView(
                      children: [
                        for (final device in devices)
                          ListTile(
                            leading: Icon(
                              device.name.toLowerCase().contains('phone')
                                  ? Icons.smartphone
                                  : Icons.computer,
                            ),
                            title: Text(
                              device.thisDevice ? '${device.name} (this one)' : device.name,
                            ),
                            subtitle: Text(
                              '${people.length > 1 ? '${device.person} · ' : ''}'
                              'last connected ${lastSeenText(device.lastSeen, _now)}',
                            ),
                            trailing: device.thisDevice
                                ? null
                                : IconButton(
                                    tooltip: 'Take off the list',
                                    icon: const Icon(Icons.close),
                                    onPressed: () => _forget(device),
                                  ),
                          ),
                      ],
                    ),
    );
  }
}
