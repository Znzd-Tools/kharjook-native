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

class KharjookApp extends StatelessWidget {
  const KharjookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
  }
}

class _Root extends StatefulWidget {
  const _Root();
  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  late final PortfolioStore store = PortfolioStore()..init();

  @override
  void dispose() {
    store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: store,
      child: Selector<PortfolioStore, String?>(
        selector: (_, s) => s.user?.id,
        builder: (_, uid, __) => uid == null ? const AuthGate() : const Shell(),
      ),
    );
  }
}
