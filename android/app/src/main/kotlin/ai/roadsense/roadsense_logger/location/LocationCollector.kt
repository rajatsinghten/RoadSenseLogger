package ai.roadsense.roadsense_logger.location

import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority

/**
 * Native GPS collector (FR-030, FR-031).
 *
 * Forwards every provider fix with its original `Location.elapsedRealtimeNanos`.
 * Fixes that fail acceptance rules are reported separately and never written
 * as data. Values the provider did not report (`has*()` false) are emitted as
 * null.
 *
 * Source selection:
 * - Fused provider first when Google Play Services is available.
 * - Platform `LocationManager` when Play Services is missing, the fused
 *   request fails, or the fused provider delivers no fix within
 *   [FUSED_SILENCE_TIMEOUT_MS] (seen on OEM builds that throttle GMS).
 * - Once one source delivers a fix the other is removed, so fixes are never
 *   duplicated across sources.
 *
 * Human-readable state changes are reported through [onStatus] so the UI can
 * explain why no fix is available.
 */
class LocationCollector(
    private val context: Context,
    private val onFix: (Map<String, Any?>) -> Unit,
    private val onStatus: (code: String, message: String) -> Unit,
) {
    private val fused: FusedLocationProviderClient =
        LocationServices.getFusedLocationProviderClient(context)

    private val locationManager =
        context.getSystemService(Context.LOCATION_SERVICE) as LocationManager

    private val handler = Handler(Looper.getMainLooper())

    private var fusedActive = false
    private var platformActive = false
    private var fixReceived = false
    private var intervalMs = 1000L
    private var precise = true

    private val fusedCallback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            for (location in result.locations) {
                handleLocation(location, fromFused = true)
            }
        }
    }

    // Implements every callback explicitly: on API < 30 the platform calls
    // onStatusChanged/onProviderEnabled/onProviderDisabled, which are not
    // default methods there.
    private val platformListener = object : LocationListener {
        override fun onLocationChanged(location: Location) {
            handleLocation(location, fromFused = false)
        }

        @Deprecated("Required on API < 29")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit

        override fun onProviderEnabled(provider: String) = Unit

        override fun onProviderDisabled(provider: String) {
            onStatus("provider_disabled", "Location provider '$provider' was turned off")
        }
    }

    private val fusedSilenceWatchdog = Runnable {
        if (!fixReceived && fusedActive && !platformActive) {
            onStatus(
                "fused_silent",
                "No fix from fused provider after ${FUSED_SILENCE_TIMEOUT_MS / 1000} s; " +
                    "also listening to device GPS",
            )
            startPlatform()
        }
    }

    /** True when the user has location services switched on for the device. */
    fun isLocationServiceEnabled(): Boolean =
        locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
            locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)

    /**
     * Starts collection at [intervalMs]. [precise] is false when the user
     * granted only approximate location; fixes are then coarse.
     */
    @SuppressLint("MissingPermission") // Caller verifies location permission.
    fun start(intervalMs: Long, precise: Boolean) {
        stop()
        this.intervalMs = intervalMs
        this.precise = precise
        fixReceived = false
        if (!precise) {
            onStatus(
                "approximate_only",
                "Only approximate location granted; enable 'Precise location' for this app",
            )
        }

        val playServicesAvailable =
            GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context) ==
                ConnectionResult.SUCCESS
        if (!playServicesAvailable) {
            onStatus("no_play_services", "Google Play Services unavailable; using device GPS")
            startPlatform()
            return
        }

        val priority =
            if (precise) Priority.PRIORITY_HIGH_ACCURACY else Priority.PRIORITY_BALANCED_POWER_ACCURACY
        val request = LocationRequest.Builder(priority, intervalMs)
            .setMinUpdateIntervalMillis(intervalMs / 2)
            .setWaitForAccurateLocation(false)
            .build()
        fusedActive = true
        onStatus("waiting", "Waiting for first GPS fix")
        fused.requestLocationUpdates(request, fusedCallback, Looper.getMainLooper())
            .addOnFailureListener { error ->
                fusedActive = false
                onStatus("fused_failed", "Fused provider failed (${error.message}); using device GPS")
                startPlatform()
            }
        handler.postDelayed(fusedSilenceWatchdog, FUSED_SILENCE_TIMEOUT_MS)
    }

    fun stop() {
        handler.removeCallbacks(fusedSilenceWatchdog)
        stopFused()
        stopPlatform()
    }

    private fun stopFused() {
        if (fusedActive) {
            fused.removeLocationUpdates(fusedCallback)
            fusedActive = false
        }
    }

    private fun stopPlatform() {
        if (platformActive) {
            locationManager.removeUpdates(platformListener)
            platformActive = false
        }
    }

    @SuppressLint("MissingPermission") // Caller verifies location permission.
    private fun startPlatform() {
        if (platformActive) return
        val provider = when {
            precise && locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER) ->
                LocationManager.GPS_PROVIDER
            locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER) ->
                LocationManager.NETWORK_PROVIDER
            else -> null
        }
        if (provider == null) {
            onStatus(
                "no_platform_provider",
                "Device GPS is disabled; set Location mode to high accuracy",
            )
            return
        }
        locationManager.requestLocationUpdates(
            provider,
            intervalMs,
            0f,
            platformListener,
            Looper.getMainLooper(),
        )
        platformActive = true
    }

    private fun handleLocation(location: Location, fromFused: Boolean) {
        if (!fixReceived) {
            fixReceived = true
            handler.removeCallbacks(fusedSilenceWatchdog)
            onStatus("fix", if (fromFused) "Receiving fused fixes" else "Receiving device GPS fixes")
        }
        if (fromFused) stopPlatform() else stopFused()

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

    companion object {
        const val FUSED_SILENCE_TIMEOUT_MS = 15_000L
    }
}
