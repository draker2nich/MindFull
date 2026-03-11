import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mindfull/services/platform_channel.dart';

class AppSelectionScreen extends StatefulWidget {
  const AppSelectionScreen({super.key});

  @override
  State<AppSelectionScreen> createState() => _AppSelectionScreenState();
}

class _AppSelectionScreenState extends State<AppSelectionScreen> {
  List<AppInfo> _allApps = [];
  Set<String> _selected = {};
  bool _loading = true;
  String _search = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('monitored_packages') ?? [];
      final apps = await PlatformChannel.getInstalledApps();

      if (!mounted) return;
      setState(() {
        _allApps = apps;
        _selected = saved.toSet();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Не удалось загрузить список приложений';
      });
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _selected.toList();
    await prefs.setStringList('monitored_packages', list);

    // Обновляем сервис в реальном времени если он запущен
    try {
      final running = await PlatformChannel.isServiceRunning();
      if (running) {
        await PlatformChannel.updateMonitoredApps(list);
      }
    } catch (_) {}
  }

  void _toggle(String packageName) {
    setState(() {
      if (_selected.contains(packageName)) {
        _selected.remove(packageName);
      } else {
        _selected.add(packageName);
      }
    });
    _save();
  }

  List<AppInfo> get _filtered {
    if (_search.isEmpty) return _allApps;
    final q = _search.toLowerCase();
    return _allApps.where((a) {
      return a.appName.toLowerCase().contains(q) ||
          a.packageName.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Выбор приложений'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Поиск...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                filled: true,
                fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ),
      body: _buildBody(cs),
      bottomNavigationBar: _selected.isNotEmpty
          ? Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              decoration: BoxDecoration(
                color: cs.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: Text(
                  'Отслеживается: ${_selected.length}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: cs.error),
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Повторить')),
          ],
        ),
      );
    }
    return _buildList(cs);
  }

  Widget _buildList(ColorScheme cs) {
    final apps = _filtered;

    if (apps.isEmpty) {
      return Center(
        child: Text(
          _search.isEmpty ? 'Нет приложений' : 'Ничего не найдено',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }

    final selectedApps = apps.where((a) => _selected.contains(a.packageName)).toList();
    final otherApps = apps.where((a) => !_selected.contains(a.packageName)).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (selectedApps.isNotEmpty && _search.isEmpty) ...[
          _sectionHeader(cs, 'Отслеживаемые', selectedApps.length),
          ...selectedApps.map((a) => _appTile(a, cs, true)),
          const SizedBox(height: 8),
          _sectionHeader(cs, 'Все приложения', otherApps.length),
          ...otherApps.map((a) => _appTile(a, cs, false)),
        ] else ...[
          ...apps.map((a) => _appTile(a, cs, _selected.contains(a.packageName))),
        ],
      ],
    );
  }

  Widget _sectionHeader(ColorScheme cs, String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        '$title ($count)',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _appTile(AppInfo app, ColorScheme cs, bool selected) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 44,
          height: 44,
          child: app.iconBytes != null
              ? Image.memory(app.iconBytes!, fit: BoxFit.cover)
              : Container(
                  color: cs.primaryContainer,
                  child: Icon(Icons.android, color: cs.onPrimaryContainer),
                ),
        ),
      ),
      title: Text(
        app.appName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15),
      ),
      subtitle: Text(
        app.packageName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
      ),
      trailing: Checkbox(
        value: selected,
        onChanged: (_) => _toggle(app.packageName),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      onTap: () => _toggle(app.packageName),
    );
  }
}