import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:tactical_connect/features/onboarding/presentation/onboarding_screen.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (BuildContext context, GoRouterState state) {
        return const OnboardingScreen();
      },
    ),
  ],
);
