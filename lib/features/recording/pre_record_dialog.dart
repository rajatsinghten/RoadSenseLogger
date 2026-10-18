/// Pre-recording session configuration dialog (FR-073): vehicle type, mount
/// position and free-text notes.
library;

import 'package:flutter/material.dart';
import 'package:roadsense_logger/domain/models/session_config.dart';

/// Shows the dialog and returns the chosen config, or null on cancel.
Future<SessionConfig?> showPreRecordDialog(
  BuildContext context, {
  SessionConfig? initial,
}) {
  return showDialog<SessionConfig>(
    context: context,
    builder: (context) => PreRecordDialog(initial: initial),
  );
}

class PreRecordDialog extends StatefulWidget {
  const PreRecordDialog({super.key, this.initial});

  final SessionConfig? initial;

  @override
  State<PreRecordDialog> createState() => _PreRecordDialogState();
}

class _PreRecordDialogState extends State<PreRecordDialog> {
  late VehicleType _vehicleType;
  late MountPosition _mountPosition;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    _vehicleType = widget.initial?.vehicleType ?? VehicleType.car;
    _mountPosition = widget.initial?.mountPosition ?? MountPosition.dashboard;
    _notes = TextEditingController(text: widget.initial?.notes ?? '');
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Session details'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<VehicleType>(
            initialValue: _vehicleType,
            decoration: const InputDecoration(labelText: 'Vehicle type'),
            items: [
              for (final type in VehicleType.values)
                DropdownMenuItem(value: type, child: Text(type.id)),
            ],
            onChanged: (value) => setState(() => _vehicleType = value!),
          ),
          DropdownButtonFormField<MountPosition>(
            initialValue: _mountPosition,
            decoration: const InputDecoration(labelText: 'Mount position'),
            items: [
              for (final position in MountPosition.values)
                DropdownMenuItem(value: position, child: Text(position.id)),
            ],
            onChanged: (value) => setState(() => _mountPosition = value!),
          ),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes'),
            maxLines: 2,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              SessionConfig(
                vehicleType: _vehicleType,
                mountPosition: _mountPosition,
                notes: _notes.text.trim(),
              ),
            );
          },
          child: const Text('Start recording'),
        ),
      ],
    );
  }
}
