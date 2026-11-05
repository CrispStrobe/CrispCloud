package ch.waio.pro_video_editor.src.features.audio.models

/**
 * Handle for cancelling an active audio extraction job.
 *
 * This functional interface encapsulates the cancellation logic,
 * allowing the caller to stop the extraction process and clean up resources.
 */
fun interface AudioExtractJobHandle {
    /**
     * Cancels the audio extraction job.
     *
     * When invoked, this should:
     * - Stop the ongoing extraction process
     * - Clean up temporary files
     * - Release resources
     */
    fun cancel()
}
