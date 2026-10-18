package ai.roadsense.roadsense_logger.sensors

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SensorBatchQueueTest {

    private fun sample(ts: Long, sensor: Int = SensorBatchQueue.SENSOR_ACC) =
        SensorBatchQueue.Sample(ts, sensor, 1f, 2f, 3f)

    @Test
    fun `add and drain preserve arrival order and timestamps`() {
        val queue = SensorBatchQueue(capacity = 10)
        queue.add(sample(100))
        queue.add(sample(200, SensorBatchQueue.SENSOR_GYRO))
        queue.add(sample(300))

        val drained = queue.drain()
        assertEquals(3, drained.size)
        assertEquals(100L, drained[0].timestampNs)
        assertEquals(200L, drained[1].timestampNs)
        assertEquals(300L, drained[2].timestampNs)
        assertEquals(SensorBatchQueue.SENSOR_GYRO, drained[1].sensor)
    }

    @Test
    fun `drain empties the queue`() {
        val queue = SensorBatchQueue(capacity = 10)
        queue.add(sample(1))
        queue.drain()
        assertEquals(0, queue.size())
        assertTrue(queue.drain().isEmpty())
    }

    @Test
    fun `overflow drops oldest sample and counts drops`() {
        val queue = SensorBatchQueue(capacity = 3)
        assertTrue(queue.add(sample(1)))
        assertTrue(queue.add(sample(2)))
        assertTrue(queue.add(sample(3)))
        assertFalse(queue.add(sample(4)))

        assertEquals(1L, queue.overflowCount)
        assertEquals(1L, queue.droppedCount)
        assertEquals(3, queue.size())

        val drained = queue.drain()
        // Oldest (ts=1) was dropped; newest is retained.
        assertEquals(listOf(2L, 3L, 4L), drained.map { it.timestampNs })
    }

    @Test
    fun `sustained overflow keeps queue bounded and counts every drop`() {
        val queue = SensorBatchQueue(capacity = 5)
        for (ts in 1..20) {
            queue.add(sample(ts.toLong()))
        }
        assertEquals(5, queue.size())
        assertEquals(15L, queue.droppedCount)
        val drained = queue.drain()
        assertEquals(listOf(16L, 17L, 18L, 19L, 20L), drained.map { it.timestampNs })
    }
}
