package ai.roadsense.roadsense_logger.sensors

/**
 * Bounded queue between sensor callbacks and the batch sender.
 *
 * Sensor callbacks only enqueue (no disk I/O, no channel work). The batch
 * sender drains [drain] every ~100 ms. On overflow the oldest sample is
 * dropped and counted — never silently (FR-024).
 */
class SensorBatchQueue(private val capacity: Int = 8192) {

    data class Sample(
        val timestampNs: Long,
        val sensor: Int,
        val x: Float,
        val y: Float,
        val z: Float,
    )

    private val deque = ArrayDeque<Sample>()

    var overflowCount: Long = 0
        private set

    var droppedCount: Long = 0
        private set

    /** Enqueues a sample; returns false if the queue overflowed. */
    @Synchronized
    fun add(sample: Sample): Boolean {
        if (deque.size >= capacity) {
            deque.removeFirst()
            overflowCount++
            droppedCount++
            deque.addLast(sample)
            return false
        }
        deque.addLast(sample)
        return true
    }

    /** Removes and returns all queued samples in timestamp order of arrival. */
    @Synchronized
    fun drain(): List<Sample> {
        if (deque.isEmpty()) return emptyList()
        val out = ArrayList<Sample>(deque.size)
        out.addAll(deque)
        deque.clear()
        return out
    }

    @Synchronized
    fun size(): Int = deque.size

    companion object {
        const val SENSOR_ACC = 0
        const val SENSOR_GYRO = 1
    }
}
