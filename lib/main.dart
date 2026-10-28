import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/router.dart';
import 'app/shell.dart';
import 'core/config.dart';
import 'core/store.dart';
import 'core/ui/theme.dart';
import 'core/ui/toast.dart';
import 'features/auth/auth_screens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: C.raised,
  ));
  await AppConfig.load();
  if (AppConfig.isComplete) {
    await Supabase.initialize(url: AppConfig.supabaseUrl, anonKey: AppConfig.supabaseAnonKey);
  }
  runApp(const KharjookApp());
}

class KharjookApp extends StatefulWidget {
  const KharjookApp({super.key});
  @override
  State<KharjookApp> createState() => _KharjookAppState();
}

class _KharjookAppState extends State<KharjookApp> {
  // The store lives above MaterialApp so pages pushed on the root navigator
  // (siblings of `home`, not children) can read it too.
  PortfolioStore? _store;

  PortfolioStore? get store {
    if (_store == null && AppConfig.isComplete) _store = PortfolioStore()..init();
    return _store;
  }

  @override
  void dispose() {
    _store?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = MaterialApp(
      title: 'خرجوک',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      navigatorKey: rootNavigatorKey,
      scaffoldMessengerKey: rootMessengerKey,
      locale: const Locale('fa', 'IR'),
      supportedLocales: const [Locale('fa', 'IR'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: AppConfig.isComplete ? const _Root() : const SetupScreen(),
    );
    final s = store;
    return s == null ? app : ChangeNotifierProvider.value(value: s, child: app);
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) => Selector<PortfolioStore, String?>(
        selector: (_, s) => s.user?.id,
        builder: (_, uid, _) => uid == null ? const AuthGate() : const Shell(),
      );
}
