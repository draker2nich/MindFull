import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mindfull/l10n/app_localizations.dart';
import 'package:mindfull/utils/responsive.dart';
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
        _error = e.toString();
      });
    }
  }

  Future<void> _saveAndGoBack() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _selected.toList();
    await prefs.setStringList('monitored_packages', list);
    try {
      final running = await PlatformChannel.isServiceRunning();
      if (running) await PlatformChannel.updateMonitoredApps(list);
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _toggle(String packageName) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selected.contains(packageName)) {
        _selected.remove(packageName);
      } else {
        _selected.add(packageName);
      }
    });
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l = AppLocalizations.of(context);
    final r = Responsive(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('appSelection')),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: EdgeInsets.fromLTRB(r.horizontalPadding, 0, r.horizontalPadding, 12),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: l.t('search'),
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                filled: true,
                fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ),
      body: _buildBody(cs, l, r),
      bottomNavigationBar: _buildBottomBar(cs, isDark, l, r),
    );
  }

  Widget _buildBottomBar(
      ColorScheme cs, bool isDark, AppLocalizations l, Responsive r) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          r.horizontalPadding, 12, r.horizontalPadding, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_selected.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  l.t('selected', {'count': '${_selected.length}'}),
                  style: TextStyle(
                    fontSize: r.sp(13),
                    fontWeight: FontWeight.w500,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            SizedBox(
              width: double.infinity,
              height: r.dp(50),
              child: FilledButton(
                onPressed: _saveAndGoBack,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  _selected.isEmpty
                      ? l.t('saveNoApps')
                      : l.t('saveCount', {'count': '${_selected.length}'}),
                  style:
                      TextStyle(fontSize: r.sp(15), fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme cs, AppLocalizations l, Responsive r) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: cs.error),
            const SizedBox(height: 16),
            Text(l.t('loadError'),
                style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: Text(l.t('retry'))),
          ],
        ),
      );
    }
    return _buildList(cs, l, r);
  }

  Widget _buildList(ColorScheme cs, AppLocalizations l, Responsive r) {
    final apps = _filtered;
    if (apps.isEmpty) {
      return Center(
        child: Text(
          _search.isEmpty ? l.t('noApps') : l.t('nothingFound'),
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }

    final selectedApps =
        apps.where((a) => _selected.contains(a.packageName)).toList();
    final otherApps =
        apps.where((a) => !_selected.contains(a.packageName)).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (selectedApps.isNotEmpty && _search.isEmpty) ...[
          _sectionHeader(cs, l.t('tracked'), selectedApps.length, r),
          ...selectedApps.map((a) => _appTile(a, cs, true, r)),
          const SizedBox(height: 8),
          _sectionHeader(cs, l.t('allApps'), otherApps.length, r),
          ...otherApps.map((a) => _appTile(a, cs, false, r)),
        ] else ...[
          ...apps.map(
              (a) => _appTile(a, cs, _selected.contains(a.packageName), r)),
        ],
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _sectionHeader(
      ColorScheme cs, String title, int count, Responsive r) {
    return Padding(
      padding: EdgeInsets.fromLTRB(r.horizontalPadding, 8, r.horizontalPadding, 4),
      child: Text(
        '$title ($count)',
        style: TextStyle(
          fontSize: r.sp(13),
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _appTile(AppInfo app, ColorScheme cs, bool selected, Responsive r) {
    return ListTile(
      contentPadding:
          EdgeInsets.symmetric(horizontal: r.horizontalPadding, vertical: 2),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: r.dp(44),
          height: r.dp(44),
          child: app.iconBytes != null
              ? Image.memory(app.iconBytes!, fit: BoxFit.cover)
              : Container(
                  color: cs.primaryContainer,
                  child:
                      Icon(Icons.android, color: cs.onPrimaryContainer),
                ),
        ),
      ),
      title: Text(
        app.appName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: r.sp(15)),
      ),
      subtitle: Text(
        app.packageName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: r.sp(11), color: cs.onSurfaceVariant),
      ),
      trailing: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: r.dp(28),
        height: r.dp(28),
        decoration: BoxDecoration(
          color: selected ? cs.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(r.dp(8)),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 0 : 2,
          ),
        ),
        child: selected
            ? Icon(Icons.check_rounded, size: r.dp(18), color: cs.onPrimary)
            : null,
      ),
      onTap: () => _toggle(app.packageName),
    );
  }
}