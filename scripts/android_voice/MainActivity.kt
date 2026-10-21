package com.sovera.sovera

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sovera/voice_background")
        SoveraVoiceService.action = { command -> runOnUiThread { channel.invokeMethod(command, null) } }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    SoveraVoiceService.started = { ready -> runOnUiThread { result.success(ready) } }
                    try {
                        val intent = Intent(this, SoveraVoiceService::class.java).putExtra("microphone", call.argument<Boolean>("microphone") == true)
                        if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
                    } catch (_: Exception) { SoveraVoiceService.started = null; result.success(false) }
                }
                "stop" -> { stopService(Intent(this, SoveraVoiceService::class.java)); result.success(true) }
                else -> result.notImplemented()
            }
        }
    }
}
