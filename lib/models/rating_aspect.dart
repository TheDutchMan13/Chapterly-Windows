/// Parts of a book you can rate on their own, next to the overall rating.
enum RatingAspect { plot, characters, writing, pacing }

extension RatingAspectLabel on RatingAspect {
  String get label => switch (this) {
        RatingAspect.plot => 'Plot',
        RatingAspect.characters => 'Characters',
        RatingAspect.writing => 'Writing',
        RatingAspect.pacing => 'Pacing',
      };
}
