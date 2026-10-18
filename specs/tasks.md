# RoadSense Logger — Implementation Tasks

Status: `pending` → `in-progress` → `done (commit <hash>)` / `blocked (<reason>)`.
One commit per task; commit hash recorded when done. Tasks are dependency-ordered.

## T-001 Create root AGENTS.md
- Requirements: — (process)
- Files: `AGENTS.md`
- Deps: none
- Steps: write project conventions, technology choices, commit rules, prohibitions.
- Verification: file exists, content complete.
- Status: pending

## T-002 Write requirements specification
- Requirements: all (definition)
- Files: `specs/requirements.md`
- Deps: T-001
- Verification: FR/NFR/DATA IDs defined; live labelling explicitly excluded.
- Status: pending

## T-003 Write architecture specification
- Requirements: all (design)
- Files: `specs/architecture.md`
- Deps: T-002
- Verification: state machine, channels, schemas, resampling, recovery documented.
- Status: pending

## T-004 Write task checklist and acceptance criteria
- Requirements: all (planning)
- Files: `specs/tasks.md`, `specs/acceptance.md`
- Deps: T-002, T-003
- Verification: every FR/NFR/DATA maps to at least one task; acceptance criteria testable.
- Status: pending

## T-005 Scaffold Flutter project and base configuration
- Requirements: NFR-006, NFR-007
- Files: `pubspec.yaml`, `analysis_options.yaml`, `android/`, `lib/main.dart`, `.gitignore`
- Deps: T-004
- Steps: `flutter create` (Android platform), add pinned deps (riverpod, camera, path_provider,
  permission_handler, share_plus, archive, wakelock_plus, shared_preferences,
  play-services-location in Gradle), minSdk 26 / targetSdk 35, `HIGH_SAMPLING_RATE_SENSORS`
  + camera/location/audio/foreground-service permissions in manifest.
- Verification: `flutter analyze`, `flutter build apk --debug`, `flutter test`.
- Status: pending

## T-006 Core time math, CSV, errors, logging
- Requirements: DATA-006, DATA-007, FR-081, NFR-001
- Files: `lib/core/time/*`, `lib/core/csv/*`, `lib/core/errors/*`, `lib/core/logging/*`, tests
- Deps: T-005
- Verification: unit tests for timestamp conversion, CSV quoting/ordering.
- Status: pending

## T-007 Domain models and recording state machine
- Requirements: FR-002, DATA-001..005 (models)
- Files: `lib/domain/models/*`, `lib/domain/recording_state_machine.dart`, tests
- Deps: T-006
- Verification: unit tests for legal/illegal transitions.
- Status: pending

## T-008 Native Kotlin platform integration (sensors, clock, foreground service)
- Requirements: FR-023, FR-024, FR-028, FR-041, FR-006
- Files: `android/app/src/main/kotlin/.../*`, `lib/services/native/native_bridge.dart`, tests
- Deps: T-005
- Steps: SensorManager on HandlerThread, bounded batch queue, EventChannel batches, clock
  mapping, foreground service with FGS types, MethodChannel API.
- Verification: `flutter analyze`; Android JVM unit tests for batching queue.
- Status: pending

## T-009 Native Kotlin GPS integration
- Requirements: FR-030, FR-031, FR-033
- Files: native location collector, `lib/services/location/*`, tests
- Deps: T-008
- Verification: `flutter analyze`; unit tests for fix acceptance rules on Dart side.
- Status: pending

## T-010 SensorRecorder + GpsRecorder Dart services
- Requirements: FR-020..027, FR-032
- Files: `lib/services/sensors/*`, `lib/services/location/*`
- Deps: T-008, T-009, T-007
- Verification: unit tests with fake sources (rate measurement, overflow diagnostics).
- Status: pending

## T-011 VideoRecorder (CameraX via camera plugin)
- Requirements: FR-010..015
- Files: `lib/services/camera/*`, tests
- Deps: T-005, T-007
- Verification: unit tests for configuration resolution logic with fake camera.
- Status: pending

