// android/app/src/main/kotlin/com/CrispStrobe/cloud_dart/TransferForegroundService.kt
//
// Minimal Android Service entry point declared in AndroidManifest so the OS
// recognises the foreground-service type "dataSync".
//
// flutter_local_notifications (>= 17.x) posts progress notifications that
// Android classifies as foreground service notifications on API 34+ when the
// channel importance is set correctly.  This service class exists solely so
// the manifest declaration (android:foregroundServiceType="dataSync") is valid
// and passes lint/aapt.  The notification lifecycle itself is controlled from
// the Flutter layer via ForegroundTransferService.

package com.crispstrobe.cloud

import android.app.Service
import android.content.Intent
import android.os.IBinder

class TransferForegroundService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // The Flutter plugin manages the notification; nothing to do here.
        return START_NOT_STICKY
    }
}
