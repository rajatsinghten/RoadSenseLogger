# RoadSense Logger — Architecture

Companion to `requirements.md` (FR/NFR/DATA IDs referenced below).

## 1. High-level design

Layered, feature-first hybrid. Dependencies point inward: UI → services → domain; data and
platform implementations satisfy domain interfaces. One state-management solution: Riverpod
(`flutter_riverpod`); UI widgets read `StateNotifier`/`Notifier` state and never touch files or
platform channels directly.

```
UI (lib/features)  ──►  Recording orchestration (lib/services)
                              │
        ┌─────────────────────┼──────────────────────┐
        ▼                     ▼                      ▼
  platform channels    persistence (lib/data)   domain (lib/domain)
  (camera/sensors/     SessionWriter,           models, interfaces,
   location/native)    Resampler, ExportManager  state machine
```

Directory layout per `AGENTS.md`. `lib/core` holds cross-cutting pure helpers (time math, CSV,
errors, logging) with no Flutter/plugin imports where possible so they are unit-testable with
plain `dart test`-style fakes.

## 2. Native Kotlin integration boundary

Two EventChannels + one MethodChannel under the `roadsense/native` channel namespace:

| Channel | Direction | Payload |
|---|---|---|
| `roadsense/native` (MethodChannel) | Dart → native | `initSensors`, `startSensors{accPeriodUs,gyroPeriodUs}`, `stopSensors`, `startGps{intervalMs}`, `stopGps`, `getSensorInfo`, `getClockMapping`, `startForeground`, `stopForeground`, `openFolder{path}` |
| `roadsense/sensors` (EventChannel) | native → Dart | batched event maps (see §4) |
| `roadsense/gps` (EventChannel) | native → Dart | one map per accepted fix |

### 2.1 Why batch over an EventChannel

IMU at 200 Hz × 2 sensors ≈ 400 events/s. Per-event channel calls would impose scheduling
overhead and jitter. The native `SensorEventListener` therefore appends events (using the
original `SensorEvent.timestamp`) into an `ArrayDeque` guarded by a lock, and a `Handler` on the
same `HandlerThread` drains the deque into a batch every **100 ms** (≈ 40 events/sends per
sensor) and emits one `StandardMethodCodec`-encoded list per batch. Sensor callbacks perform no
disk I/O and no serialization beyond the append. The deque is bounded (default 8 192 events);
on overflow the oldest batch window is dropped and a `queue_overflow` diagnostic event is
emitted with a counter (FR-024, NFR-002).

Trade-off: persistence happens in Dart (`SessionWriter`), keeping CSV logic testable and shared
with recovery paths, at the cost of one extra in-memory hop. Native-on-disk writing was
rejected because it duplicates CSV/schema logic in Kotlin and complicates merged generation and
validation.

### 2.2 GPS

`FusedLocationProviderClient` (`play-services-location`) with
`Priority.PRIORITY_HIGH_ACCURACY`, `intervalMs=1000`, `minUpdateIntervalMs=500`. The
`LocationCallback` forwards each accepted fix immediately (low rate). Acceptance rules: valid
`latitude ∈ [-90,90]`, `longitude ∈ [-180,180]`, `elapsedRealtimeNanos > 0`; altitude/speed/
bearing/accuracy are forwarded only when `has*()` is true (missing → null → empty CSV field).
Rejected fixes increment a counter and emit a diagnostic (FR-031).

### 2.3 Clock mapping (FR-041, DATA-006)

Native `getClockMapping` returns `{elapsed_ns, unix_ms}` sampled together
(`SystemClock.elapsedRealtimeNanos()` + `System.currentTimeMillis()`). Dart stores the first
sample as `session_start_*`; all `unix_time_ms` values are derived from it. Wall-clock jumps
never affect `timestamp_ns`/`t_video_s` (monotonic), and unix estimates are documented as
estimates.

### 2.4 Foreground service (FR-006)

`RecordingForegroundService` (`foregroundServiceType="camera|location|microphone"`) started by
the MethodChannel call while the app is in the foreground at recording start, stopped at
finalization. It holds a low-importance notification ("RoadSense recording in progress") and no
data of its own — it keeps the process eligible during long recordings. Microphone type is only
requested when audio is enabled.

