/// A rating as text: filled and empty stars (★★★☆☆), or a number (3/5).
String ratingText(int rating, {required bool asNumber}) {
  final value = rating < 1 ? 1 : (rating > 5 ? 5 : rating);
  if (asNumber) return '$value/5';
  return '${'★' * value}${'☆' * (5 - value)}';
}
