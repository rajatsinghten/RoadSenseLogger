# RoadSense Logger

An Android application (Flutter + Dart + native Kotlin) that records
synchronized **rear-camera video**, **raw IMU** (accelerometer including
gravity, gyroscope) and **GPS** data for training road-roughness and
pothole-detection models.

The recorded video is later reviewed to **manually annotate** road conditions
and create ground-truth labels. RoadSense Logger deliberately does **not**
provide live road-condition labels (Smooth/Medium/Rough/Pothole/Speed Breaker),
marker buttons, automatic classification or live predictions.

## 1. Architecture

- **Flutter (UI + orchestration)** — Material 3 screens (recording, settings,
  session history), the `RecordingSessionManager` state machine
  (`IDLE → PREPARING → RECORDING → FINALIZING → COMPLETED`, plus `ERROR`,
  `INTERRUPTED`, `RECOVERING`), CSV persistence, resampling, export.
- **Native Kotlin (Android)** — `SensorManager` collection on a dedicated
  `HandlerThread` preserving `SensorEvent.timestamp`,
  `FusedLocationProviderClient` GPS preserving `Location.elapsedRealtimeNanos`,
  elapsed-realtime clock mapping, a foreground service, and permission plumbing.
- **CameraX video capture** through the Flutter `camera` plugin.
- **State management:** Riverpod only. Platform integrations sit behind seams
  (`SensorSource`, `LocationSource`, `VideoRecorder`, `NativeControl`) so the
  whole pipeline is unit-testable with deterministic fakes.

IMU events are batched natively every 100 ms over an `EventChannel` with their
**original timestamps**; sensor callbacks never touch the disk. Dart writes
`imu_raw.csv` / `gps.csv` incrementally (bounded buffers, ~1 s flush cadence).

See `specs/architecture.md` for the full design and `specs/requirements.md`
for the requirement IDs referenced throughout this README.

## 2. Prerequisites

- Flutter stable (developed against Flutter 3.41.x, Dart 3.11.x)
- Android SDK 36 + JDK 17+ (developed with OpenJDK 21)
- An Android device (min SDK 26) with camera, accelerometer, gyroscope
- Google Play Services (for `FusedLocationProviderClient`)

## 3. Setup and build

```bash
flutter pub get
flutter build apk --debug
```

Verification commands used by this project:

```bash
flutter doctor -v
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --debug
cd android && ./gradlew test   # native Kotlin unit tests
```

## 4. Permissions

| Permission | Why | When requested |
|---|---|---|
| Camera | Rear-camera video | Before first recording |
| Fine/Coarse location | GPS fixes | Before first recording |
| Record audio | Optional audio track | Only when audio is enabled in settings |
| High-rate sensors (manifest) | IMU above 200 Hz on Android 12+ | Not a runtime prompt |
| Foreground service (camera/location/microphone types) | Reliable long recordings | At recording start |
| Notifications | Foreground-service notification | With the service |

Denied camera permission blocks recording with a clear message. Missing GPS
only warns: you can explicitly choose to record without GPS (never fabricating
positions). No telemetry, no network upload; data leaves the device only if
you share it.

## 5. Recording workflow

1. Launch the app and grant permissions.
2. Check the live camera preview, GPS status, sensor readouts and free storage.
3. Press **Record**, confirm vehicle type, mount position and notes.
4. If no GPS fix exists yet, confirm explicitly to record without GPS.
5. Record — the screen shows elapsed time, speed, GPS age/accuracy, sensor
   magnitudes, achieved IMU rates, storage and warnings.
6. Press **Stop** — files are finalized, `merged.csv` generated, metadata and
   diagnostics written, and the session validated before being marked complete.

The screen stays awake and orientation is locked while recording; a foreground
service keeps the process eligible in the background.

## 6. Session directory structure

Active sessions live in app-specific storage
(`…/app_flutter/sessions/`, `session_YYYYMMDD_HHMMSS_<id>/`):

