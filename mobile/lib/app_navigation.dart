import 'package:flutter/material.dart';

/// Lets api_service.dart navigate/show a snackbar from anywhere (e.g. when a
/// session expires mid-request) without needing a BuildContext at the call
/// site. Wired into MaterialApp in main.dart.
final navigatorKey = GlobalKey<NavigatorState>();
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
