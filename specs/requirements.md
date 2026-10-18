# RoadSense Logger — Product Requirements

Status legend: `Draft` → `Approved` → `Implemented` → `Verified`.
All requirements are traceable to tasks in `specs/tasks.md` and acceptance criteria in
`specs/acceptance.md`.

## 1. Product overview

RoadSense Logger records synchronized rear-camera video, raw IMU (accelerometer with gravity,
gyroscope) and GPS data on an Android phone rigidly mounted in a vehicle. The output is a set of
per-session files suitable for later manual video annotation and model training.

**Explicitly out of scope:** live road-condition labelling (Smooth/Medium/Rough/Pothole/Speed
Breaker), marker buttons, automatic classification, live predictions. Ground-truth labels are
created later by manual video annotation.

## 2. Functional requirements — recording lifecycle

- **FR-001** The app shall provide a primary recording workflow: grant permissions, configure
  session metadata, pre-flight checks, start recording, live diagnostics, stop, finalize,
  validate, session summary, export/share/delete.
- **FR-002** The app shall implement the recording state machine
  `IDLE → PREPARING → RECORDING → FINALIZING → COMPLETED` with `ERROR`, `INTERRUPTED` and
  `RECOVERING` states. Duplicate start/stop operations shall be rejected.
- **FR-003** A session shall not be marked `COMPLETED` until all required files exist, are
  finalized, and pass schema/row validation.
- **FR-004** The app shall display elapsed recording time and live diagnostics (GPS status,
  speed, sensor magnitudes, achieved sensor rates, storage) while recording.
- **FR-005** The app shall keep the screen awake and lock orientation while recording, restoring
  previous behavior afterwards where feasible.
- **FR-006** Recording shall survive app backgrounding via a foreground service with appropriate
  service types. If continuation becomes unsafe, the app shall stop or recover the session safely
  and report what occurred.

## 3. Functional requirements — video

- **FR-010** The app shall record video from the rear (fallback: primary back) camera using
  CameraX, saving `video.mp4` in the session directory.
- **FR-011** Default video configuration shall be 1920×1080 at 30 FPS target where supported;
  resolution and frame rate shall be configurable in settings.
- **FR-012** Audio shall be disabled by default and enabled only by explicit user setting; audio
  permission shall be requested only when audio is enabled.
- **FR-013** The app shall display a live camera preview before and during recording.
- **FR-014** The app shall capture the CameraX recording-start event timestamp
  (`video_start_ns`, elapsed realtime) and the recording-stop/finalization timestamps.
- **FR-015** Camera initialization failures, unsupported configurations, and recording errors
  shall be surfaced to the user and recorded in diagnostics; requested vs. actual configuration
  shall be reported.

## 4. Functional requirements — IMU

- **FR-020** The app shall record raw `Sensor.TYPE_ACCELEROMETER` events (x, y, z in m/s²,
  gravity included; no transformation to linear acceleration).
- **FR-021** The app shall record raw `Sensor.TYPE_GYROSCOPE` events (x, y, z in rad/s).
- **FR-022** IMU target sampling rate shall be configurable: 100 Hz, 200 Hz (nominal 5 000 µs
  period), or fastest available; 200 Hz is default.
- **FR-023** Sensor collection shall run on a dedicated native background thread and shall
  preserve the original `SensorEvent.timestamp` for every event. Callback-arrival or wall-clock
  timestamps shall never replace it.
- **FR-024** Every received IMU event shall be persisted to `imu_raw.csv` unless a bounded queue
  overflow occurs, which shall be detected, counted, and reported (never silent).
- **FR-025** The app shall measure achieved accelerometer and gyroscope rates independently and
  report them as measured values (never the requested values).
- **FR-026** The app shall record sensor metadata (name, vendor, range, resolution) where
  available and detect timestamp gaps / irregular sampling.
- **FR-027** If the gyroscope is missing, recording shall continue with a user-visible warning
  and explicit missing-data behavior (empty fields, never zeros).
- **FR-028** The app shall declare `HIGH_SAMPLING_RATE_SENSORS` for high-rate sampling on
  Android 12+.

## 5. Functional requirements — GPS

- **FR-030** The app shall collect GPS fixes via `FusedLocationProviderClient` (high accuracy,
  ~1 000 ms interval) recording latitude, longitude, altitude (m), speed (m/s), bearing (deg),
  horizontal accuracy (m), `Location.elapsedRealtimeNanos`, and Unix time (ms).
- **FR-031** Every accepted fix shall be written to `gps.csv`; rejected/invalid fixes shall be
  counted and documented.
