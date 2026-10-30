import 'dart:async';
import 'dart:io';

import 'pc_sync.dart';
import 'sync_protocol.dart';
import 'sync_server.dart' show localAddresses;

/// Whether [address] is a home-network address: 10.x.x.x, 172.16-31.x.x or
/// 192.168.x.x.
bool isPrivateIPv4(String address) {
  final parts = address.split('.');
  if (parts.length != 4) return false;
  final numbers = <int>[];
  for (final part in parts) {
    final value = int.tryParse(part);
    if (value == null || value < 0 || value > 255) return false;
    numbers.add(value);
  }
  final a = numbers[0];
  final b = numbers[1];
  return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168);
}

/// Every other address on the same home networks as [own] (the last number
/// from 1 to 254), without this PC's own addresses.
List<String> candidateAddresses(List<String> own) {
  final mine = own.toSet();
  final prefixes = <String>{};
  final hosts = <String>[];
  for (final address in own) {
    if (!isPrivateIPv4(address)) continue;
    final prefix = address.substring(0, address.lastIndexOf('.'));
    if (!prefixes.add(prefix)) continue;
    for (var i = 1; i <= 254; i++) {
      final host = '$prefix.$i';
      if (!mine.contains(host)) hosts.add(host);
    }
  }
  return hosts;
}

/// Runs [probe] on every host, [workers] at a time, and returns the hosts
/// where it said yes, in the order given. A probe that throws counts as no.
Future<List<String>> scanHosts(
  List<String> hosts,
  Future<bool> Function(String host) probe, {
  int workers = 48,
}) async {
  final found = <String>{};
  var next = 0;
  Future<void> worker() async {
    while (next < hosts.length) {
      final host = hosts[next++];
      try {
        if (await probe(host)) found.add(host);
      } catch (_) {
        // Not a phone.
      }
    }
  }

  await Future.wait([for (var i = 0; i < workers; i++) worker()]);
  return [
    for (final host in hosts)
      if (found.contains(host)) host,
  ];
}

/// Whether a Chapterly phone answers at [host]. A quick connection test comes
/// first, so empty addresses are skipped fast.
Future<bool> probeHost(
  String host,
  SyncClient client, {
  int port = defaultSyncPort,
  Duration connectTimeout = const Duration(milliseconds: 600),
}) async {
  try {
    final socket = await Socket.connect(host, port, timeout: connectTimeout);
    socket.destroy();
  } catch (_) {
    return false;
  }
  try {
    await client.ping(Uri(scheme: 'http', host: host, port: port));
    return true;
  } on SyncFailure {
    return false;
  }
}

/// Looks for Chapterly phones on the same home networks as this PC. Returns
/// their addresses, such as 192.168.1.20:8765.
Future<List<String>> findPhonesOnNetwork(SyncClient client) async {
  final hosts = candidateAddresses(await localAddresses());
  final found = await scanHosts(hosts, (host) => probeHost(host, client));
  return [for (final host in found) '$host:$defaultSyncPort'];
}
