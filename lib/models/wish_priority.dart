/// How much you want to read a book on the For later shelf.
enum WishPriority { low, medium, high }

extension WishPriorityLabel on WishPriority {
  String get label => switch (this) {
        WishPriority.low => 'Low',
        WishPriority.medium => 'Medium',
        WishPriority.high => 'High',
      };
}
