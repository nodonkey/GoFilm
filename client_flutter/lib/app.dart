import 'package:flutter/material.dart';

import 'core/app_config.dart';
import 'core/theme.dart';
import 'screens/splash_screen.dart';

class GoFilmApp extends StatelessWidget {
  const GoFilmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GoFilm',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      builder: (context, child) {
        if (AppConfig.isTv(context) &&
            FocusManager.instance.highlightStrategy !=
                FocusHighlightStrategy.alwaysTraditional) {
          FocusManager.instance.highlightStrategy =
              FocusHighlightStrategy.alwaysTraditional;
        }
        return child ?? const SizedBox.shrink();
      },
      home: const SplashScreen(),
    );
  }
}