- **FR-032** The app shall display GPS status, accuracy and fix age during recording, and show
  the last valid speed with a staleness indication.
- **FR-033** If no GPS fix is available before recording, the app shall warn the user and
  require an explicit decision to proceed. GPS values shall never be fabricated.

## 6. Functional requirements — time synchronization

- **FR-040** The monotonic master clock shall be Android elapsed realtime
  (`SystemClock.elapsedRealtimeNanos()`).
- **FR-041** Each session shall capture `session_start_elapsed_ns`, `session_start_unix_ms`, the
  elapsed↔wall-clock mapping, `video_start_ns`, and stop/finalization timestamps.
- **FR-042** Every raw and merged row shall carry `timestamp_ns` (monotonic ns), `t_video_s`
  (double, `(timestamp_ns − video_start_ns) / 1e9`) and `unix_time_ms` where applicable.
- **FR-043** Wall-clock changes (NTP, manual) shall not disturb monotonic alignment; unix times
  are estimates derived from the session clock mapping and documented as such.
- **FR-044** Raw events slightly before or after the video interval shall be preserved in raw
  files; the merged dataset covers the validated video-relative interval only, with documented
  boundaries.

## 7. Functional requirements — persistence and schemas

- **FR-050** Each session shall be stored in a unique directory
  `session_YYYYMMDD_HHMMSS_<id>/` in app-specific storage; active sessions use temp names or
  completion markers until finalized.
- **FR-051** A completed session directory shall contain `video.mp4`, `imu_raw.csv`, `gps.csv`,
  `merged.csv`, `metadata.json`, `diagnostics.json` (plus optional session log).
- **FR-052** Data shall stream to disk incrementally (bounded buffers, ~1 s flush cadence);
  sensor callbacks shall never perform disk I/O; memory usage shall be bounded.
- **FR-053** CSV schemas (column names, order, units) shall follow `DATA-*` requirements exactly;
  missing values are empty fields, never zero-substituted.
- **FR-054** Storage shall be checked before recording; low-storage and write failures shall
  stop recording safely with actionable messages and diagnostics.
- **FR-055** Interrupted sessions shall be detected at next launch, identified as incomplete or
  recovered, validated, and never silently presented as complete. Buffered events at crash time
  may be lost; the loss window shall be minimized and documented.

## 8. Functional requirements — resampling

- **FR-060** A dedicated `Resampler` shall generate `merged.csv` on a uniform grid (default
  100 Hz, configurable) over the validated video-relative interval, with documented endpoint
  conventions and no cumulative floating-point drift.
- **FR-061** IMU channels shall use timestamp-based linear interpolation between valid
  neighbours; gaps larger than the configured threshold yield empty fields; duplicate timestamps
  and missing sensors are handled explicitly.
- **FR-062** GPS channels shall use forward-fill from the latest fix at or before each grid
  timestamp (never future fixes); `gps_age_s` is recorded; fixes older than the configured
  maximum age yield empty GPS fields.
- **FR-063** `merged.csv` shall contain no live labels; if a `label` column exists for future
  compatibility it stays empty until manual annotation.

## 9. Functional requirements — history, export, settings

- **FR-070** The app shall list past sessions with metadata, data-quality status and
  complete/incomplete/recovered identification, with actions: view metadata, inspect
  diagnostics, share full archive (ZIP), export CSVs only (ZIP), open/browse session folder,
  delete (with confirmation).
- **FR-071** `ExportManager` shall produce ZIP archives (full session and CSV-only) shared via
  content URIs / `FileProvider` with temporary read permissions; large videos shall not be
  needlessly duplicated.
- **FR-072** Settings shall include IMU target rate, merged CSV rate, video resolution and frame
  rate, audio on/off, maximum IMU interpolation gap, maximum GPS age; requested settings shall
  be visually distinguished from measured hardware behavior.
- **FR-073** The pre-recording dialog shall collect vehicle type (bike/car/auto/bus), mount
  position (handlebar/dashboard/windshield/other) and free-text notes; selections are remembered
  and stored in `metadata.json`.
- **FR-074** The session summary shall show duration, GPS-derived distance and average speed
  where calculable, event counts, achieved rates, video configuration, missing-data warnings and
  completion status; unknown values display as unavailable, never zero.

## 10. Functional requirements — permissions, privacy, errors

- **FR-080** The app shall request only camera, fine location, audio (when enabled), high-rate
  sensor (implicit via manifest) and foreground-service permissions, with rationale UI and safe
  denial handling.
- **FR-081** All failures shall surface actionable UI messages and be recorded in
  `diagnostics.json`; exceptions shall never be swallowed silently.
