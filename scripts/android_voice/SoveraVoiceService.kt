package com.sovera.sovera

import android.app.*
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.*

class SoveraVoiceService : Service() {
    companion object {
        var started: ((Boolean) -> Unit)? = null
        var action: ((String) -> Unit)? = null
        var running = false
    }
    private var wake: PowerManager.WakeLock? = null
    override fun onBind(intent: Intent?) = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val command = intent?.action
        if (command == "mute" || command == "leave") {
            action?.invoke(command)
            if (command == "leave") stopSelf()
            return START_NOT_STICKY
        }
        try {
            val manager = getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel("sovera_voice", "Live voice room", NotificationManager.IMPORTANCE_LOW))
            val open = packageManager.getLaunchIntentForPackage(packageName)!!.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            val tap = PendingIntent.getActivity(this, 0, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            fun button(name: String, code: Int) = PendingIntent.getService(this, code, Intent(this, SoveraVoiceService::class.java).setAction(name), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "sovera_voice") else Notification.Builder(this)
            val notification = builder.setSmallIcon(android.R.drawable.ic_btn_speak_now).setContentTitle("Sovera voice room")
                .setContentText("Room connected · Tap to open Sovera").setContentIntent(tap).setOngoing(true)
                .setCategory(Notification.CATEGORY_CALL).addAction(android.R.drawable.ic_lock_silent_mode, "Mute mic", button("mute", 1))
                .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Leave room", button("leave", 2)).build()
            if (Build.VERSION.SDK_INT >= 29) {
                var type = ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                if (intent?.getBooleanExtra("microphone", false) == true && Build.VERSION.SDK_INT >= 30) type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                startForeground(410, notification, type)
            } else startForeground(410, notification)
            if (wake == null) wake = (getSystemService(POWER_SERVICE) as PowerManager).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "sovera:voice").apply { acquire() }
            running = true
            started?.invoke(true); started = null
        } catch (_: Exception) { running = false; started?.invoke(false); started = null; stopSelf() }
        return START_NOT_STICKY
    }
    override fun onTaskRemoved(rootIntent: Intent?) { action?.invoke("leave"); stopSelf(); super.onTaskRemoved(rootIntent) }
    override fun onDestroy() { running = false; wake?.let { if (it.isHeld) it.release() }; wake = null; stopForeground(STOP_FOREGROUND_REMOVE); super.onDestroy() }
}
