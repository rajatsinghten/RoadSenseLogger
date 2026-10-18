/// Recording settings (FR-072). All values here are *requested* settings;
/// achieved hardware behavior is reported in session metadata after
/// recording (NFR-005).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roadsense_logger/app/providers.dart';
import 'package:roadsense_logger/domain/models/session_config.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Requested settings — achieved hardware behavior is reported '
            'in each session\'s metadata.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<ImuRateSetting>(
            initialValue: settings.imuRate,
            decoration: const InputDecoration(labelText: 'IMU target rate'),
            items: [
              for (final rate in ImuRateSetting.values)
                DropdownMenuItem(value: rate, child: Text(rate.label)),
            ],
            onChanged: (value) =>
                controller.update(settings.copyWith(imuRate: value)),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<double>(
            initialValue: settings.mergedRateHz,
            decoration: const InputDecoration(
              labelText: 'Merged CSV rate (Hz)',
            ),
            items: const [
              DropdownMenuItem(value: 50.0, child: Text('50 Hz')),
              DropdownMenuItem(value: 100.0, child: Text('100 Hz')),
              DropdownMenuItem(value: 200.0, child: Text('200 Hz')),
            ],
            onChanged: (value) =>
                controller.update(settings.copyWith(mergedRateHz: value)),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: '${settings.videoWidth}x${settings.videoHeight}',
            decoration: const InputDecoration(labelText: 'Video resolution'),
            items: const [
              DropdownMenuItem(value: '1280x720', child: Text('1280 × 720')),
              DropdownMenuItem(value: '1920x1080', child: Text('1920 × 1080')),
              DropdownMenuItem(value: '2560x1440', child: Text('2560 × 1440')),
            ],
            onChanged: (value) {
              final parts = value!.split('x');
              controller.update(
                settings.copyWith(
                  videoWidth: int.parse(parts[0]),
                  videoHeight: int.parse(parts[1]),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: settings.videoFps,
            decoration: const InputDecoration(
              labelText: 'Video frame rate (target)',
            ),
            items: const [
              DropdownMenuItem(value: 24, child: Text('24 FPS')),
              DropdownMenuItem(value: 30, child: Text('30 FPS')),
              DropdownMenuItem(value: 60, child: Text('60 FPS')),
            ],
            onChanged: (value) =>
                controller.update(settings.copyWith(videoFps: value)),
          ),
          SwitchListTile(
            title: const Text('Record audio'),
            subtitle: const Text(
              'Off by default; microphone permission is requested only when on',
            ),
            value: settings.audioEnabled,
            onChanged: (value) =>
                controller.update(settings.copyWith(audioEnabled: value)),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<double>(
            initialValue: settings.maxImuGapMs,
            decoration: const InputDecoration(
              labelText: 'Maximum IMU interpolation gap (ms)',
            ),
            items: const [
              DropdownMenuItem(value: 100.0, child: Text('100 ms')),
              DropdownMenuItem(value: 250.0, child: Text('250 ms')),
              DropdownMenuItem(value: 500.0, child: Text('500 ms')),
            ],
            onChanged: (value) =>
                controller.update(settings.copyWith(maxImuGapMs: value)),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<double>(
            initialValue: settings.maxGpsAgeS,
            decoration: const InputDecoration(
              labelText: 'Maximum GPS fix age (s)',
            ),
            items: const [
              DropdownMenuItem(value: 2.0, child: Text('2 s')),
              DropdownMenuItem(value: 5.0, child: Text('5 s')),
              DropdownMenuItem(value: 10.0, child: Text('10 s')),
            ],
            onChanged: (value) =>
                controller.update(settings.copyWith(maxGpsAgeS: value)),
          ),
        ],
      ),
    );
  }
}
