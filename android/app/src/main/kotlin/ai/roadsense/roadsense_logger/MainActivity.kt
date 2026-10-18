package ai.roadsense.roadsense_logger

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import ai.roadsense.roadsense_logger.location.LocationCollector
import ai.roadsense.roadsense_logger.recording.RecordingForegroundService
import ai.roadsense.roadsense_logger.sensors.SensorCollector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Native integration entry point (see `specs/architecture.md` §2).
 *
 * Channels:
 * - MethodChannel `roadsense/native`  — control API (sensors, clock, FGS, permissions)
 * - EventChannel  `roadsense/sensors` — batched IMU events with original timestamps
 */
class MainActivity : FlutterActivity() {

    private var sensorCollector: SensorCollector? = null
    private var sensorSink: EventChannel.EventSink? = null
    private var locationCollector: LocationCollector? = null
    private var gpsSink: EventChannel.EventSink? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_SENSORS,
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    sensorSink = events
                }

                override fun onCancel(arguments: Any?) {
                    sensorSink = null
                }
            },
        )

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_GPS,
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    gpsSink = events
                }

                override fun onCancel(arguments: Any?) {
                    gpsSink = null
                }
            },
        )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NATIVE,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startSensors" -> startSensors(
                    call.argument<Int>("accPeriodUs") ?: 0,
                    call.argument<Int>("gyroPeriodUs") ?: 0,
                    result,
                )
                "stopSensors" -> {
                    sensorCollector?.stop()
                    result.success(null)
                }
                "getSensorInfo" ->
                    result.success(sensorCollector?.sensorInfo() ?: emptyList<Any>())
                "getClockMapping" -> result.success(
                    mapOf(
                        "elapsed_ns" to SensorCollector.elapsedRealtimeNs(),
                        "unix_ms" to System.currentTimeMillis(),
                    ),
                )
                "getElapsedNs" -> result.success(SensorCollector.elapsedRealtimeNs())
                "startGps" -> startGps(
                    call.argument<Int>("intervalMs") ?: 1000,
                    result,
                )
                "stopGps" -> {
                    locationCollector?.stop()
                    result.success(null)
                }
                "startForeground" -> {
                    RecordingForegroundService.start(
                        this,
                        call.argument<Boolean>("audio") ?: false,
                    )
                    result.success(null)
                }
                "stopForeground" -> {
                    RecordingForegroundService.stop(this)
                    result.success(null)
                }
                "checkPermissions" -> result.success(
                    permissionStatus(call.argument<List<String>>("permissions") ?: emptyList()),
                )
                "requestPermissions" -> requestPermissions(
                    call.argument<List<String>>("permissions") ?: emptyList(),
                    result,
                )
                else -> result.notImplemented()
            }
        }
    }

    private fun startGps(intervalMs: Int, result: MethodChannel.Result) {
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            result.error(
                "NO_LOCATION_PERMISSION",
                "Fine location permission is required for GPS collection",
                null,
            )
            return
        }
        val collector = locationCollector ?: LocationCollector(
            applicationContext,
            onFix = { event ->
                runOnUiThread { gpsSink?.success(event) }
            },
        ).also { locationCollector = it }
        collector.start(intervalMs.toLong())
        result.success(null)
    }

    private fun startSensors(
        accPeriodUs: Int,
        gyroPeriodUs: Int,
        result: MethodChannel.Result,
    ) {
        val collector = sensorCollector ?: SensorCollector(
            applicationContext,
            onBatch = { sensor, events ->
                runOnUiThread {
                    sensorSink?.success(mapOf("sensor" to sensor, "events" to events))
                }
            },
            onQueueOverflow = { droppedTotal ->
                runOnUiThread {
                    sensorSink?.success(
                        mapOf(
                            "sensor" to "OVERFLOW",
                            "events" to emptyList<List<Any>>(),
                            "dropped_total" to droppedTotal,
                        ),
                    )
                }
            },
        ).also { sensorCollector = it }

        if (!collector.accelerometerAvailable) {
            result.error(
                "NO_ACCELEROMETER",
                "No accelerometer available on this device",
                null,
            )
            return
        }
        collector.start(accPeriodUs, gyroPeriodUs)
        result.success(
            mapOf(
                "accelerometer_available" to collector.accelerometerAvailable,
                "gyroscope_available" to collector.gyroscopeAvailable,
            ),
        )
    }

    private fun permissionNamesToManifest(names: List<String>): List<String> =
        names.mapNotNull { name ->
            when (name) {
                "camera" -> Manifest.permission.CAMERA
                "fineLocation" -> Manifest.permission.ACCESS_FINE_LOCATION
                "coarseLocation" -> Manifest.permission.ACCESS_COARSE_LOCATION
                "recordAudio" -> Manifest.permission.RECORD_AUDIO
                "notifications" ->
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        Manifest.permission.POST_NOTIFICATIONS
                    } else {
                        null
                    }
                else -> null
            }
        }

    private fun permissionStatus(names: List<String>): Map<String, Boolean> =
        names.associateWith { name ->
            val manifest = permissionNamesToManifest(listOf(name)).firstOrNull()
            if (manifest == null) {
                true
            } else {
                checkSelfPermission(manifest) == PackageManager.PERMISSION_GRANTED
            }
        }

    private fun requestPermissions(names: List<String>, result: MethodChannel.Result) {
        val needed = permissionNamesToManifest(names).filter {
            checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }
        if (needed.isEmpty()) {
            result.success(permissionStatus(names))
            return
        }
        val stale = pendingPermissionResult
        pendingPermissionResult = result
        stale?.error("REQUEST_SUPERSEDED", "A newer permission request replaced this one", null)
        requestPermissions(needed.toTypedArray(), PERMISSION_REQUEST_CODE)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERMISSION_REQUEST_CODE) return
        val pending = pendingPermissionResult ?: return
        pendingPermissionResult = null
        val requested = permissions.map { manifest ->
            when (manifest) {
                Manifest.permission.CAMERA -> "camera"
                Manifest.permission.ACCESS_FINE_LOCATION -> "fineLocation"
                Manifest.permission.ACCESS_COARSE_LOCATION -> "coarseLocation"
                Manifest.permission.RECORD_AUDIO -> "recordAudio"
                Manifest.permission.POST_NOTIFICATIONS -> "notifications"
                else -> manifest
            }
        }
        pending.success(permissionStatus(requested))
    }

    companion object {
        private const val CHANNEL_NATIVE = "roadsense/native"
        private const val CHANNEL_SENSORS = "roadsense/sensors"
        private const val CHANNEL_GPS = "roadsense/gps"
        private const val PERMISSION_REQUEST_CODE = 4311
    }
}
