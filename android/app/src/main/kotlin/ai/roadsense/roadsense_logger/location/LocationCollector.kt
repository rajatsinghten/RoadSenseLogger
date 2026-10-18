package ai.roadsense.roadsense_logger.location

import android.annotation.SuppressLint
import android.content.Context
import android.os.Looper
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority

/**
 * Native GPS collector (FR-030, FR-031).
 *
 * Uses `FusedLocationProviderClient` in high-accuracy mode and forwards every
 * provider fix with its original `Location.elapsedRealtimeNanos`. Fixes that
 * fail acceptance rules are reported separately and never written as data.
 * Values the provider did not report (`has*()` false) are emitted as null.
 */
class LocationCollector(
    context: Context,
    private val onFix: (Map<String, Any?>) -> Unit,
) {
    private val fused: FusedLocationProviderClient =
        LocationServices.getFusedLocationProviderClient(context)

    private val callback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            for (location in result.locations) {
                handleLocation(location)
            }
        }
    }

    @SuppressLint("MissingPermission") // Caller verifies fine location permission.
    fun start(intervalMs: Long) {
        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, intervalMs)
            .setMinUpdateIntervalMillis(intervalMs / 2)
            .setWaitForAccurateLocation(false)
            .build()
        fused.requestLocationUpdates(request, callback, Looper.getMainLooper())
    }

    fun stop() {
        fused.removeLocationUpdates(callback)
    }

    private fun handleLocation(location: android.location.Location) {
        val accepted =
            location.latitude in -90.0..90.0 &&
                location.longitude in -180.0..180.0 &&
                location.elapsedRealtimeNanos > 0

        val event = mutableMapOf<String, Any?>(
            "timestamp_ns" to location.elapsedRealtimeNanos,
            "unix_time_ms" to location.time,
            "latitude" to location.latitude,
            "longitude" to location.longitude,
            "altitude_m" to if (location.hasAltitude()) location.altitude else null,
            "speed_mps" to if (location.hasSpeed()) location.speed.toDouble() else null,
            "bearing_deg" to if (location.hasBearing()) location.bearing.toDouble() else null,
            "accuracy_m" to if (location.hasAccuracy()) location.accuracy.toDouble() else null,
            "accepted" to accepted,
        )
        if (!accepted) {
            event["reason"] = when {
                location.latitude !in -90.0..90.0 -> "latitude_out_of_range"
                location.longitude !in -180.0..180.0 -> "longitude_out_of_range"
                else -> "invalid_timestamp"
            }
        }
        onFix(event)
    }
}
