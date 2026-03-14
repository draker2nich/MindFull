import 'package:flutter/material.dart';
import 'package:mindfull/l10n/app_localizations.dart';
import 'package:mindfull/utils/responsive.dart';
import 'package:mindfull/services/notes_repository.dart';

class NotesHistoryScreen extends StatefulWidget {
  const NotesHistoryScreen({super.key});

  @override
  State<NotesHistoryScreen> createState() => _NotesHistoryScreenState();
}

class _NotesHistoryScreenState extends State<NotesHistoryScreen> {
  List<NoteEntry> _notes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final notes = await NotesRepository.getAllNotes();
    if (!mounted) return;
    setState(() {
      _notes = notes;
      _loading = false;
    });
  }

  Future<void> _deleteNote(int id) async {
    await NotesRepository.deleteNote(id);
    _load();
  }

  Future<void> _clearAll() async {
    final l = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.t('deleteAllNotes')),
        content: Text(l.t('cannotUndo')),
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
            child: Text(l.t('delete')),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await NotesRepository.clearAll();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final r = Responsive(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_notes.isEmpty
            ? l.t('notesTitle')
            : l.t('notesWithCount', {'count': '${_notes.length}'})),
        actions: [
          if (_notes.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded),
              onPressed: _clearAll,
              tooltip: l.t('clearAll'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notes.isEmpty
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(r.dp(32)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.note_alt_outlined,
                            size: r.dp(64),
                            color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                        SizedBox(height: r.dp(16)),
                        Text(l.t('noNotesYet'),
                            style: TextStyle(
                                fontSize: r.sp(16),
                                color: cs.onSurfaceVariant)),
                        SizedBox(height: r.dp(8)),
                        Text(
                          l.t('noNotesDesc'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: r.sp(13),
                            color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: r.maxContentWidth),
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _notes.length,
                      itemBuilder: (context, index) =>
                          _noteTile(_notes[index], cs, l, r),
                    ),
                  ),
                ),
    );
  }

  Widget _noteTile(
      NoteEntry note, ColorScheme cs, AppLocalizations l, Responsive r) {
    final date = DateTime.fromMillisecondsSinceEpoch(note.timestamp);
    final dateStr = '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.'
        '${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';

    return Dismissible(
      key: ValueKey(note.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: cs.error,
        child: Icon(Icons.delete_rounded, color: cs.onError),
      ),
      confirmDismiss: (_) async {
        final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(l.t('deleteNote')),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: Text(l.t('cancel')),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: Text(l.t('delete')),
                  ),
                ],
              ),
            ) ??
            false;
        if (confirmed) await _deleteNote(note.id);
        return false;
      },
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(
            horizontal: r.horizontalPadding, vertical: 4),
        title: Text(note.text, style: TextStyle(fontSize: r.sp(15))),
        subtitle: Row(
          children: [
            Icon(Icons.apps_rounded, size: r.dp(14), color: cs.onSurfaceVariant),
            SizedBox(width: r.dp(4)),
            Flexible(
              child: Text(
                '${note.appName} · $dateStr',
                style: TextStyle(
                    fontSize: r.sp(12), color: cs.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}