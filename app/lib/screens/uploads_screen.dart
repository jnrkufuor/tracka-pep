import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/upload_queue.dart';
import '../theme/theme.dart';
import '../widgets/ds.dart';
import 'guardian_screens.dart';
import 'video_screen.dart';

/// Uploads (canvas: Failsafe › Uploads): every clip waiting, going or done,
/// with one clear action each. Clips stay on the phone until they finish,
/// so closing the app loses nothing (lib/state/upload_queue.dart).
class UploadsScreen extends StatelessWidget {
  const UploadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final items = s.queue.items.reversed.toList();
    return Scaffold(
      appBar: AppBar(),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
        Text('Uploads', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 16),
        if (s.offline) ...[const OfflineBanner(), const SizedBox(height: 12)],
        if (items.isEmpty)
          const Panel(child: Text('Nothing waiting. Clips you add show here until they reach Pep.', style: TextStyle(color: Tk.inkSoft))),
        for (final it in items) ...[UploadRow(item: it), const SizedBox(height: 10)],
        const SizedBox(height: 8),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: SwitchListTile(
            title: const Text('Upload on Wi-Fi only'),
            subtitle: const Text('Saves your data.'),
            value: s.settings.uploadOnWifiOnly,
            onChanged: (v) async {
              await s.saveSettings({'uploadOnWifiOnly': v});
              await s.queue.pump(retryFailed: true);
            },
          ),
        ),
        const SizedBox(height: 12),
        const InfoNote('Clips stay on your phone until they finish uploading. Nothing is lost if you close the app.'),
      ]),
    );
  }
}

class UploadRow extends StatelessWidget {
  const UploadRow({super.key, required this.item});

  final UploadItem item;

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final a = context.accent;
    final it = item;
    final (sub, tag, colour) = switch (it.status) {
      UploadStatus.uploading => ('${(it.progress * 100).round()}% · ${(it.bytes * it.progress / 1e6).round()} of ${it.size}', 'Uploading', a.main),
      UploadStatus.waitingWifi => ('${it.size} · waiting for Wi-Fi', 'Waiting', Tk.stone),
      UploadStatus.waitingOnline => ("${it.size} · goes when you're back online", 'Waiting', Tk.stone),
      UploadStatus.waitingGuardian => ('${it.size} · goes once your guardian says yes', 'Waiting', Tk.stone),
      UploadStatus.failed => (it.error ?? 'Stopped', 'Stopped', Tk.gold),
      UploadStatus.done => ('Uploaded · Pep is watching it', 'Done', a.main),
    };
    Widget? action = switch (it.status) {
      UploadStatus.waitingWifi => TextButton(onPressed: () => s.queue.useMobileData(it.id), child: const Text('Use mobile data instead')),
      UploadStatus.failed when it.retryable => TextButton(onPressed: () => s.queue.retry(it.id), child: const Text('Try again')),
      UploadStatus.failed => TextButton(onPressed: () => s.queue.remove(it.id), child: const Text('Remove')),
      UploadStatus.waitingGuardian => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GuardianScreen())),
          child: const Text('Your guardian'),
        ),
      UploadStatus.done when it.videoId != null => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoScreen(videoId: it.videoId!))),
          child: const Text('See it'),
        ),
      _ => null,
    };
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(it.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Tk.ink))),
          Text(tag, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colour)),
        ]),
        const SizedBox(height: 4),
        Text(sub, style: const TextStyle(fontSize: 13, color: Tk.muted)),
        if (it.status == UploadStatus.uploading) ...[
          const SizedBox(height: 10),
          ClipRRect(borderRadius: BorderRadius.circular(999), child: LinearProgressIndicator(value: it.progress, minHeight: 4)),
        ],
        if (action != null) Align(alignment: Alignment.centerLeft, child: action),
      ]),
    );
  }
}

/// The small card on Home while clips are waiting or going.
class UploadsCard extends StatelessWidget {
  const UploadsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final q = context.watch<AppState>().queue;
    final active = q.active;
    if (active.isEmpty) return const SizedBox.shrink();
    final going = active.where((i) => i.status == UploadStatus.uploading).firstOrNull;
    final stopped = active.where((i) => i.status == UploadStatus.failed).length;
    final title = going != null
        ? 'Uploading ${going.title} · ${(going.progress * 100).round()}%'
        : stopped > 0
            ? '$stopped upload${stopped == 1 ? '' : 's'} stopped'
            : '${active.length} clip${active.length == 1 ? '' : 's'} waiting to upload';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Panel(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UploadsScreen())),
        child: Row(children: [
          IconTile(icon: 'upload', color: context.accent.main, background: context.accent.tile, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Tk.ink)),
              if (going != null) ...[
                const SizedBox(height: 8),
                ClipRRect(borderRadius: BorderRadius.circular(999), child: LinearProgressIndicator(value: going.progress, minHeight: 4)),
              ] else
                const Text('Tap to see them', style: TextStyle(fontSize: 13, color: Tk.muted)),
            ]),
          ),
        ]),
      ),
    );
  }
}