## 3. Recording state machine (FR-002)

States: `IDLE, PREPARING, RECORDING, FINALIZING, COMPLETED, ERROR, INTERRUPTED, RECOVERING`.

| From | Event | To |
|---|---|---|
| IDLE | `start` | PREPARING |
| PREPARING | all subsystems ready + `video_start_ns` captured | RECORDING |
| PREPARING | any subsystem failure | ERROR (resources released) |
| RECORDING | `stop` | FINALIZING |
| RECORDING | subsystem loss (camera error, storage full) | INTERRUPTED → FINALIZING (best-effort) |
| FINALIZING | files validated | COMPLETED |
| FINALIZING | validation failure | ERROR (session kept, marked incomplete) |
| any active | `start`/`stop` duplicates | rejected (ignored with warning) |
| startup | incomplete session found | RECOVERING → validate → COMPLETED or stays incomplete |

`RecordingStateMachine` is a pure Dart class: illegal transitions throw `StateTransitionError`
and are unit-tested. `RecordingSessionManager` is the sole owner of the machine.

## 4. Data contracts (Dart ↔ native)

Batch map: `{ "sensor": "ACC"|"GYRO", "events": [ [timestamp_ns(double), x, y, z], ... ] }`.
GPS fix map: `{ timestamp_ns, unix_time_ms, latitude, longitude, altitude_m?, speed_mps?,
bearing_deg?, accuracy_m?, accepted, reason? }`. Values arrive as `double`/`int`/`null`; null
means "not available" and becomes an empty CSV field (never 0).

## 5. Recording orchestration

`RecordingSessionManager` wires everything (constructor-injected interfaces):

1. **PREPARING**: create session dir + `SessionWriter`; clock mapping sample; pre-flight storage
   check; init camera (requested config); start native sensors + GPS; start foreground service;
   start `VideoRecorder`; capture `video_start_ns` from the plugin's recording-start event
   (elapsed realtime sampled natively at the moment `startVideoRecording` completes — see §6).
2. **RECORDING**: `SensorRecorder` and `GpsRecorder` forward batches to `SessionWriter` (bounded
   Dart-side queues, 1 s flush); a 1 Hz ticker publishes live metrics (achieved rates computed
   from event counts per wall interval over monotonic deltas).
3. **FINALIZING**: stop intake → flush writers → stop camera (await `video.mp4` finalization,
   capture `video_end_ns`) → stop GPS/sensors/foreground service → run `Resampler` → write
   `metadata.json` + `diagnostics.json` → validate session → atomically mark complete
   (`metadata.json` written last with `"status": "completed"`; a session lacking this marker is
   incomplete).

`SessionWriter` writes each CSV with a single header row and appends rows; flush cadence ~1 s
and on each N rows; `close()` is deterministic (FR-052).

## 6. Video timing (FR-014, honest limitation)

The `camera` plugin (CameraX-backed) does not expose CameraX's `Recording.start` callback
timestamp to Dart. `video_start_ns` is therefore sampled as `SystemClock.elapsedRealtimeNanos()`
natively at the instant the plugin's `startVideoRecording` future completes (the closest
available recording-start event). **This is not the exposure timestamp of the first encoded
frame**; encoder startup latency is device-dependent. All `t_video_s` values inherit this
reference; frame-accurate synchronization is not claimed without per-device validation.
Recorded in `metadata.json` as `video_start_reference: "camera_plugin_start_completed"`.

## 7. Session storage (FR-050)

Active session: `getApplicationDocumentsDirectory()/sessions/session_YYYYMMDD_HHMMSS_<6-hex>/`.
Files are written as `*.csv.part` names and renamed on finalization where practical;
`metadata.json` is the completion marker (written last). Session ID = directory suffix.
Export to user-accessible storage uses Android share intents / SAF (content URIs) — no broad
filesystem permissions (NFR-006).

## 8. CSV schemas (DATA-001/2/3/7)

