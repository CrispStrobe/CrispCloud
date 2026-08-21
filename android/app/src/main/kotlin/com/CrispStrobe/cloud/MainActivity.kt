package com.crispstrobe.cloud

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    private val safChannel = "com.crispstrobe.cloud/saf"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Storage Access Framework — folder / document pickers
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, safChannel)
        SAFHandler(this).register(channel)
    }
}
