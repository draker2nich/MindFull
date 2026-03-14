import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mindfull/app.dart';
import 'package:mindfull/l10n/app_localizations.dart';
import 'package:mindfull/utils/responsive.dart';
import 'package:mindfull/services/platform_channel.dart';
import 'package:mindfull/services/notes_repository.dart';
import 'package:mindfull/screens/app_selection_screen.dart';
import 'package:mindfull/screens/onboarding_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  bool _serviceRunning = false;
  bool _usageGranted = false;
  bool _overlayGranted = false;
  bool _batteryExempt = false;
  int _monitoredCount = 0;
  bool _loading = true;
  String _currentLocaleCode = 'system';

  static const _privacyPolicyUrl = 'https://example.com/privacy';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _loadLocale();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _currentLocaleCode = prefs.getString(kPrefLocale) ?? 'system';
    });
  }

  void _changeLocale(String code) {
    setState(() => _currentLocaleCode = code);
    MindfulApp.setLocale(context, code);
  }

  Future<void> _refresh() async {
    final running = await PlatformChannel.isServiceRunning();
    final perms = await PlatformChannel.checkAllPermissions();
    final prefs = await SharedPreferences.getInstance();
    final monitored = prefs.getStringList('monitored_packages') ?? [];
    if (!mounted) return;
    setState(() {
      _serviceRunning = running;
      _usageGranted = perms.usageAccess;
      _overlayGranted = perms.overlay;
      _batteryExempt = perms.battery;
      _monitoredCount = monitored.length;
      _loading = false;
    });
  }

  Future<void> _toggleService(bool enable) async {
    try {
      if (enable) {
        final prefs = await SharedPreferences.getInstance();
        final monitored = prefs.getStringList('monitored_packages') ?? [];
        await PlatformChannel.updateMonitoredApps(monitored);
        await PlatformChannel.startMonitorService();
      } else {
        await PlatformChannel.stopMonitorService();
      }
      await Future.delayed(const Duration(milliseconds: 500));
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                AppLocalizations.of(context).t('error', {'e': '$e'}))),
      );
    }
  }

  Future<void> _deleteAllData() async {
    final l = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.t('deleteAllDataConfirm')),
        content: Text(l.t('deleteAllDataWarning')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.t('deleteEverything')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await PlatformChannel.stopMonitorService();
      await NotesRepository.clearAll();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('monitored_packages');
      await PlatformChannel.setCooldownMinutes(5);
      await PlatformChannel.setCooldownEnabled(true);
      await PlatformChannel.updateMonitoredApps([]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.t('allDataDeleted'))),
      );
      _refresh();
    }
  }

  Future<void> _openPrivacyPolicy() async {
    final uri = Uri.parse(_privacyPolicyUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l = AppLocalizations.of(context);
    final r = Responsive(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.t('settings'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: r.maxContentWidth),
                child: ListView(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  children: [
                    // ── General ──
                    _sectionHeader(cs, l.t('general'), r),
                    _buildCard(
                      cs, isDark, r,
                      child: SwitchListTile(
                        title: Text(l.protectionActive),
                        subtitle: Text(_serviceRunning
                            ? l.t('protectionActiveDesc')
                            : l.t('serviceStopped')),
                        secondary: Icon(
                          _serviceRunning
                              ? Icons.shield_rounded
                              : Icons.shield_outlined,
                          color: _serviceRunning
                              ? cs.primary
                              : cs.onSurfaceVariant,
                        ),
                        value: _serviceRunning,
                        onChanged: (_monitoredCount > 0 &&
                                _usageGranted &&
                                _overlayGranted)
                            ? (val) => _toggleService(val)
                            : null,
                      ),
                    ),
                    if (!_usageGranted || !_overlayGranted) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: r.horizontalPadding),
                        child: Container(
                          padding: EdgeInsets.all(r.dp(12)),
                          decoration: BoxDecoration(
                            color: cs.error.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber_rounded,
                                  color: cs.error, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  l.t('permissionsNotGranted'),
                                  style: TextStyle(
                                      fontSize: r.sp(13), color: cs.error),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    SizedBox(height: r.dp(20)),

                    // ── Language ──
                    _sectionHeader(cs, l.t('language'), r),
                    _buildCard(
                      cs, isDark, r,
                      child: _buildLanguageSelector(cs, l, r),
                    ),

                    SizedBox(height: r.dp(20)),

                    // ── Apps ──
                    _sectionHeader(cs, l.t('apps'), r),
                    _buildCard(
                      cs, isDark, r,
                      child: ListTile(
                        leading:
                            Icon(Icons.apps_rounded, color: cs.primary),
                        title: Text(l.t('controlledApps')),
                        subtitle: Text(l.t('selected',
                            {'count': '$_monitoredCount'})),
                        trailing: const Icon(Icons.chevron_right_rounded,
                            size: 20),
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) =>
                                    const AppSelectionScreen()),
                          );
                          _refresh();
                        },
                      ),
                    ),

                    SizedBox(height: r.dp(20)),

                    // ── Permissions ──
                    _sectionHeader(cs, l.t('permissions'), r),
                    _buildCard(
                      cs, isDark, r,
                      child: Column(
                        children: [
                          _permissionTile(cs, l,
                              title: l.t('usageAccess'),
                              granted: _usageGranted,
                              onTap: () =>
                                  PlatformChannel.requestUsageAccess()),
                          Divider(
                              height: 1,
                              indent: 56,
                              color: cs.outlineVariant
                                  .withValues(alpha: 0.3)),
                          _permissionTile(cs, l,
                              title: l.t('overlayPermission'),
                              granted: _overlayGranted,
                              onTap: () => PlatformChannel
                                  .requestOverlayPermission()),
                          Divider(
                              height: 1,
                              indent: 56,
                              color: cs.outlineVariant
                                  .withValues(alpha: 0.3)),
                          _permissionTile(cs, l,
                              title: l.t('batteryOptimization'),
                              granted: _batteryExempt,
                              onTap: () => PlatformChannel
                                  .requestBatteryOptimizationExemption()),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: r.horizontalPadding, vertical: 8),
                      child: TextButton.icon(
                        onPressed: _refresh,
                        icon:
                            const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(l.t('refreshStatus')),
                      ),
                    ),

                    SizedBox(height: r.dp(20)),

                    // ── Data & Privacy ──
                    _sectionHeader(cs, l.t('dataAndPrivacy'), r),
                    _buildCard(
                      cs, isDark, r,
                      child: Column(
                        children: [
                          ListTile(
                            leading: Icon(Icons.delete_forever_rounded,
                                color: cs.error),
                            title: Text(l.t('deleteAllData')),
                            subtitle: Text(l.t('deleteAllDataDesc')),
                            onTap: _deleteAllData,
                          ),
                          Divider(
                              height: 1,
                              indent: 56,
                              color: cs.outlineVariant
                                  .withValues(alpha: 0.3)),
                          ListTile(
                            leading: Icon(Icons.privacy_tip_outlined,
                                color: cs.onSurfaceVariant),
                            title: Text(l.t('privacyPolicy')),
                            trailing: const Icon(
                                Icons.open_in_new_rounded,
                                size: 18),
                            onTap: _openPrivacyPolicy,
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: r.dp(20)),

                    // ── About ──
                    _sectionHeader(cs, l.t('about'), r),
                    _buildCard(
                      cs, isDark, r,
                      child: Column(
                        children: [
                          ListTile(
                            leading: Icon(Icons.info_outline_rounded,
                                color: cs.onSurfaceVariant),
                            title: const Text('Mindful Pause'),
                            subtitle:
                                Text(l.t('version', {'v': '1.0.0'})),
                          ),
                          Divider(
                              height: 1,
                              indent: 56,
                              color: cs.outlineVariant
                                  .withValues(alpha: 0.3)),
                          ListTile(
                            leading: Icon(Icons.replay_rounded,
                                color: cs.onSurfaceVariant),
                            title: Text(l.t('showOnboarding')),
                            onTap: () => _resetOnboarding(context),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: r.dp(40)),
                  ],
                ),
              ),
            ),
    );
  }

  // ══════════════════════════════════════════════════════════
  //  LANGUAGE SELECTOR
  // ══════════════════════════════════════════════════════════

  Widget _buildLanguageSelector(
      ColorScheme cs, AppLocalizations l, Responsive r) {
    final options = [
      ('system', l.t('langSystem'), Icons.phone_android_rounded),
      ('ru', l.t('langRu'), null),
      ('en', l.t('langEn'), null),
    ];

    return Padding(
      padding: EdgeInsets.symmetric(vertical: r.dp(8)),
      child: Column(
        children: options.map((opt) {
          final (code, label, icon) = opt;
          final selected = _currentLocaleCode == code;
          return RadioListTile<String>(
            value: code,
            groupValue: _currentLocaleCode,
            onChanged: (v) {
              if (v != null) _changeLocale(v);
            },
            title: Text(
              label,
              style: TextStyle(
                fontSize: r.sp(15),
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: cs.onSurface,
              ),
            ),
            secondary: icon != null
                ? Icon(icon, color: cs.onSurfaceVariant, size: r.dp(22))
                : null,
            activeColor: cs.primary,
            dense: true,
          );
        }).toList(),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  //  SHARED WIDGETS
  // ══════════════════════════════════════════════════════════

  Widget _sectionHeader(ColorScheme cs, String title, Responsive r) {
    return Padding(
      padding:
          EdgeInsets.fromLTRB(r.horizontalPadding, 4, r.horizontalPadding, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: r.sp(13),
          fontWeight: FontWeight.w600,
          color: cs.primary,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildCard(ColorScheme cs, bool isDark, Responsive r,
      {required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        decoration: BoxDecoration(
          color: isDark
              ? cs.surfaceContainerHighest.withValues(alpha: 0.4)
              : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(r.dp(16)),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.15),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }

  Widget _permissionTile(
    ColorScheme cs,
    AppLocalizations l, {
    required String title,
    required bool granted,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(
        granted ? Icons.check_circle_rounded : Icons.error_outline_rounded,
        color: granted ? cs.primary : cs.error,
        size: 22,
      ),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      subtitle: Text(
        granted ? l.t('granted') : l.t('notGranted'),
        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
      ),
      trailing: granted
          ? null
          : TextButton(onPressed: onTap, child: Text(l.t('grant'))),
    );
  }

  Future<void> _resetOnboarding(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.t('resetOnboarding')),
        content: Text(l.t('resetOnboardingDesc')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.t('reset')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_done', false);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
        (_) => false,
      );
    }
  }
}