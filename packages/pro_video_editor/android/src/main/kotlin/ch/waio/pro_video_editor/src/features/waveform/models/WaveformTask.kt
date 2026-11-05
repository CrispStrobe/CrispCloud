package ch.waio.pro_video_editor.src.features.waveform.models

/**
 * Handle for cancelling an active waveform generation job.
 *
 * @property cancel Function to invoke when cancellation is requested
 */
data class WaveformJobHandle(
    val cancel: () -> Unit
)

/**
 * Task wrapper for managing waveform generation jobs.
 *
 * Tracks the job state and provides thread-safe cancellation.
 */
data class WaveformTask(
    var job: WaveformJobHandle?,
    val result: io.flutter.plugin.common.MethodChannel.Result
) {
    @Volatile
    var isCanceled: Boolean = false
        private set

    /**
     * Marks this task as canceled and invokes the job's cancel handler.
     */
    fun cancel() {
        isCanceled = true
        job?.cancel?.invoke()
    }
}
