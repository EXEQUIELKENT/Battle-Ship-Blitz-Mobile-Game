import 'package:flutter/material.dart';

/// App-wide route observer, registered on [MaterialApp.navigatorObservers]
/// in `main.dart`.
///
/// BUGFIX (menu music "gone forever" after a match): `HomeScreen` is
/// pushed once, near app launch, and then simply stays mounted
/// underneath `PlacementScreen` / `BattleScreen` / `ResultScreen` for the
/// rest of that game — `Navigator` never disposes and recreates it, it's
/// just not the visible top route for a while. That means
/// `HomeScreen.initState()` (which starts the menu music) only ever runs
/// ONCE per app run, while `BattleScreen.initState()` explicitly stops
/// that music the moment a battle starts. Nothing ever told `HomeScreen`
/// "you're visible again" when the result screen's REMATCH / MAIN MENU
/// buttons popped back to it, so music that battle turned off had
/// nothing left to turn it back on — it stayed off for the rest of the
/// app's life.
///
/// Subscribing a screen to this observer (via the `RouteAware` mixin)
/// gives it a `didPopNext()` callback that fires exactly at that
/// "became visible again" moment, so `HomeScreen` can use it to restart
/// the menu music every time it re-becomes the top route, not just the
/// first time it's ever built.
final RouteObserver<PageRoute<dynamic>> appRouteObserver =
    RouteObserver<PageRoute<dynamic>>();
