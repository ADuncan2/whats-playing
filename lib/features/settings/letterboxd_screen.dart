import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants.dart';
import '../../data/letterboxd/letterboxd_data.dart';
import '../../data/letterboxd/letterboxd_import.dart';
import '../../state/app_state.dart';
import '../../ui/links.dart';

/// Lets the user pick the export ZIP. Overridden in tests. Null = cancelled.
final letterboxdFilePickerProvider = Provider<Future<PickedFile?> Function()>((ref) => _pickZip);

Future<PickedFile?> _pickZip() async {
  final f = await FilePicker.pickFile(
    dialogTitle: 'Choose your Letterboxd export',
    type: FileType.custom,
    allowedExtensions: ['zip'],
  );
  if (f == null) return null;
  return (name: f.name, bytes: await f.readAsBytes());
}

String exportSummary(LetterboxdData d) =>
    'Imported ${d.watchlist.length} watchlist ${d.watchlist.length == 1 ? 'film' : 'films'} and '
    '${d.watched.length} watched ${d.watched.length == 1 ? 'film' : 'films'} '
    '(exported ${DateFormat('d MMM yyyy').format(d.exportedAt.toLocal())})';

/// Settings -> Letterboxd. There is no "log in with Letterboxd" (the API is invite-only and refuses
/// personal projects; scraping breaks the terms), so the user downloads their own data export and
/// hands the ZIP to the app. See docs/letterboxd-linking.md.
class LetterboxdScreen extends ConsumerStatefulWidget {
  const LetterboxdScreen({super.key});

  @override
  ConsumerState<LetterboxdScreen> createState() => _LetterboxdScreenState();
}

class _LetterboxdScreenState extends ConsumerState<LetterboxdScreen> {
  final _username = TextEditingController();
  bool _busy = false;
  String? _usernameShown; // what the field was last filled from, so edits aren't overwritten

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final file = await ref.read(letterboxdFilePickerProvider)();
      if (file == null) return;
      final data = await ref.read(letterboxdProvider.notifier).importZip(file);
      messenger.showSnackBar(SnackBar(content: Text(exportSummary(data))));
    } on LetterboxdImportException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't import that file: $e")));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlink() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unlink Letterboxd?'),
        content: const Text('Your imported watchlist and watched list are deleted from this phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Unlink')),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    await ref.read(letterboxdProvider.notifier).unlink();
    _username.clear();
    _usernameShown = null;
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Letterboxd unlinked')));
  }

  Future<void> _saveUsername() async {
    FocusScope.of(context).unfocus();
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(letterboxdProvider.notifier).setUsername(_username.text);
    final u = ref.read(letterboxdProvider).value?.username ?? '';
    _usernameShown = u;
    _username.text = u;
    messenger.showSnackBar(SnackBar(content: Text(u.isEmpty ? 'Username cleared' : 'Checking the diary feed for $u')));
  }

  Future<void> _checkFeed() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(letterboxdProvider.notifier).refreshRss();
      final n = ref.read(letterboxdProvider).value?.rssWatchedTmdb.length ?? 0;
      messenger.showSnackBar(SnackBar(content: Text('Diary feed checked: $n logged ${n == 1 ? 'film' : 'films'}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't read the diary feed: $e")));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = ref.watch(letterboxdProvider).value;
    final linked = data != null;
    if (linked && _usernameShown != data.username) {
      _usernameShown = data.username;
      _username.text = data.username;
    }
    final body = theme.textTheme.bodyMedium;
    final muted = body?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    Widget step(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Letterboxd')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (linked) _LinkedCard(data: data, busy: _busy, onReimport: _import, onUnlink: _unlink),
          Text(linked ? 'Import a newer export' : 'Link your Letterboxd account', style: theme.textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'WhatsPlaying never sees your Letterboxd password. You download a copy of your data from '
            'Letterboxd, then give that file to the app.',
            style: body,
          ),
          step('1. Download your data from Letterboxd', [
            Text(
              'Tap Open in browser. If Letterboxd asks you to sign in, do so. Your download (a .zip file) '
              "should start straight away. If it doesn't, open the link again after signing in.",
              style: body,
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : () => openInBrowser(context, letterboxdExportUrl),
              icon: const Icon(Icons.open_in_browser),
              label: const Text('Open in browser'),
            ),
            const SizedBox(height: 12),
            Text(
              'Opened the Letterboxd app instead, or it keeps loading? Tap Copy link, open Chrome (or any '
              'browser), paste the link into the address bar, and sign in there.',
              style: muted,
            ),
            const SizedBox(height: 6),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                SelectableText(letterboxdExportUrl, style: body?.copyWith(fontFamily: 'monospace')),
                OutlinedButton.icon(
                  onPressed: () => copyToClipboard(context, letterboxdExportUrl),
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy link'),
                ),
              ],
            ),
          ]),
          step('2. Import the file', [
            Text('Tap Choose file and pick the file that starts letterboxd- in your Downloads folder.', style: body),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _import,
              icon: _busy
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.folder_zip_outlined),
              label: Text(_busy ? 'Importing...' : 'Choose file'),
            ),
          ]),
          step('3. (Optional) Keep "seen" films up to date automatically', [
            Text(
              "Enter your Letterboxd username. The app checks your public diary feed for films you've "
              'logged since your last export.',
              style: body,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _username,
              enabled: linked && !_busy,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Letterboxd username',
                helperText: linked ? null : 'Import your file first',
                border: const OutlineInputBorder(),
                suffixIcon: linked
                    ? IconButton(icon: const Icon(Icons.check), tooltip: 'Save username', onPressed: _saveUsername)
                    : null,
              ),
              onSubmitted: (_) => _saveUsername(),
            ),
            if (linked && data.username.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: Text(_feedStatus(data), style: muted)),
                  TextButton(onPressed: _busy ? null : _checkFeed, child: const Text('Check now')),
                ],
              ),
            ],
          ]),
          const SizedBox(height: 20),
          Text(
            "Your watchlist only updates when you import a new file. We'll remind you when it's more than "
            '30 days old.',
            style: muted,
          ),
        ],
      ),
    );
  }

  static String _feedStatus(LetterboxdData d) {
    final at = d.rssFetchedAt;
    if (at == null) return 'Diary feed not checked yet';
    final n = d.rssWatchedTmdb.length;
    return 'Diary feed checked ${DateFormat('EEE d MMM, HH:mm').format(at.toLocal())} · '
        '$n logged ${n == 1 ? 'film' : 'films'}';
  }
}

/// What is linked now: the counts and export date, with Re-import and Unlink.
class _LinkedCard extends StatelessWidget {
  const _LinkedCard({required this.data, required this.busy, required this.onReimport, required this.onUnlink});
  final LetterboxdData data;
  final bool busy;
  final VoidCallback onReimport, onUnlink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final age = DateTime.now().difference(data.importedAt);
    final stale = age > letterboxdExportStale;
    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      color: stale ? theme.colorScheme.tertiaryContainer : theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.link),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    data.username.isEmpty ? 'Letterboxd linked' : 'Linked as ${data.username}',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(exportSummary(data)),
            if (stale) ...[
              const SizedBox(height: 6),
              Text(
                'Your export is ${age.inDays} days old. Download a new one to refresh your watchlist.',
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: busy ? null : onUnlink, child: const Text('Unlink')),
                TextButton.icon(
                  onPressed: busy ? null : onReimport,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Re-import'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