Exact column orders in `requirements.md` §12. `lib/data/serialization/csv.dart` owns quoting
(RFC 4180: quote fields containing `,`, `"`, or newline; double internal quotes) and number
formatting: `timestamp_ns` as integer, floats as fixed-precision (up to 9 significant decimals,
trailing zeros trimmed), missing → empty field. Units are encoded in column names.

## 9. Resampling (FR-060..063)

Pure Dart `Resampler.generate(...)` producing grid rows for `t ∈ [t0, t1]`:

- Grid: `t_i = t0 + i / rate`, computed as `t0 + i * (1.0 / rate)` in double and stored as
  `t_video_s`; loop bound derived once from `floor((t1−t0) * rate)` to avoid cumulative drift.
  Endpoints: first sample at `t0`, last at the largest `t_i ≤ t1` (inclusive start, inclusive of
  any endpoint exactly on the grid).
- IMU: linear interpolation between consecutive valid samples bracketing `t`; if bracketing gap
  `> maxImuGapMs` (default 250 ms) or a side is missing → empty fields. Duplicate timestamps:
  the later value is used for right-side interpolation, the earlier for left-side (deterministic;
  documented; no averaging).
- GPS forward-fill: latest fix with `timestamp_ns ≤ grid_ns`; `gps_age_s = (grid_ns − fix_ns)/1e9`;
  if age `> maxGpsAgeS` (default 5 s) → GPS columns empty **except** `gps_age_s` which still
  reports the real age. Never future fixes; no coordinate interpolation.
- Memory: input streamed in timestamp order (already sorted by construction); interpolators keep
  only the current bracketing pair.

## 10. Crash recovery (FR-055)

At startup `SessionRepository.scan()` finds session dirs lacking the completion marker and
reports them as `incomplete`. `RecoveryService` validates partial CSVs (header + parseable rows,
monotonic timestamps), truncates corrupt tails, renames `.part` files, and marks the session
`"status": "recovered"` in `metadata.json` with counts of retained rows and the documented
loss window (last unflushed buffer, ≤ ~1 s of events). Recovered sessions are listed distinctly
in the UI and are never claimed complete.

## 11. Error handling & diagnostics

`AppFailure` hierarchy (message, cause, context map). Services catch at their boundaries, log
via `core/logging`, append a `DiagnosticEvent` to `diagnostics.json`, and rethrow or surface to
UI through state. No silent catches.

## 12. Testing strategy (NFR-004, FR-090..093)

- **Unit** (`test/unit/`): time math, CSV writer, resampler (gaps/duplicates/missing sensors/
  boundaries/empty input), GPS forward-fill + staleness, state machine, metadata serialization,
  session recovery, export zip contents/failures. Platform interactions are behind interfaces
  (`SensorSource`, `LocationSource`, `VideoRecorder`, `Clock`) with deterministic fakes.
- **Widget** (`test/widget/`): screens with faked service providers.
- **Integration** (`test/integration/`): full pipeline on device/emulator; unverified where no
  hardware is attached (recorded blocker).
- **Native** (`android/app/src/test/`): JVM unit tests for the batching queue and timestamp
  handling in Kotlin.

## 13. Design decisions & trade-offs

1. **Dart persistence over native persistence** — testability and single schema implementation
   vs. one extra copy; acceptable at ≤400 events/s.
2. **Batched EventChannel (100 ms) vs. per-event channel** — lower overhead and jitter; adds
   ≤100 ms transport latency which does not affect recorded timestamps (already stamped
   natively).
3. **`camera` plugin vs. hand-rolled CameraX** — plugin is maintained and CameraX-backed;
   cost: `video_start_ns` is a completion-event reference, not a frame exposure time (§6). If
   frame-exact sync is later required, replace `VideoRecorder` impl with native CameraX
   `Recording` callbacks (interface already isolates this).
4. **Riverpod only** — avoids mixed state approaches (NFR-007).
5. **Foreground service always on during recording** — battery/notification cost, but required
   for reliable long recordings on modern Android.
6. **Forward-fill (not interpolation) for GPS** — speed/position interpolation would fabricate
   measurements; stale markers keep honesty (FR-033, FR-062).
