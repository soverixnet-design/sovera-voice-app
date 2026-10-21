package com.sovera.sovera

import android.Manifest
import android.content.pm.PackageManager
import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    override fun popSystemNavigator(): Boolean {
        if (SoveraVoiceService.running) { moveTaskToBack(true); return true }
        return super.popSystemNavigator()
    }
    private fun offerVoiceNotificationPermission() {
        if (Build.VERSION.SDK_INT < 33 || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED || getPreferences(0).getBoolean("voice_notification_asked", false)) return
        window.decorView.postDelayed({
            if (!isFinishing && hasWindowFocus()) {
                getPreferences(0).edit().putBoolean("voice_notification_asked", true).apply()
                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 801)
            }
        }, 700)
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sovera/voice_background")
        SoveraVoiceService.action = { command -> runOnUiThread { channel.invokeMethod(command, null) } }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    SoveraVoiceService.started = { ready -> runOnUiThread { result.success(ready); if (ready) offerVoiceNotificationPermission() } }
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
