import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

const bool kBreakTheme = false;

class Song {
  final int? id;
  final String title;
  final String artist;

  Song({this.id, required this.title, required this.artist});

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'title': title,
        'artist': artist,
      };

  factory Song.fromMap(Map<String, Object?> m) => Song(
        id: m['id'] as int,
        title: m['title'] as String,
        artist: m['artist'] as String,
      );
}

class SongDb {
  static final Future<Database> _dbFuture = _open();
  static Future<Database> get db => _dbFuture;

  static Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'pocket_notes.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) => db.execute(
        'CREATE TABLE songs ('
        'id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'title TEXT, '
        'artist TEXT)',
      ),
    );
  }

  static Future<List<Song>> all() async {
    final db = await SongDb.db;
    final rows = await db.query('songs', orderBy: 'id ASC');
    debugPrint('DB ROWS: $rows');
    return rows.map(Song.fromMap).toList();
  }

  static Future<void> add(Song s) async {
    final db = await SongDb.db;
    await db.insert('songs', s.toMap());
  }

  static Future<void> update(Song s) async {
    final db = await SongDb.db;
    await db.update(
      'songs',
      s.toMap(),
      where: 'id = ?',
      whereArgs: [s.id],
    );
  }

  static Future<void> delete(int id) async {
    final db = await SongDb.db;
    await db.delete(
      'songs',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final bool startDark = kBreakTheme
      ? false
      : await SharedPreferencesAsync().getBool('isDark') ?? false;

  runApp(PocketNotesApp(startDark: startDark));
}

class PocketNotesApp extends StatefulWidget {
  final bool startDark;
  const PocketNotesApp({super.key, required this.startDark});

  @override
  State<PocketNotesApp> createState() => _PocketNotesAppState();
}

class _PocketNotesAppState extends State<PocketNotesApp> {
  late bool _isDark = widget.startDark;

  @override
  void initState() {
    super.initState();
    if (kBreakTheme) _loadThemeLate();
  }

  Future<void> _loadThemeLate() async {
    await Future.delayed(const Duration(seconds: 2));
    final saved = await SharedPreferencesAsync().getBool('isDark') ?? false;
    if (!mounted) return;
    setState(() => _isDark = saved);
  }

  Future<void> _setDark(bool value) async {
    setState(() => _isDark = value);
    await SharedPreferencesAsync().setBool('isDark', value);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pocket Notes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, brightness: Brightness.light),
      darkTheme: ThemeData(colorSchemeSeed: Colors.indigo, brightness: Brightness.dark),
      themeMode: _isDark ? ThemeMode.dark : ThemeMode.light,
      home: HomePage(isDark: _isDark, onThemeChanged: _setDark),
    );
  }
}

class HomePage extends StatefulWidget {
  final bool isDark;
  final ValueChanged<bool> onThemeChanged;
  const HomePage({super.key, required this.isDark, required this.onThemeChanged});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Song> _songs = [];

  String _search = '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final songs = await SongDb.all();
      if (!mounted) return;
      setState(() => _songs = songs);
    } catch (e) {
      debugPrint('LOAD ERROR: $e');
      _say('Could not load songs: $e');
    }
  }

  Future<void> _openDialog([Song? song]) async {
    final result = await showDialog<Song>(
      context: context,
      builder: (_) => SongDialog(song: song),
    );
    if (result == null) return;
    try {
      if (song == null) {
        await SongDb.add(result);
      } else {
        await SongDb.update(result);
      }
      await _refresh();
      _say(song == null ? 'Song added' : 'Song updated');
    } catch (e) {
      debugPrint('SAVE ERROR: $e');
      _say('Save failed: $e');
    }
  }

  Future<void> _delete(Song song) async {
    try {
      await SongDb.delete(song.id!);
      await _refresh();
      _say('Song deleted');
    } catch (e) {
      debugPrint('DELETE ERROR: $e');
      _say('Delete failed: $e');
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.toLowerCase();
    final shown = _songs
        .where((s) => s.title.toLowerCase().contains(q) || s.artist.toLowerCase().contains(q))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pocket Notes: Songs'),
        actions: [
          Icon(widget.isDark ? Icons.dark_mode : Icons.light_mode),
          Switch(value: widget.isDark, onChanged: widget.onThemeChanged),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openDialog(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search songs (not saved)',
                border: OutlineInputBorder(),
              ),
              onChanged: (text) => setState(() => _search = text),
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? const Center(child: Text('No songs yet. Tap + to add one.'))
                : ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (context, i) {
                      final song = shown[i];
                      return ListTile(
                        leading: CircleAvatar(child: Text('${song.id}')),
                        title: Text(song.title),
                        subtitle: Text(song.artist),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _openDialog(song),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () => _delete(song),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class SongDialog extends StatefulWidget {
  final Song? song;
  const SongDialog({super.key, this.song});

  @override
  State<SongDialog> createState() => _SongDialogState();
}

class _SongDialogState extends State<SongDialog> {
  late final _title = TextEditingController(text: widget.song?.title ?? '');
  late final _artist = TextEditingController(text: widget.song?.artist ?? '');

  String? _titleError;

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.song == null ? 'Add song' : 'Edit song'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            decoration: InputDecoration(labelText: 'Title', errorText: _titleError),
          ),
          TextField(controller: _artist, decoration: const InputDecoration(labelText: 'Artist')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_title.text.trim().isEmpty) {
              setState(() => _titleError = 'Please type a title');
              return;
            }
            Navigator.pop(
              context,
              Song(id: widget.song?.id, title: _title.text.trim(), artist: _artist.text.trim()),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}