import 'package:flutter/material.dart';

import 'api_service.dart';
import 'app_navigation.dart';
import 'screens/role_home_shell.dart';
import 'screens/splash_screen.dart';
import 'theme.dart';

void main() {
  runApp(const MidManApp());
}

class MidManApp extends StatelessWidget {
  const MidManApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MidMen',
      debugShowCheckedModeBanner: false,
      theme: buildMidManTheme(),
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      home: const _StartupGate(),
    );
  }
}

/// Skips the splash/login flow straight to the home shell if a session
/// token is already stored on the device.
class _StartupGate extends StatelessWidget {
  const _StartupGate();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: ApiService.isLoggedIn(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return (snapshot.data ?? false) ? const RoleHomeShell() : const SplashScreen();
      },
    );
  }
}
