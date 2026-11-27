package com.shivetay.dunhold.push

import android.Manifest
import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build

/**
 * Pokazuje lokalne powiadomienie o końcu budowy (#30, ADR 0012), gdy minie czas z
 * [DunholdPush.schedule_local]. Działa przy zamkniętej grze. Po restarcie telefonu zaplanowane
 * alarmy przepadają (bez uprawnienia RECEIVE_BOOT_COMPLETED), a gra planuje je znowu przy kolejnym
 * wyjściu do tła.
 */
class BuildAlarmReceiver : BroadcastReceiver() {

    companion object {
        const val TAG_BUILD = "build"
        private const val ACTION = "com.shivetay.dunhold.push.BUILD_DONE"
        private const val EXTRA_SLOT = "slot"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_BODY = "body"
        private const val REQUEST_BASE = 3100

        private fun intent(ctx: Context, slot: Int): Intent =
            Intent(ctx, BuildAlarmReceiver::class.java).setAction(ACTION).putExtra(EXTRA_SLOT, slot)

        /**
         * Nowy PendingIntent miejsca `slot` z treścią. FLAG_CANCEL_CURRENT zamiast UPDATE_CURRENT: niezmiennego
         * (IMMUTABLE) PendingIntentu nie aktualizujemy, tylko zastępujemy (review #410).
         */
        fun schedule(ctx: Context, slot: Int, title: String, body: String): PendingIntent =
            PendingIntent.getBroadcast(ctx, REQUEST_BASE + slot,
                intent(ctx, slot).putExtra(EXTRA_TITLE, title).putExtra(EXTRA_BODY, body),
                PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        /** Istniejący PendingIntent miejsca `slot` albo null (FLAG_NO_CREATE: kasowanie niczego nie tworzy). */
        fun existing(ctx: Context, slot: Int): PendingIntent? =
            PendingIntent.getBroadcast(ctx, REQUEST_BASE + slot, intent(ctx, slot),
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE)
    }

    override fun onReceive(ctx: Context, intent: Intent) {
        if (intent.action != ACTION) {
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ctx.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            return
        }
        val slot = intent.getIntExtra(EXTRA_SLOT, 0)
        val title = intent.getStringExtra(EXTRA_TITLE).orEmpty()
        val body = intent.getStringExtra(EXTRA_BODY).orEmpty()
        val launch = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
        val open = launch?.let {
            PendingIntent.getActivity(ctx, REQUEST_BASE + 10 + slot, it, PendingIntent.FLAG_IMMUTABLE)
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(ctx, DunholdPush.CHANNEL_BUILD)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(ctx)
        }
        builder.setSmallIcon(ctx.applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
        if (open != null) {
            builder.setContentIntent(open)
        }
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(TAG_BUILD, slot, builder.build())
    }
}
