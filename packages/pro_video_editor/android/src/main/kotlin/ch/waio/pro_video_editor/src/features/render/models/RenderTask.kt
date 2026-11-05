package ch.waio.pro_video_editor.src.features.render.models

import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Represents an active render task with cancellation support.
 */
class RenderTask(
    var job: RenderJobHandle?,
    private val result: MethodChannel.Result,
    val canceled: AtomicBoolean = AtomicBoolean(false),
) {
    private val resultConsumed = AtomicBoolean(false)

    /**
     * Sends a success result to Flutter. Can only be called once.
     */
    fun sendSuccess(payload: Any?) {
        if (resultConsumed.compareAndSet(false, true)) {
            result.success(payload)
        }
    }

    /**
     * Sends an error result to Flutter. Can only be called once.
     */
    fun sendError(code: String, message: String?, details: Any? = null) {
        if (resultConsumed.compareAndSet(false, true)) {
            result.error(code, message, details)
        }
    }
}
