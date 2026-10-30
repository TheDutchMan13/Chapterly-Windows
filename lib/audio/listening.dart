import 'package:flutter/widgets.dart';

import 'audio_files.dart';
import 'listen_controller.dart';

/// The audiobook player for the whole app, set up in main.dart. Null in
/// tests and until set up, and the listening parts of the screens then
/// stay hidden.
class Listening {
  Listening._();

  static ListenController? controller;
  static AudioFiles? files;

  /// Lets the bar at the bottom (which sits outside the pages) open the
  /// player and ask questions.
  static final navigatorKey = GlobalKey<NavigatorState>();
}