```text
session_YYYYMMDD_HHMMSS_<id>/
  video.mp4          rear-camera recording
  imu_raw.csv        every received IMU event (never resampled)
  gps.csv            every accepted GPS fix
  merged.csv         uniform-grid dataset (default 100 Hz)
  metadata.json      full session metadata (written last = completion marker)
  diagnostics.json   timestamped data-quality events
```

While writing, CSVs use `.part` names. A session without a valid
`metadata.json` is **incomplete**, never shown as complete.

## 7. CSV schemas and units

**`imu_raw.csv`** — one row per received event:

```text
timestamp_ns,t_video_s,unix_time_ms,sensor,x,y,z
```

`sensor` is `ACC` (m/s², **gravity included**) or `GYRO` (rad/s).

**`gps.csv`** — one row per accepted fix:

```text
timestamp_ns,t_video_s,unix_time_ms,latitude,longitude,altitude_m,speed_mps,bearing_deg,accuracy_m
```

**`merged.csv`** — uniform grid (default 100 Hz):

```text
t_video_s,unix_time_ms,acc_x,acc_y,acc_z,gyro_x,gyro_y,gyro_z,latitude,longitude,altitude_m,speed_mps,bearing_deg,gps_accuracy_m,gps_age_s,label
```

`label` is reserved for later manual annotation and is always empty in logged
data. CSV is UTF-8, RFC 4180-quoted, with one header row in the exact order
above. **Missing values are empty fields — never zero.**

## 8. Timestamp synchronization

- Master clock: Android **elapsed realtime**
  (`SystemClock.elapsedRealtimeNanos()`), monotonic and unaffected by
  wall-clock changes.
- Every event keeps its **original** timestamp: `SensorEvent.timestamp` (IMU),
  `Location.elapsedRealtimeNanos` (GPS).
- `t_video_s = (timestamp_ns − video_start_ns) / 1e9` (double precision;
  negative before the video start reference).
- `unix_time_ms` is derived from the session clock mapping (elapsed ↔
  wall-clock sample taken at session start) and is an **estimate**; later
  NTP/manual clock changes do not disturb the monotonic alignment.
- Raw events before or after the video interval are kept in the raw files and
  counted in `metadata.json`
  (`imu_events_outside_video_interval`, `gps_fixes_outside_video_interval`).

### Camera synchronization limitation

`video_start_ns` is sampled natively when the `camera` plugin reports
recording start (`"start_reference": "camera_plugin_start_completed"`). This
is **not** the exposure timestamp of the first encoded frame — encoder startup
latency is device-dependent. **Frame-accurate synchronization is not claimed**
without per-device validation. The same applies to `video_end_ns`.

## 9. Requested vs. achieved IMU rates

200 Hz (or 100 Hz / fastest) is a **request**, not a guarantee: actual rates
depend on device sensors and HAL batching. Each session records
`requested_rate` and the measured `achieved_rate_hz` per sensor (computed from
event counts and monotonic timestamps) in `metadata.json`. The live UI shows
the measured rate.

## 10. GPS limitations

GPS can be slow to fix, inaccurate in urban canyons/tunnels, and can stop
entirely. Fixes older than the configured maximum age (default 5 s) are marked
stale: `merged.csv` keeps `gps_age_s` but leaves the GPS columns empty. Speed
and bearing may be missing on stationary devices — those fields are empty.
Distance and average speed are derived only from consecutive accepted fixes.

## 11. Resampling and interpolation

`merged.csv` is generated at finalization on a uniform grid `t_i = i / rate`
(computed from `i`, so no cumulative floating-point drift), covering
`[video_start_ns, video_end_ns]` (inclusive of grid endpoints).

