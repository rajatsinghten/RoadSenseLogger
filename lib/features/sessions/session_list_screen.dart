/// Session history (FR-070): lists sessions with status identification and
/// navigates to per-session summaries and export actions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roadsense_logger/app/providers.dart';
import 'package:roadsense_logger/data/session/session_repository.dart';
import 'package:roadsense_logger/domain/models/session_metadata.dart';
import 'package:roadsense_logger/features/sessions/session_detail_screen.dart';

class SessionListScreen extends ConsumerStatefulWidget {
  const SessionListScreen({super.key});

  @override
  ConsumerState<SessionListScreen> createState() => _SessionListScreenState();
}

class _SessionListScreenState extends ConsumerState<SessionListScreen> {
  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(sessionRepositoryProvider).listSessions();
    return Scaffold(
      appBar: AppBar(title: const Text('Sessions')),
      body: sessions.isEmpty
          ? const Center(child: Text('No sessions recorded yet'))
          : ListView.builder(
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final record = sessions[index];
                return ListTile(
                  title: Text(record.id),
                  subtitle: Text(_subtitle(record)),
                  trailing: _StatusChip(status: record.status),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) => SessionDetailScreen(
                          record: record,
                          exporter: ref.read(exportManagerProvider),
                          onDelete: (id) async {
                            await ref
                                .read(sessionRepositoryProvider)
                                .deleteSession(id);
                          },
                        ),
                      ),
                    );
                    if (mounted) setState(() {});
                  },
                );
              },
            ),
    );
  }

  String _subtitle(SessionRecord record) {
    final duration = record.durationS;
    final durationText = duration == null
        ? 'duration unavailable'
        : '${duration.toStringAsFixed(1)} s';
    return '$durationText · '
        'ACC ${record.accEventCount ?? '—'} · '
        'GPS ${record.gpsFixCount ?? '—'}';
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final SessionStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      SessionStatus.completed => ('complete', Colors.green),
      SessionStatus.recovered => ('recovered', Colors.orange),
      SessionStatus.incomplete => ('incomplete', Colors.red),
    };
    return Chip(
      label: Text(label),
      backgroundColor: color.withValues(alpha: 0.2),
    );
  }
}
