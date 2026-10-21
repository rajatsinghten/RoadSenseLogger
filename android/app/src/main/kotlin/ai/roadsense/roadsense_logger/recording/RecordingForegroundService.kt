package ai.roadsense.roadsense_logger.recording

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.Manifest
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.util.Log
import android.os.Build
import android.os.IBinder
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * Foreground service that keeps the process eligible while a session records
 * in the background (FR-006). Holds no data itself; sensor/GPS collection is
 * owned by the plugin-side collectors.
 */
class RecordingForegroundService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val audio = intent?.getBooleanExtra(EXTRA_AUDIO, false) ?: false
        startAsForeground(audio)
        return START_NOT_STICKY
    }

    private fun startAsForeground(audio: Boolean) {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Recording",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        val notification: Notification = Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.presence_video_online)
            .setContentTitle("RoadSense recording in progress")
            .setContentText("Video, IMU and GPS data are being collected.")
            .setOngoing(true)
            .build()

        // On Android 14+ declaring a type whose runtime permission is not
        // granted throws SecurityException and kills the process, so only
        // types backed by a granted permission are requested.
        // Location exists from API 29; camera and microphone from API 30.
        var type = 0
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            (granted(Manifest.permission.ACCESS_FINE_LOCATION) ||
                granted(Manifest.permission.ACCESS_COARSE_LOCATION))
        ) {
            type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            if (granted(Manifest.permission.CAMERA)) {
                type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
            }
            if (audio && granted(Manifest.permission.RECORD_AUDIO)) {
                type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            }
        }
        try {
            ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, type)
        } catch (error: RuntimeException) {
            Log.e(TAG, "startForeground failed; recording continues without FGS", error)
            stopSelf()
        }
    }

    private fun granted(permission: String): Boolean =
        ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED

    companion object {
        const val ACTION_START = "ai.roadsense.roadsense_logger.action.START_RECORDING"
        const val EXTRA_AUDIO = "audio"
        private const val CHANNEL_ID = "roadsense_recording"
        private const val NOTIFICATION_ID = 1001
        private const val TAG = "RoadSenseFgs"

        fun start(context: Context, audio: Boolean) {
            val intent = Intent(context, RecordingForegroundService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_AUDIO, audio)
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            // stopService never throws for a backgrounded app, unlike
            // startService (IllegalStateException on API 26+).
            context.stopService(Intent(context, RecordingForegroundService::class.java))
        }
    }
}
