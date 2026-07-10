package com.CrispStrobe.cloud_dart

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    private val safChannel = "com.CrispStrobe.cloud_dart/saf"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Storage Access Framework — folder / document pickers
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, safChannel)
        SAFHandler(this).register(channel)
    }
}