- **IMU:** linear interpolation between the bracketing samples' actual
  timestamps, only when the bracketing gap ≤ `max_imu_gap_ms` (default
  250 ms). A grid point exactly on sample timestamp(s) uses the last-arriving
  sample at that timestamp; duplicates are never averaged.
- **GPS:** forward-fill from the latest fix at or before the grid point — never
  future fixes, no coordinate interpolation.
- Missing values are empty fields; zero is never substituted.

## 12. Missing-data conventions

| Situation | Behavior |
|---|---|
| Sensor value unavailable | empty CSV field |
| Gyroscope absent on device | GYRO columns empty + `gyroscope_unavailable` diagnostic |
| IMU gap > threshold | empty IMU fields for rows in the gap |
| GPS fix stale / absent | empty GPS fields, `gps_age_s` preserved where a fix exists |
| Queue overflow | drops counted (`dropped_events`), `queue_overflow` diagnostic |
| Unknown summary values | shown as `—`, never 0 |

## 13. Crash recovery

Files are flushed about once per second. If the app dies, buffered events not
yet flushed can be lost — the loss window is **≤ ~1 s of events**; perfect
crash protection is not claimed. On next launch, sessions without a completion
marker are recovered: `.part` files are renamed, corrupt tails truncated, and
`metadata.json` is written with `"status": "recovered"` (never `completed`)
including retained row counts, problems and the loss-window estimate.
Recovered sessions may lack `merged.csv` (its generation needs the in-memory
video interval) and are labelled distinctly in the session history.

## 14. Export and sharing

From a session's detail screen:

- **Share full archive (ZIP)** — `video.mp4`, raw CSVs, `merged.csv`,
  `metadata.json`, `diagnostics.json`, streamed to the archive (no full-file
  copies in memory) and shared via a content URI.
- **Export CSVs only (ZIP)** — the dataset without video.
- **Open folder** — opens the session directory with a system file viewer
  where the device supports it (app-private storage limits what other apps can
  browse; sharing is the reliable path).
- **Delete session** — with confirmation.

## 15. Tests and verification

```bash
flutter analyze                       # static analysis
dart format --output=none --set-exit-if-changed .
flutter test                          # unit + widget tests
flutter build apk --debug             # debug APK
cd android && ./gradlew test          # native (JVM) unit tests
flutter test integration_test -d <id> # device-run integration tests
```

Integration tests (`integration_test/recording_pipeline_test.dart`) require a
physical device or emulator and pre-granted permissions (see the file header).
In environments without Android hardware they are **unverified** — the exact
blocker is recorded in the project's final verification report.

## 16. Known limitations

- `video_start_ns` is a recording-start event reference, not the first frame's
  exposure timestamp (see §8).
- Frame rate is a requested target only; the `camera` plugin does not expose
  FPS control or achieved FPS on Android (recorded in metadata as
  `fps_control_supported: false`).
- The camera plugin's preset mapping governs actual recording resolution;
  requested width/height and the chosen preset are both recorded.
- Finalization holds the session's IMU/GPS series in memory to interpolate
  `merged.csv` at full precision (recording-path memory stays bounded).
- Recovered sessions can lose ≤ ~1 s of buffered events and may lack
  `merged.csv`.
- Hardware behavior (rates, camera timing, GPS quality) is only verified on
  real devices; emulator results differ.

## 17. Data collection practices

- Mount the phone **rigidly** (windshield/dash mount, handlebar clamp) — loose
  mounts add noise that is indistinguishable from road bumps.
- Mounting orientation, mounting stiffness, vehicle suspension, speed and
  device model all influence accelerometer readings; record them (vehicle
  type, mount position, notes are stored in `metadata.json`).
- Raw accelerometer data **includes gravity**: a stationary phone reads
  ≈ 9.8 m/s² on one axis.
- Keep recordings reasonably short (tens of minutes) and check free storage.
- Create ground-truth labels by annotating the recorded video with a
  consistent protocol — the empty `label` column in `merged.csv` is there for
  the result.
