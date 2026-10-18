# AGENTS.md — RoadSense Logger

## Project purpose and scope

RoadSense Logger is an Android application (Flutter + Dart + native Kotlin) that collects
synchronized rear-camera video, IMU (accelerometer with gravity, gyroscope), and GPS data for
training road-roughness and pothole-detection models.

In scope: session configuration, concurrent video/IMU/GPS capture, timestamp synchronization,
incremental persistence, resampling to a uniform grid, crash recovery, session history, export.

Out of scope (explicitly excluded): live road-condition labelling (Smooth/Medium/Rough/Pothole/
Speed Breaker), marker buttons, automatic classification, live predictions. Ground-truth labels
are produced later by manual video annotation.

## Technology choices

- Flutter stable channel, Dart with sound null safety, Flutter Material 3.
- Native Android in Kotlin for: sensor collection (SensorManager + HandlerThread) preserving
  `SensorEvent.timestamp`, GPS via `FusedLocationProviderClient` preserving
  `Location.elapsedRealtimeNanos`, elapsed-realtime clock mapping, foreground service, and
  Android-specific lifecycle/permission/storage integration.
- CameraX-backed video capture through the Flutter `camera` plugin.
- One state-management solution only: Riverpod (`flutter_riverpod`).
- Kotlin coroutines for native background work; Dart async streams for data flow.
- Buffered, incremental CSV/JSON file writing.

## Architecture and directory conventions

Layered, feature-first hybrid (see `specs/architecture.md` for the full contract):

- `lib/app/` — application bootstrap, theme, routing.
- `lib/core/` — errors, logging, permissions, time, utilities (framework-agnostic helpers).
- `lib/domain/` — models, repository/service interfaces, use cases (no Flutter imports).
- `lib/data/` — serialization, storage, session repositories implementing domain interfaces.
- `lib/features/` — UI: `home`, `recording`, `sessions`, `settings`, `export`.
- `lib/services/` — recording orchestration and platform integrations (camera, sensors,
  location, recording, resampling, export).
- `android/app/src/main/kotlin/` — native Kotlin: sensor/location collectors, foreground
  service, clock mapping, channel plumbing.
- `specs/` — requirements, architecture, tasks, acceptance (spec-driven development).
- `test/unit/`, `test/widget/` — automated tests; `integration_test/` —
  device-run integration tests (standard Flutter convention).

Use constructor-based dependency injection and interface seams for testability. Keep UI code
free of direct file I/O and platform-channel access.

## Coding standards

- Sound null safety; no dynamic where a type is known; prefer final/const.
- Public APIs documented where behavior is non-obvious (units, timestamps, missing values).
- Existing formatting is authoritative: run `dart format` before committing.
- No dead code, no commented-out code blocks, no placeholder/TODO implementations.
- Functions do one thing; names reflect units where relevant (`*_ns`, `*_ms`, `*_s`, `*_m`, `*_mps`).

## Sensor timestamps and synchronization (critical)

- Monotonic master clock: Android `SystemClock.elapsedRealtimeNanos()`.
- Preserve original event timestamps: `SensorEvent.timestamp` for IMU,
  `Location.elapsedRealtimeNanos` for GPS, CameraX recording-start event time for video.
- NEVER replace event timestamps with callback-arrival or wall-clock timestamps.
- `t_video_s = (timestamp_ns - video_start_ns) / 1e9` computed in double precision.
- `unix_time_ms` derived from the captured session clock mapping (elapsed ↔ wall clock);
  wall-clock changes must not disturb monotonic alignment.
- The camera recording-start event is NOT the exposure time of the first encoded frame. Document
  this limitation; never claim frame-accurate synchronization without validation.

## Storage, file writing, crash recovery

- Each session gets a unique directory `session_YYYYMMDD_HHMMSS_<id>/` under the app-specific
  documents directory; finalized sessions are exported to user-accessible storage via supported
  Android storage APIs (no broad filesystem permissions).
- Stream data to disk incrementally with bounded in-memory buffers and ~1 s flush cadence.
- Sensor callbacks must never perform disk I/O; use bounded queues with explicit overflow
  detection and diagnostics.
- Sessions are finalized atomically where possible (temp names / completion markers); incomplete
  or recovered sessions must be identified as such and validated before being called complete.
- Never claim crash protection beyond what is implemented: buffered events at crash time can be
  lost; minimize and document the loss window.

## Permissions and privacy

- Request only: camera, fine location, audio (only when audio enabled), and any high-rate sensor
  permission required by the target SDK. Foreground-service permissions per service types used.
- Explain each permission to the user; handle denial without crashing or fabricating data.
- No telemetry, no network upload, no collection beyond the recorded session data.

## Testing and acceptance

- Unit tests for: resampling/interpolation (gaps, duplicates, missing sensors, boundaries),
  GPS forward-fill and staleness, timestamp conversion, CSV schema/escaping, metadata
  serialization, state-machine transitions, session recovery, ZIP export contents/failures.
- Widget tests for: recording screen states, permission/init errors, pre-recording dialog,
  settings, session summary/history, export failure handling.
- Integration tests where hardware/emulator support exists (may be unverified in CI-less envs —
  record the exact reason).
- Android native unit tests for native batching/timestamp logic.
- Acceptance criteria live in `specs/acceptance.md`; every requirement must trace to tasks,
  implementation, and tests.

## Required build and verification commands

```bash
flutter doctor -v
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --debug
```

Also run Android native tests (`./gradlew test`) and lint where applicable. Fix failures caused
by implementation changes. Never claim tests passed without running them; record exact reasons
for any command that cannot run in the current environment.

## Dependency management

- Add the smallest number of maintained, compatible dependencies; pin sensible versions in
  `pubspec.yaml` and commit `pubspec.lock`.
- Do not assume a plugin exposes specific timestamps/rates/lifecycle events; verify, and fall
  back to native Kotlin when fidelity is insufficient.
- No dependency may silently transform sensor data (e.g. linear acceleration).

## Error handling and diagnostic logging

- Failures surface to the UI with actionable messages and are recorded in `diagnostics.json`
  and an optional session log. No swallowed exceptions.
- Data-quality events (sensor gaps, queue overflows, GPS outages, stale fixes, storage errors,
  camera failures, interruptions, recovery actions) are recorded with timestamps and counts.
- Requested settings are never presented as achieved behavior; report measured rates/configs.

## Git commit conventions (mandatory)

- One commit per completed implementation task; never accumulate the whole app in one commit.
- Message format: `(type) Short, one-line description` with type one of
  `feat | fix | chore | refactor | test | docs | perf | build`.
- One line only, preferably under 72 characters, no bodies or bullet lists, no empty commits.
- Stage only files belonging to the completed task; preserve unrelated user work; no destructive
  git commands, no history rewriting, no bypassing hooks. Never commit secrets.

## Spec-driven development and traceability

- `specs/` is the source of truth: requirements (`FR-*`, `NFR-*`, `DATA-*`), architecture,
  task checklist (with per-task status + commit hash), acceptance criteria.
- Update task status and commit hashes as work completes; keep requirements ↔ tasks ↔ code ↔
  tests ↔ acceptance traceable.

## Prohibited

- Fake or simulated sensor data, placeholder implementations, mock screens pretending to work.
- Silently dropping samples, reducing requested sampling rates, removing required fields, or
  substituting zero for missing measurements (missing values are empty CSV fields).
- Claiming unverified completion (tests/builds/hardware behavior) — mark unverified work
  explicitly with the exact blocker.
