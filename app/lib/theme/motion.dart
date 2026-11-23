import 'package:flutter/widgets.dart';

/// Motion tokens: how long things take and how they ease.
///
/// Concept: motion explains a change (where a sheet came from, that a tap
/// landed); it never carries information on its own. So every animation must
/// still make sense when it is switched off. Some people get dizzy or
/// distracted by movement; phones let them turn it off ("reduce motion" /
/// "remove animations"), and Tracka also has its own switch in
/// Settings › Accessibility. Both end up in [Motion.reduced].
/// The full list per screen is the "Motion, screen by screen" board on the
/// design canvas. See docs/handbook/09-mobile-and-web-apps.md, "Motion and reduce motion".
class Motion {
  Motion._();

  // Durations (match the canvas's motion spec).
  static const press = Duration(milliseconds: 120); // button shrinks to 97%
  static const pop = Duration(milliseconds: 180); // a chip you picked
  static const toastIn = Duration(milliseconds: 240);
  static const select = Duration(milliseconds: 280); // chips, tabs
  static const sheet = Duration(milliseconds: 320);
  static const enter = Duration(milliseconds: 350); // every screen's content
  static const toggle = Duration(milliseconds: 360); // switches
  static const morph = Duration(milliseconds: 450); // the Feed button folding
  static const fill = Duration(milliseconds: 600); // bars, count-ups
  static const toastStay = Duration(seconds: 4);
  static const pulse = Duration(milliseconds: 1600); // loading shapes

  // Easing: ease-out for things arriving, ease-in-out for things changing.
  static const arrive = Curves.easeOutCubic;
  static const change = Curves.easeInOutCubic;

  /// The app's own "reduce motion" switch. Set from the player's settings
  /// (AppState) so widgets don't need to know where it comes from.
  static bool appSetting = false;

  /// True when either the phone or Tracka's setting asks for less motion.
  static bool reduced(BuildContext context) =>
      appSetting || (MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  /// [d], or no time at all when motion is reduced. Use for any one-off
  /// animation: the change still happens, it just happens at once.
  static Duration of(BuildContext context, Duration d) => reduced(context) ? Duration.zero : d;
}
