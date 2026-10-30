import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../models/shelf.dart';

/// Choose the order of the four main shelf tabs with the arrow buttons.
class ShelfOrderScreen extends StatelessWidget {
  const ShelfOrderScreen({super.key, required this.settings});

  final AppSettings settings;

  void _move(int index, int by) {
    final order = [...settings.shelfOrder];
    final target = index + by;
    if (target < 0 || target >= order.length) return;
    final shelf = order.removeAt(index);
    order.insert(target, shelf);
    settings.setShelfOrder(order);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Order of shelf tabs')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final order = settings.shelfOrder;
          return ListView(
            children: [
              for (var i = 0; i < order.length; i++)
                ListTile(
                  title: Text(order[i].label),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Move up',
                        icon: const Icon(Icons.arrow_upward),
                        onPressed: i == 0 ? null : () => _move(i, -1),
                      ),
                      IconButton(
                        tooltip: 'Move down',
                        icon: const Icon(Icons.arrow_downward),
                        onPressed:
                            i == order.length - 1 ? null : () => _move(i, 1),
                      ),
                    ],
                  ),
                ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Your own shelves always come after these.'),
              ),
            ],
          );
        },
      ),
    );
  }
}
