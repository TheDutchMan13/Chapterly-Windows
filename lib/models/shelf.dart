/// The shelves a book can sit on. Wishlist holds books you want but have
/// not got yet.
enum Shelf { finished, inProgress, forLater, unfinished, wishlist }

extension ShelfLabel on Shelf {
  String get label => switch (this) {
        Shelf.finished => 'Finished',
        Shelf.inProgress => 'In progress',
        Shelf.forLater => 'For later',
        Shelf.unfinished => 'Unfinished',
        Shelf.wishlist => 'Wishlist',
      };
}
