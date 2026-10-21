package ai.roadsense.roadsense_logger.sensors

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock

/**
 * Native IMU collector (FR-020..026).
 *
 * - Runs on a dedicated [HandlerThread].
 * - Preserves the original [SensorEvent.timestamp] (elapsed-realtime ns);
 *   callback-arrival time is never used.
 * - Callbacks only enqueue into a [SensorBatchQueue]; batches are sent to the
 *   Flutter side every [batchIntervalMs] via the injected [onBatch] callback.
 */
class SensorCollector(
    context: Context,
    private val onBatch: (sensor: String, events: List<List<Any>>) -> Unit,
    private val onQueueOverflow: (droppedTotal: Long) -> Unit,
    private val batchIntervalMs: Long = 100,
) : SensorEventListener {

    private val sensorManager =
        context.getSystemService(Context.SENSOR_SERVICE) as SensorManager

    private val accelerometer: Sensor? =
        sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    private val gyroscope: Sensor? =
        sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)

    private val queue = SensorBatchQueue()
    private var thread: HandlerThread? = null
    private var handler: Handler? = null
    private var running = false

    @Volatile
    private var overflowPending = false

    val accelerometerAvailable: Boolean get() = accelerometer != null
    val gyroscopeAvailable: Boolean get() = gyroscope != null

    private val drainRunnable = object : Runnable {
        override fun run() {
            if (!running) return
            flush()
            handler?.postDelayed(this, batchIntervalMs)
        }
    }

    /**
     * Starts collection. [accPeriodUs]/[gyroPeriodUs] are *requested* nominal
     * sampling periods (0 = SENSOR_DELAY_FASTEST); achieved rates are measured
     * on the Dart side and reported separately (NFR-005).
     */
    @Synchronized
    fun start(accPeriodUs: Int, gyroPeriodUs: Int) {
        if (running) return
        val t = HandlerThread("RoadSense-IMU").also { it.start() }
        thread = t
        val h = Handler(t.looper)
        handler = h
        running = true

        accelerometer?.let {
            sensorManager.registerListener(this, it, accPeriodUs, h)
        }
        gyroscope?.let {
            sensorManager.registerListener(this, it, gyroPeriodUs, h)
        }
        h.post(drainRunnable)
    }

    @Synchronized
    fun stop() {
        if (!running) return
        running = false
        sensorManager.unregisterListener(this)
        handler?.removeCallbacks(drainRunnable)
        flush()
        thread?.quitSafely()
        thread = null
        handler = null
    }

    override fun onSensorChanged(event: SensorEvent) {
        val sensorId = when (event.sensor.type) {
            Sensor.TYPE_ACCELEROMETER -> SensorBatchQueue.SENSOR_ACC
            Sensor.TYPE_GYROSCOPE -> SensorBatchQueue.SENSOR_GYRO
            else -> return
        }
        val overflowed = queue.add(
            SensorBatchQueue.Sample(
                timestampNs = event.timestamp,
                sensor = sensorId,
                x = event.values[0],
                y = event.values[1],
                z = event.values[2],
            ),
        )
        // Overflow is reported from flush() at batch cadence; reporting per
        // dropped sample flooded the main thread and worsened the overflow.
        if (!overflowed) overflowPending = true
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    private fun flush() {
        if (overflowPending) {
            overflowPending = false
            onQueueOverflow(queue.droppedCount)
        }
        val drained = queue.drain()
        if (drained.isEmpty()) return
        val acc = ArrayList<List<Any>>()
        val gyro = ArrayList<List<Any>>()
        for (sample in drained) {
            // Long timestamp preserved exactly; values as Double.
            val row = listOf<Any>(
                sample.timestampNs,
                sample.x.toDouble(),
                sample.y.toDouble(),
                sample.z.toDouble(),
            )
            when (sample.sensor) {
                SensorBatchQueue.SENSOR_ACC -> acc.add(row)
                SensorBatchQueue.SENSOR_GYRO -> gyro.add(row)
            }
        }
        if (acc.isNotEmpty()) onBatch("ACC", acc)
        if (gyro.isNotEmpty()) onBatch("GYRO", gyro)
    }

    /** Hardware metadata for `metadata.json` (FR-026). */
    fun sensorInfo(): List<Map<String, Any?>> {
        fun info(kind: String, sensor: Sensor?): Map<String, Any?> = mapOf(
            "kind" to kind,
            "name" to (sensor?.name ?: ""),
            "vendor" to (sensor?.vendor ?: ""),
            "range" to (sensor?.maximumRange?.toDouble()),
            "resolution" to (sensor?.resolution?.toDouble()),
            "available" to (sensor != null),
        )
        return listOf(info("ACC", accelerometer), info("GYRO", gyroscope))
    }

    companion object {
        /** Monotonic clock source for the session clock mapping (FR-041). */
        fun elapsedRealtimeNs(): Long = SystemClock.elapsedRealtimeNanos()
    }
}
