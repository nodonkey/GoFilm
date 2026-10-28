import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/api_client.dart';
import 'core/app_config.dart';
import 'core/auth_controller.dart';
import 'core/session_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await SessionStore.open();
  final savedBase = store.baseUrl;
  final api = ApiClient(
    baseUrl: savedBase.isEmpty
        ? AppConfig.normalizeBaseUrl(AppConfig.apiBaseUrl)
        : savedBase,
  );
  final auth = AuthController(api, store);
  runApp(
    ChangeNotifierProvider<AuthController>.value(
      value: auth,
      child: const GoFilmApp(),
    ),
  );
}
