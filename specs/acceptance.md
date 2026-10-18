# RoadSense Logger — Acceptance Criteria

Each criterion is testable and traces to requirements. `Verified` requires evidence (test name,
build output, or device observation). Unverified items state the exact blocker.

## AC-01 Recording start and stop (FR-001, FR-002)
- Given permissions granted and pre-flight passed, pressing Record moves
  `IDLE → PREPARING → RECORDING` exactly once; a second press during PREPARING/RECORDING is
  rejected. Stop moves `RECORDING → FINALIZING → COMPLETED`.
- Evidence: unit tests `recording_session_manager_test.dart`, `recording_state_machine_test.dart`.

## AC-02 Real sensor collection (FR-020..027)
- During a real recording, `imu_raw.csv` contains rows with `sensor` `ACC` and `GYRO`, original
  nanosecond timestamps, m/s² and rad/s magnitudes consistent with a stationary device
  (ACC ≈ 9.8 m/s² magnitude) and zero rotation (GYRO ≈ 0 rad/s), and measured rates reported in
  `metadata.json`. No fabricated rows.
- Evidence: integration test + device recording (hardware-dependent).

## AC-03 GPS collection (FR-030..033)
- `gps.csv` rows carry monotonic + derived unix timestamps and valid lat/lon; fields without a
  sensor value (e.g. bearing when stationary) are empty; missing initial fix triggers the
  explicit proceed warning; GPS-less recording never writes fabricated coordinates.
- Evidence: integration/device test; widget test for the warning path.

## AC-04 Video timestamp alignment (FR-014, FR-042, DATA-006)
- `metadata.json` contains `video_start_ns` and the documented reference kind; every row's
  `t_video_s` equals `(timestamp_ns − video_start_ns)/1e9` within 1 µs; README/metadata state
  that the reference is not the first frame's exposure time.
- Evidence: unit test for the conversion; metadata fields inspected in a recorded session.

## AC-05 Achieved sampling-rate reporting (FR-025, NFR-005)
- `metadata.json` reports `requested_rate_hz` and `achieved_rate_hz` separately for ACC and
  GYRO; achieved values are computed from event counts and monotonic time, not copied from
  settings.
- Evidence: unit test on rate computation; device metadata inspection.

## AC-06 CSV schemas and units (DATA-001..003, DATA-007)
- Header rows match the specified column names and order exactly; units encoded in column names;
  RFC 4180 quoting applied; missing values are empty fields (never `0` placeholders).
- Evidence: unit tests `csv_writer_test.dart`, `schema_test.dart`.

## AC-07 Resampling (FR-060..063)
- `merged.csv` grid spacing is uniform at the configured rate (default 100 Hz); IMU values at
  grid points equal linear interpolation of bracketing samples; rows inside a >threshold gap have
  empty IMU fields; GPS columns equal the latest fix at or before the grid time with correct
  `gps_age_s`; stale GPS yields empty GPS fields; no future fixes used.
- Evidence: unit tests `resampler_test.dart` (gaps, duplicates, missing sensors, boundaries,
  empty input).

## AC-08 Missing and stale data (FR-027, FR-033, FR-062, DATA-*006)
- With gyroscope absent: GYRO columns empty, warning recorded in diagnostics and surfaced in UI.
- Stale GPS (> max age): GPS fields empty and `gps_age_s` present; last speed displayed with
  staleness indicator during recording.
- Evidence: unit + widget tests.

## AC-09 Incremental persistence (FR-052)
- During recording, CSV files on disk grow while recording proceeds (flush ~1 s); sensor
  callbacks perform no file I/O (native callback only enqueues); queues are bounded with
  overflow counters when exceeded.
- Evidence: unit test for writer flush behavior; native JVM test for bounded queue; code
  inspection of sensor callback path.

## AC-10 Crash recovery (FR-055)
- A session without the completion marker is listed as incomplete at next launch; recovery
  validates rows, truncates corrupt tails, marks `recovered` with retained-row counts and loss
  window; it is never presented as complete.
- Evidence: unit tests `session_recovery_test.dart`.

## AC-11 Export and sharing (FR-070, FR-071)
- Full ZIP contains `video.mp4`, `imu_raw.csv`, `gps.csv`, `merged.csv`, `metadata.json`,
  `diagnostics.json`; CSV-only ZIP excludes video; missing files produce a failure with a clear
  message; share uses content URIs (FileProvider) — verified in share flow on device.
- Evidence: unit tests `export_manager_test.dart`; device share test (hardware-dependent).

## AC-12 Permissions and lifecycle (FR-005, FR-006, FR-080)
- Only camera, fine location, audio (when enabled) and foreground-service permissions are
  required; denial is handled with explanation and no crash; screen stays awake and orientation
  locked during recording; foreground service runs during recording with correct types.
- Evidence: widget tests for denial paths; manifest inspection; device observation.

## AC-13 State machine integrity (FR-002, NFR-002)
- Illegal transitions throw; duplicate listeners/recordings impossible; resources released on
  every exit path (unit-tested with fakes tracking dispose calls).
- Evidence: `recording_state_machine_test.dart`, `recording_session_manager_test.dart`.

## AC-14 Session history and summary (FR-070, FR-074)
- History lists sessions with status (complete/incomplete/recovered); summary shows duration,
  counts, achieved rates, video config, distance/average speed when calculable and `—` (not 0)
  when not; delete requires confirmation.
- Evidence: widget tests.

## AC-15 Settings (FR-072)
- Settings persist across launches and affect the next session; UI labels requested values as
  "requested" and shows measured values separately after recording.
- Evidence: widget tests + settings persistence test.

## AC-16 Final build and automated tests (FR-090..093)
- `flutter analyze` clean; `dart format --output=none --set-exit-if-changed .` clean;
  `flutter test` passes; `flutter build apk --debug` produces an APK; Android JVM tests pass.
  Any command that cannot run records the exact blocker.
- Evidence: command output in final report.