## T-012 SessionWriter incremental persistence
- Requirements: FR-052, DATA-001, DATA-002, DATA-007
- Files: `lib/data/session/session_writer.dart`, tests
- Deps: T-006, T-007
- Verification: unit tests for incremental writes, flush cadence hooks, schema order.
- Status: pending

## T-013 Resampler and merged.csv generation
- Requirements: FR-060..063, DATA-003
- Files: `lib/services/resampling/*`, tests
- Deps: T-006
- Verification: unit tests — interpolation, large gaps, duplicates, missing sensors, GPS
  forward-fill/staleness, empty input, boundaries.
- Status: pending

## T-014 metadata.json + diagnostics.json writers
- Requirements: DATA-004, DATA-005, FR-081
- Files: `lib/data/session/metadata_writer.dart`, `lib/data/session/diagnostics.dart`, tests
- Deps: T-006, T-007
- Verification: unit tests for serialization and unknown-value handling.
- Status: pending

## T-015 RecordingSessionManager orchestration
- Requirements: FR-001..006, FR-044, FR-053, FR-054
- Files: `lib/services/recording/*`, tests
- Deps: T-010, T-011, T-012, T-013, T-014
- Verification: unit tests for lifecycle, duplicate rejection, validation gate before COMPLETED.
- Status: pending

## T-016 Session repository and crash recovery
- Requirements: FR-055
- Files: `lib/data/session/session_repository.dart`, `lib/services/recovery/*`, tests
- Deps: T-012, T-014
- Verification: unit tests for incomplete detection, corrupt-tail truncation, recovered marking.
- Status: pending

## T-017 ExportManager (ZIP full / CSVs only / open folder)
- Requirements: FR-070, FR-071
- Files: `lib/services/export/*`, tests
- Deps: T-014, T-016
- Verification: unit tests for zip contents, missing files, collisions, failures.
- Status: pending

## T-018 UI: app shell, theme, routing, home/recording screen
- Requirements: FR-001, FR-004, FR-032
- Files: `lib/app/*`, `lib/features/home/*`, `lib/features/recording/*`, tests
- Deps: T-015
- Verification: widget tests for recording screen states and controls.
- Status: pending

## T-019 UI: pre-recording dialog and settings
- Requirements: FR-072, FR-073, FR-080
- Files: `lib/features/recording/pre_record_dialog.dart`, `lib/features/settings/*`, tests
- Deps: T-018
- Verification: widget tests for dialog fields, persistence, settings controls.
- Status: pending

## T-020 UI: session history, summary, export actions
- Requirements: FR-070, FR-074
- Files: `lib/features/sessions/*`, `lib/features/export/*`, tests
- Deps: T-017, T-018
- Verification: widget tests for list, summary unknowns, delete confirmation, export errors.
- Status: pending

## T-021 Permission flows and lifecycle hardening
- Requirements: FR-080, FR-005, FR-006
- Files: `lib/core/permissions/*`, `lib/services/recording/lifecycle.dart`, tests
- Deps: T-015, T-018
- Verification: widget/unit tests for denial paths; manual lifecycle behavior documented.
- Status: pending

## T-022 Integration test suite
- Requirements: FR-092
- Files: `test/integration/*`
- Deps: T-015..T-021
- Verification: `flutter test integration_test` where a device exists; otherwise record blocker.
- Status: pending

## T-023 README and documentation
- Requirements: NFR-005 (honesty), delivery requirements
- Files: `README.md`
- Deps: all implementation tasks
- Verification: README matches implemented behavior; limitations documented.
- Status: pending

## T-024 Final verification pass
- Requirements: FR-093
- Files: `specs/tasks.md` (statuses), final report in conversation
- Deps: all
- Verification: `flutter analyze`, `dart format` check, `flutter test`, `flutter build apk
  --debug`, `./gradlew test`, git log inspection.
- Status: pending
