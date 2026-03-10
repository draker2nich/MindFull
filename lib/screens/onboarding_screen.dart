import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/platform_channel.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  bool _usageGranted = false;
  bool _overlayGranted = false;

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
    });
  }

  Future<void> _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  void _nextPage() {
    if (_page < 2) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Индикатор страниц
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) {
                  final active = i == _page;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: active ? 28 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: active ? cs.primary : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),

            // Страницы
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) {
                  setState(() => _page = i);
                  if (i == 2) _refreshPermissions();
                },
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildWelcomePage(cs),
                  _buildHowItWorksPage(cs),
                  _buildPermissionsPage(cs),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Страница 1: Приветствие ──

  Widget _buildWelcomePage(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.self_improvement_rounded, size: 96, color: cs.primary),
          const SizedBox(height: 32),
          Text(
            'Mindful Pause',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Осознанная пауза перед отвлекающими приложениями.\n'
            'Не блокирует — мягко возвращает внимание.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 48),
          FilledButton(
            onPressed: _nextPage,
            child: const Text('Далее'),
          ),
        ],
      ),
    );
  }

  // ── Страница 2: Как это работает ──

  Widget _buildHowItWorksPage(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _step(cs, Icons.touch_app_rounded, '1', 'Выберите приложения',
              'Укажите, перед какими приложениями показывать паузу'),
          const SizedBox(height: 24),
          _step(cs, Icons.timer_rounded, '2', '60 секунд паузы',
              'Дыхательная анимация и время подумать'),
          const SizedBox(height: 24),
          _step(cs, Icons.arrow_forward_rounded, '3', 'Продолжайте',
              'После паузы — свободный переход в приложение'),
          const SizedBox(height: 48),
          FilledButton(
            onPressed: _nextPage,
            child: const Text('Настроить разрешения'),
          ),
        ],
      ),
    );
  }

  Widget _step(ColorScheme cs, IconData icon, String num, String title, String desc) {
    return Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: cs.primaryContainer,
          child: Icon(icon, color: cs.onPrimaryContainer),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface,
              )),
              const SizedBox(height: 4),
              Text(desc, style: TextStyle(
                fontSize: 14, color: cs.onSurfaceVariant,
              )),
            ],
          ),
        ),
      ],
    );
  }

  // ── Страница 3: Разрешения ──

  Widget _buildPermissionsPage(ColorScheme cs) {
    final allGranted = _usageGranted && _overlayGranted;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Нужны два разрешения',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Без них приложение не сможет отслеживать запуск других приложений',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 40),

          // Usage Access
          _permissionTile(
            cs,
            icon: Icons.bar_chart_rounded,
            title: 'Доступ к использованию',
            subtitle: 'Позволяет определить, какое приложение открыто',
            granted: _usageGranted,
            onTap: () async {
              await PlatformChannel.requestUsageAccess();
              // Пользователь вернётся из настроек — обновим статус
              await Future.delayed(const Duration(seconds: 1));
              _refreshPermissions();
            },
          ),
          const SizedBox(height: 16),

          // Overlay
          _permissionTile(
            cs,
            icon: Icons.layers_rounded,
            title: 'Наложение поверх приложений',
            subtitle: 'Позволяет показать экран паузы',
            granted: _overlayGranted,
            onTap: () async {
              await PlatformChannel.requestOverlayPermission();
              await Future.delayed(const Duration(seconds: 1));
              _refreshPermissions();
            },
          ),
          const SizedBox(height: 16),

          // Кнопка обновить
          TextButton.icon(
            onPressed: _refreshPermissions,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Проверить разрешения'),
          ),

          const SizedBox(height: 40),

          FilledButton(
            onPressed: allGranted ? _finishOnboarding : null,
            child: const Text('Начать'),
          ),
          if (!allGranted) ...[
            const SizedBox(height: 8),
            Text(
              'Выдайте оба разрешения, чтобы продолжить',
              style: TextStyle(fontSize: 12, color: cs.error),
            ),
          ],
        ],
      ),
    );
  }

  Widget _permissionTile(
    ColorScheme cs, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool granted,
    required VoidCallback onTap,
  }) {
    return Material(
      color: granted ? cs.primaryContainer.withValues(alpha: 0.3) : cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: granted ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: granted ? cs.primary : cs.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(
                      fontWeight: FontWeight.w600, color: cs.onSurface,
                    )),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(
                      fontSize: 12, color: cs.onSurfaceVariant,
                    )),
                  ],
                ),
              ),
              Icon(
                granted ? Icons.check_circle_rounded : Icons.arrow_forward_ios_rounded,
                color: granted ? cs.primary : cs.onSurfaceVariant,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}