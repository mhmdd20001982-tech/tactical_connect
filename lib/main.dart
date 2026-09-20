import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tactical_connect/core/app_router.dart';
import 'package:tactical_connect/core/theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: TacticalConnectApp()));
}

class TacticalConnectApp extends StatelessWidget {
  const TacticalConnectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Tactical Connect',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: appRouter,
    );
  }
}