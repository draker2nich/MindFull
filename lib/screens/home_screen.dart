import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mindfull/l10n/app_localizations.dart';
import 'package:mindfull/utils/responsive.dart';
import 'package:mindfull/services/platform_channel.dart';
import 'package:mindfull/screens/app_selection_screen.dart';
import 'package:mindfull/screens/settings_screen.dart';
import 'package:mindfull/screens/notes_history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin, RouteAware {
  bool _serviceRunning = false;
  bool _loading = true;
  int _monitoredCount = 0;
  bool _permissionsOk = false;
  int _cooldownMinutes = 5;
  bool _cooldownEnabled = true;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  static const _cooldownOptions = [1, 3, 5, 10, 15, 30, 60];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _init() async {
    await _refresh();
    if (!_serviceRunning && _monitoredCount > 0 && _permissionsOk) {
      await _startService();
    }
  }

  Future<void> _refresh() async {
    final running = await PlatformChannel.isServiceRunning();
    final perms = await PlatformChannel.checkAllPermissions();
    final prefs = await SharedPreferences.getInstance();
    final monitored = prefs.getStringList('monitored_packages') ?? [];
    final cooldown = await PlatformChannel.getCooldownMinutes();
    final cooldownEnabled = await PlatformChannel.isCooldownEnabled();
    if (!mounted) return;
    setState(() {
      _serviceRunning = running;
      _monitoredCount = monitored.length;
      _permissionsOk = perms.usageAccess && perms.overlay;
      _cooldownMinutes = cooldown;
      _cooldownEnabled = cooldownEnabled;
      _loading = false;
    });
  }

  Future<void> _startService() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final monitored = prefs.getStringList('monitored_packages') ?? [];
      await PlatformChannel.updateMonitoredApps(monitored);
      await PlatformChannel.startMonitorService();
      await Future.delayed(const Duration(milliseconds: 500));
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(AppLocalizations.of(context).t('error', {'e': '$e'}));
    }
  }

  Future<void> _stopService() async {
    try {
      await PlatformChannel.stopMonitorService();
      await Future.delayed(const Duration(milliseconds: 500));
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(AppLocalizations.of(context).t('error', {'e': '$e'}));
    }
  }

  Future<void> _toggleService() async {
    HapticFeedback.mediumImpact();
    _serviceRunning ? await _stopService() : await _startService();
  }

  Future<void> _setCooldown(int minutes) async {
    await PlatformChannel.setCooldownMinutes(minutes);
    setState(() => _cooldownMinutes = minutes);
  }

  Future<void> _toggleCooldownEnabled(bool enabled) async {
    HapticFeedback.lightImpact();
    await PlatformChannel.setCooldownEnabled(enabled);
    setState(() => _cooldownEnabled = enabled);
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  bool get _canToggle => _monitoredCount > 0 && _permissionsOk;

  /// Navigate to AppSelectionScreen and refresh when it pops.
  Future<void> _openAppSelection() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AppSelectionScreen()),
    );
    // Always refresh after returning — this is the fix for the
    // first-run bug where apps were selected during onboarding
    // but the home screen still showed 0 monitored.
    await _refresh();
    // Auto-start service if conditions are now met
    if (!_serviceRunning && _monitoredCount > 0 && _permissionsOk) {
      await _startService();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l = AppLocalizations.of(context);
    final r = Responsive(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: r.maxContentWidth),
                  child: CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      SliverAppBar(
                        floating: true,
                        snap: true,
                        backgroundColor: Colors.transparent,
                        elevation: 0,
                        title: Text(
                          l.appTitle,
                          style: TextStyle(
                            fontSize: r.sp(20),
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                            letterSpacing: -0.5,
                          ),
                        ),
                        actions: [
                          IconButton(
                            icon: Icon(Icons.settings_rounded,
                                color: cs.onSurfaceVariant),
                            onPressed: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => const SettingsScreen()),
                              );
                              _refresh();
                            },
                          ),
                          SizedBox(width: r.dp(8)),
                        ],
                      ),
                      SliverPadding(
                        padding: EdgeInsets.symmetric(
                            horizontal: r.horizontalPadding),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            SizedBox(height: r.dp(8)),
                            _buildHeroCard(cs, isDark, l, r),
                            SizedBox(height: r.dp(20)),
                            _buildCooldownCard(cs, isDark, l, r),
                            SizedBox(height: r.dp(16)),
                            _buildQuickAction(
                              cs, isDark, r,
                              icon: Icons.apps_rounded,
                              title: l.t('apps'),
                              value: _monitoredCount > 0
                                  ? l.t('appsSelected',
                                      {'count': '$_monitoredCount'})
                                  : l.t('tapToSelect'),
                              onTap: _openAppSelection,
                            ),
                            SizedBox(height: r.dp(12)),
                            _buildQuickAction(
                              cs, isDark, r,
                              icon: Icons.history_rounded,
                              title: l.t('notesHistory'),
                              value: l.t('notesHistoryDesc'),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const NotesHistoryScreen()),
                                );
                              },
                            ),
                            SizedBox(height: r.dp(40)),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildHeroCard(
      ColorScheme cs, bool isDark, AppLocalizations l, Responsive r) {
    final active = _serviceRunning;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(r.dp(28)),
      decoration: BoxDecoration(
        color: active
            ? cs.primary.withValues(alpha: isDark ? 0.15 : 0.08)
            : cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(r.dp(28)),
        border: Border.all(
          color: active
              ? cs.primary.withValues(alpha: 0.2)
              : cs.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) => Transform.scale(
              scale: active ? _pulseAnimation.value : 1.0,
              child: child,
            ),
            child: Container(
              width: r.dp(72),
              height: r.dp(72),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? cs.primary.withValues(alpha: 0.15)
                    : cs.surfaceContainerHighest,
              ),
              child: Icon(
                active ? Icons.shield_rounded : Icons.shield_outlined,
                size: r.dp(36),
                color: active
                    ? cs.primary
                    : cs.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
          SizedBox(height: r.dp(20)),
          Text(
            active ? l.protectionActive : l.protectionOff,
            style: TextStyle(
              fontSize: r.sp(22),
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
              letterSpacing: -0.5,
            ),
          ),
          SizedBox(height: r.dp(6)),
          Text(
            active
                ? l.t('monitored', {'count': '$_monitoredCount'})
                : _monitoredCount > 0
                    ? l.t('readyToStart', {'count': '$_monitoredCount'})
                    : l.t('selectAppsFirst'),
            style: TextStyle(fontSize: r.sp(14), color: cs.onSurfaceVariant),
          ),
          if (!_permissionsOk && !active) ...[
            SizedBox(height: r.dp(12)),
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: r.dp(12), vertical: r.dp(6)),
              decoration: BoxDecoration(
                color: cs.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(r.dp(8)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: r.dp(16), color: cs.error),
                  SizedBox(width: r.dp(6)),
                  Flexible(
                    child: Text(
                      l.t('needPermissions'),
                      style: TextStyle(
                        fontSize: r.sp(12),
                        color: cs.error,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: r.dp(24)),
          SizedBox(
            width: double.infinity,
            height: r.dp(52),
            child: FilledButton(
              onPressed: _canToggle ? _toggleService : null,
              style: FilledButton.styleFrom(
                backgroundColor:
                    active ? cs.error.withValues(alpha: 0.9) : cs.primary,
                foregroundColor: active ? cs.onError : cs.onPrimary,
                disabledBackgroundColor: cs.surfaceContainerHighest,
                disabledForegroundColor:
                    cs.onSurfaceVariant.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(r.dp(16)),
                ),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    active
                        ? Icons.stop_rounded
                        : _canToggle
                            ? Icons.play_arrow_rounded
                            : Icons.lock_outline_rounded,
                    size: r.dp(22),
                  ),
                  SizedBox(width: r.dp(8)),
                  Text(
                    active
                        ? l.t('stopProtection')
                        : l.t('enableProtection'),
                    style: TextStyle(
                        fontSize: r.sp(16), fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
          if (!_canToggle && !active) ...[
            SizedBox(height: r.dp(10)),
            Text(
              _monitoredCount == 0
                  ? l.t('selectAppsHint')
                  : l.t('grantPermissionsHint'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: r.sp(12),
                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCooldownCard(
      ColorScheme cs, bool isDark, AppLocalizations l, Responsive r) {
    return Container(
      padding: EdgeInsets.all(r.dp(20)),
      decoration: BoxDecoration(
        color: isDark
            ? cs.surfaceContainerHighest.withValues(alpha: 0.4)
            : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(r.dp(22)),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: r.dp(40),
                height: r.dp(40),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(r.dp(12)),
                ),
                child: Icon(Icons.timer_rounded,
                    size: r.dp(22), color: cs.primary),
              ),
              SizedBox(width: r.dp(14)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.t('cooldown'),
                      style: TextStyle(
                        fontSize: r.sp(16),
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    Text(
                      _cooldownEnabled
                          ? l.t('cooldownDesc', {
                              'minutes':
                                  l.cooldownLabelFull(_cooldownMinutes)
                            })
                          : l.t('cooldownEveryTime'),
                      style: TextStyle(
                          fontSize: r.sp(12), color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Transform.scale(
                scale: 0.85,
                child: Switch.adaptive(
                  value: _cooldownEnabled,
                  onChanged: _toggleCooldownEnabled,
                ),
              ),
            ],
          ),
          if (_cooldownEnabled) ...[
            SizedBox(height: r.dp(16)),
            SizedBox(
              height: r.dp(40),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: _cooldownOptions.length,
                separatorBuilder: (_, __) => SizedBox(width: r.dp(8)),
                itemBuilder: (context, index) {
                  final minutes = _cooldownOptions[index];
                  final selected = _cooldownMinutes == minutes;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      _setCooldown(minutes);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding:
                          EdgeInsets.symmetric(horizontal: r.dp(16)),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? cs.primary
                            : cs.surfaceContainerHighest
                                .withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(r.dp(12)),
                        border: selected
                            ? null
                            : Border.all(
                                color: cs.outlineVariant
                                    .withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        l.cooldownLabelShort(minutes),
                        style: TextStyle(
                          fontSize: r.sp(13),
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                          color: selected
                              ? cs.onPrimary
                              : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickAction(
    ColorScheme cs,
    bool isDark,
    Responsive r, {
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isDark
          ? cs.surfaceContainerHighest.withValues(alpha: 0.4)
          : cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(r.dp(18)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(r.dp(18)),
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: r.dp(20), vertical: r.dp(18)),
          child: Row(
            children: [
              Container(
                width: r.dp(40),
                height: r.dp(40),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(r.dp(12)),
                ),
                child: Icon(icon, size: r.dp(22), color: cs.primary),
              ),
              SizedBox(width: r.dp(14)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: r.sp(15),
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    Text(
                      value,
                      style: TextStyle(
                          fontSize: r.sp(12), color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                  size: r.dp(22)),
            ],
          ),
        ),
      ),
    );
  }
}