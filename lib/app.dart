import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mindfull/l10n/app_localizations.dart';
import 'package:mindfull/theme/app_theme.dart';
import 'package:mindfull/screens/onboarding_screen.dart';
import 'package:mindfull/screens/home_screen.dart';

/// Key used in SharedPreferences to store the user's language override.
/// Values: 'system', 'ru', 'en'
const kPrefLocale = 'app_locale';

class MindfulApp extends StatefulWidget {
  const MindfulApp({super.key});

  /// Allows any descendant to trigger a locale change.
  static void setLocale(BuildContext context, String localeCode) {
    final state = context.findAncestorStateOfType<_MindfulAppState>();
    state?._setLocale(localeCode);
  }

  @override
  State<MindfulApp> createState() => _MindfulAppState();
}

class _MindfulAppState extends State<MindfulApp> {
  /// null = follow system
  Locale? _overrideLocale;
  bool _localeLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadLocale();
  }

  Future<void> _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(kPrefLocale) ?? 'system';
    if (!mounted) return;
    setState(() {
      _overrideLocale = _localeFromCode(code);
      _localeLoaded = true;
    });
  }

  void _setLocale(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefLocale, code);
    if (!mounted) return;
    setState(() {
      _overrideLocale = _localeFromCode(code);
    });
  }

  static Locale? _localeFromCode(String code) {
    if (code == 'ru') return const Locale('ru');
    if (code == 'en') return const Locale('en');
    return null; // system
  }

  @override
  Widget build(BuildContext context) {
    if (!_localeLoaded) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MaterialApp(
      title: 'Mindful Pause',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      locale: _overrideLocale, // null → system locale
      supportedLocales: const [
        Locale('en'),
        Locale('ru'),
      ],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _EntryPoint(),
    );
  }
}

class _EntryPoint extends StatefulWidget {
  const _EntryPoint();

  @override
  State<_EntryPoint> createState() => _EntryPointState();
}

class _EntryPointState extends State<_EntryPoint> {
  bool _loading = true;
  bool _onboardingDone = false;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool('onboarding_done') ?? false;
    if (!mounted) return;
    setState(() {
      _onboardingDone = done;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return _onboardingDone ? const HomeScreen() : const OnboardingScreen();
  }
}