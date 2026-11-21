package com.crispstrobe.cloud

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    private val safChannel = "com.crispstrobe.cloud/saf"

    // receive_sharing_intent reports VIEW ("Open with") and SEND (share) alike;
    // Dart asks which one it was (lib/services/external_open_service.dart).
    private val externalOpenChannel = "com.crispcloud/external_open"
    private var lastIntentAction: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        lastIntentAction = intent?.action
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        // Record before super, which hands the intent to the plugins.
        lastIntentAction = intent.action
        super.onNewIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Storage Access Framework — folder / document pickers
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, safChannel)
        SAFHandler(this).register(channel)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, externalOpenChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "lastIntentAction" -> result.success(lastIntentAction)
                    else -> result.notImplemented()
                }
            }
    }
}
