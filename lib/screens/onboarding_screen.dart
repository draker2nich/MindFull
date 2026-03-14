import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mindfull/l10n/app_localizations.dart';
import 'package:mindfull/utils/responsive.dart';
import 'package:mindfull/services/platform_channel.dart';
import 'package:mindfull/screens/home_screen.dart';
import 'package:mindfull/screens/app_selection_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;
  static const _totalPages = 4;

  bool _usageGranted = false;
  bool _overlayGranted = false;
  bool _batteryExempt = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _refreshPermissions() async {
    final perms = await PlatformChannel.checkAllPermissions();
    if (!mounted) return;
    setState(() {
      _usageGranted = perms.usageAccess;
      _overlayGranted = perms.overlay;
      _batteryExempt = perms.battery;
    });
  }

  Future<void> _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (!mounted) return;

    // Replace the entire stack with HomeScreen, then push AppSelectionScreen
    // on top. When AppSelectionScreen pops, HomeScreen will be shown.
    // We use pushAndRemoveUntil to get a clean stack, then immediately
    // push AppSelectionScreen. HomeScreen will call _refresh() on resume
    // via the navigatorObserver pattern below.
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );

    // At this point the HomeScreen is mounted.
    // We push AppSelectionScreen. When user saves and pops,
    // HomeScreen._didPopFromAppSelection() triggers refresh.
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AppSelectionScreen()),
    );
  }

  void _nextPage() {
    if (_page < _totalPages - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = Responsive(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: r.maxContentWidth),
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(vertical: r.dp(16)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_totalPages, (i) {
                      final active = i == _page;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: active ? 28 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: active
                              ? cs.primary
                              : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: _controller,
                    onPageChanged: (i) {
                      setState(() => _page = i);
                      if (i >= 2) _refreshPermissions();
                    },
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildWelcomePage(cs, r),
                      _buildHowItWorksPage(cs, r),
                      _buildPermissionsPage(cs, r),
                      _buildBatteryPage(cs, r),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomePage(ColorScheme cs, Responsive r) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: r.horizontalPadding + 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.self_improvement_rounded,
              size: r.dp(96), color: cs.primary),
          SizedBox(height: r.dp(32)),
          Text(
            l.t('onboardingTitle'),
            style: TextStyle(
              fontSize: r.sp(28),
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          SizedBox(height: r.dp(16)),
          Text(
            l.t('onboardingDesc'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: r.sp(16), color: cs.onSurfaceVariant),
          ),
          SizedBox(height: r.dp(48)),
          FilledButton(onPressed: _nextPage, child: Text(l.t('next'))),
        ],
      ),
    );
  }

  Widget _buildHowItWorksPage(ColorScheme cs, Responsive r) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: r.horizontalPadding + 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _step(cs, r, Icons.touch_app_rounded, l.t('selectApps'),
              l.t('selectAppsDesc')),
          SizedBox(height: r.dp(24)),
          _step(cs, r, Icons.timer_rounded, l.t('pauseDuration'),
              l.t('pauseDurationDesc')),
          SizedBox(height: r.dp(24)),
          _step(cs, r, Icons.arrow_forward_rounded, l.t('continueUsing'),
              l.t('continueUsingDesc')),
          SizedBox(height: r.dp(48)),
          FilledButton(
              onPressed: _nextPage, child: Text(l.t('setupPermissions'))),
        ],
      ),
    );
  }

  Widget _step(
      ColorScheme cs, Responsive r, IconData icon, String title, String desc) {
    return Row(
      children: [
        CircleAvatar(
          radius: r.dp(24),
          backgroundColor: cs.primaryContainer,
          child: Icon(icon, color: cs.onPrimaryContainer),
        ),
        SizedBox(width: r.dp(16)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: r.sp(16),
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface)),
              SizedBox(height: r.dp(4)),
              Text(desc,
                  style: TextStyle(
                      fontSize: r.sp(14), color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionsPage(ColorScheme cs, Responsive r) {
    final l = AppLocalizations.of(context);
    final coreGranted = _usageGranted && _overlayGranted;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: r.horizontalPadding + 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(height: r.dp(40)),
          Text(
            l.t('twoPermissions'),
            style: TextStyle(
              fontSize: r.sp(22),
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          SizedBox(height: r.dp(8)),
          Text(
            l.t('twoPermissionsDesc'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: r.sp(14), color: cs.onSurfaceVariant),
          ),
          SizedBox(height: r.dp(40)),
          _permissionTile(
            cs, r,
            icon: Icons.bar_chart_rounded,
            title: l.t('usageAccess'),
            subtitle: l.t('usageAccessDesc'),
            granted: _usageGranted,
            onTap: () async {
              await PlatformChannel.requestUsageAccess();
              await Future.delayed(const Duration(seconds: 1));
              _refreshPermissions();
            },
          ),
          SizedBox(height: r.dp(16)),
          _permissionTile(
            cs, r,
            icon: Icons.layers_rounded,
            title: l.t('overlayPermission'),
            subtitle: l.t('overlayPermissionDesc'),
            granted: _overlayGranted,
            onTap: () async {
              await PlatformChannel.requestOverlayPermission();
              await Future.delayed(const Duration(seconds: 1));
              _refreshPermissions();
            },
          ),
          SizedBox(height: r.dp(16)),
          TextButton.icon(
            onPressed: _refreshPermissions,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(l.t('checkPermissions')),
          ),
          SizedBox(height: r.dp(40)),
          FilledButton(
            onPressed: coreGranted ? _nextPage : null,
            child: Text(l.t('next')),
          ),
          if (!coreGranted) ...[
            SizedBox(height: r.dp(8)),
            Text(l.t('grantBoth'),
                style: TextStyle(fontSize: r.sp(12), color: cs.error)),
          ],
          SizedBox(height: r.dp(40)),
        ],
      ),
    );
  }

  Widget _buildBatteryPage(ColorScheme cs, Responsive r) {
    final l = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: r.horizontalPadding + 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(height: r.dp(40)),
          Icon(
            _batteryExempt
                ? Icons.battery_full_rounded
                : Icons.battery_alert_rounded,
            size: r.dp(64),
            color: _batteryExempt ? cs.primary : cs.onSurfaceVariant,
          ),
          SizedBox(height: r.dp(24)),
          Text(
            l.t('batteryTitle'),
            style: TextStyle(
              fontSize: r.sp(22),
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          SizedBox(height: r.dp(8)),
          Text(
            l.t('batteryDesc'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: r.sp(14), color: cs.onSurfaceVariant),
          ),
          SizedBox(height: r.dp(32)),
          if (!_batteryExempt) ...[
            _permissionTile(
              cs, r,
              icon: Icons.battery_saver_rounded,
              title: l.t('disableBatteryOpt'),
              subtitle: l.t('disableBatteryOptDesc'),
              granted: false,
              onTap: () async {
                await PlatformChannel.requestBatteryOptimizationExemption();
                await Future.delayed(const Duration(seconds: 2));
                _refreshPermissions();
              },
            ),
            SizedBox(height: r.dp(16)),
            TextButton.icon(
              onPressed: _refreshPermissions,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(l.t('check')),
            ),
          ] else ...[
            Container(
              padding: EdgeInsets.all(r.dp(16)),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(r.dp(16)),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: cs.primary),
                  SizedBox(width: r.dp(12)),
                  Expanded(
                    child: Text(
                      l.t('batteryDisabled'),
                      style: TextStyle(
                          color: cs.onSurface, fontSize: r.sp(14)),
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: r.dp(40)),
          FilledButton(
              onPressed: _finishOnboarding, child: Text(l.t('start'))),
          if (!_batteryExempt) ...[
            SizedBox(height: r.dp(8)),
            Text(
              l.t('skipWarning'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: r.sp(12), color: cs.onSurfaceVariant),
            ),
          ],
          SizedBox(height: r.dp(40)),
        ],
      ),
    );
  }

  Widget _permissionTile(
    ColorScheme cs,
    Responsive r, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool granted,
    required VoidCallback onTap,
  }) {
    return Material(
      color: granted
          ? cs.primaryContainer.withValues(alpha: 0.3)
          : cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(r.dp(16)),
      child: InkWell(
        onTap: granted ? null : onTap,
        borderRadius: BorderRadius.circular(r.dp(16)),
        child: Padding(
          padding: EdgeInsets.all(r.dp(16)),
          child: Row(
            children: [
              Icon(icon,
                  color: granted ? cs.primary : cs.onSurfaceVariant),
              SizedBox(width: r.dp(16)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface)),
                    SizedBox(height: r.dp(2)),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: r.sp(12),
                            color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(
                granted
                    ? Icons.check_circle_rounded
                    : Icons.arrow_forward_ios_rounded,
                color: granted ? cs.primary : cs.onSurfaceVariant,
                size: r.dp(20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}