- **FR-082** The app shall collect no telemetry and upload no data; all data remains on device
  unless the user explicitly shares it.

## 11. Non-functional requirements

- **NFR-001** Timestamp fidelity: original event timestamps preserved end-to-end; relative
  timestamps computed in double precision.
- **NFR-002** Reliability: bounded memory, bounded queues with overflow diagnostics,
  deterministic resource release, no duplicate listeners or recordings.
- **NFR-003** Performance: sensor callbacks non-blocking; disk writes off the sensor thread;
  UI responsive during recording.
- **NFR-004** Testability: core logic (resampling, time math, serialization, state machine,
  recovery, export) covered by automated tests with deterministic fakes.
- **NFR-005** Honesty: requested configuration is never presented as achieved behavior; hardware
  claims require evidence; unverified items are explicitly marked.
- **NFR-006** Compatibility: modern Android (min SDK 26, target SDK 35+) with runtime
  permissions, scoped storage, and foreground-service type compliance.
- **NFR-007** Maintainability: layered architecture, single state-management solution
  (Riverpod), interface seams for platform integration, spec traceability.

## 12. Data requirements

- **DATA-001** `imu_raw.csv` columns (exact order):
  `timestamp_ns,t_video_s,unix_time_ms,sensor,x,y,z` with `sensor` ∈ {`ACC`,`GYRO`}; one row per
  actual received event; x/y/z in m/s² (ACC) or rad/s (GYRO); never resampled or silently
  filtered.
- **DATA-002** `gps.csv` columns (exact order):
  `timestamp_ns,t_video_s,unix_time_ms,latitude,longitude,altitude_m,speed_mps,bearing_deg,accuracy_m`;
  unavailable optional fields (altitude/speed/bearing/accuracy) are empty strings; rejected
  fixes are counted in diagnostics, not written.
- **DATA-003** `merged.csv` columns (exact order):
  `t_video_s,unix_time_ms,acc_x,acc_y,acc_z,gyro_x,gyro_y,gyro_z,latitude,longitude,altitude_m,speed_mps,bearing_deg,gps_accuracy_m,gps_age_s`
  (an optional trailing `label` column stays empty). Missing values are empty fields.
- **DATA-004** `metadata.json` shall include: app version, session ID, device manufacturer and
  model, Android version, session start/end (elapsed ns + unix ms) and duration, clock mapping,
  video_start_ns and finalization timestamps, actual video configuration, audio setting, sensor
  metadata (name/vendor/range/resolution), requested and achieved sensor rates, GPS
  configuration and fix statistics, event counts, merged rate and row count, missing-data and
  quality statistics, GPS-derived distance (m) and average speed (m/s) where calculable, vehicle
  type, mount position, notes, completion/interruption/recovery status.
- **DATA-005** `diagnostics.json` shall record timestamped data-quality events: sensor
  availability changes, timestamp gaps, queue overflows, GPS outages/stale fixes, storage
  errors, camera failures, recording interruptions, recovery actions, dataset validation
  failures. No unrelated sensitive information.
- **DATA-006** `t_video_s = (timestamp_ns − video_start_ns) / 1e9` in double precision;
  `unix_time_ms` derived from the session clock mapping:
  `unix_ms = session_start_unix_ms + (timestamp_ns − session_start_elapsed_ns) / 1e6`.
- **DATA-007** All CSV files use RFC 4180 quoting for text fields, UTF-8 encoding, `\n` or
  platform-consistent line endings, and a single header row with the exact column order above.
- **DATA-008** Raw events outside the merged interval are retained in raw files and counted in
  metadata (`*_events_outside_video_interval`); merged boundaries are
  `[video_start_ns, video_end_ns]` inclusive of endpoints on the uniform grid.

## 13. Verification requirements

- **FR-090** Unit tests cover interpolation, gaps, duplicates, missing sensors, GPS forward-fill
  and staleness, time-grid generation, timestamp conversion, CSV schemas/escaping, metadata
  serialization, state transitions, session recovery, and ZIP export success/failure.
- **FR-091** Widget tests cover recording screen states, permission/init errors, recording
  controls, pre-recording dialog, settings, session summary/history and export failures.
- **FR-092** Integration tests cover session creation, capture, persistence, finalization,
  merged generation, export, permission-denied flows and recovery where hardware/emulators
  permit; otherwise the exact blocker is recorded.
- **FR-093** The project builds (`flutter build apk --debug`) and passes `flutter analyze`,
  `dart format` check and `flutter test` in the development environment.
