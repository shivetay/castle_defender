package com.shivetay.dunhold.push

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.View
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

/**
 * Wtyczka Android v2 „DunholdPush” (#30, ADR 0012).
 *
 * - Firebase startuje z wpisów `dunhold.firebase.*` w manifeście, które dokłada eksport Godota
 *   z `config/google-services.json` (pliku nie ma w repo). Bez nich [is_configured] zwraca false
 *   i gra działa jak bez powiadomień.
 * - Push o ataku pokazuje sam Firebase (wiadomość z `notification`, kanał `attacks`), także przy
 *   zamkniętej grze, więc wtyczka nie ma własnego `FirebaseMessagingService`.
 * - Token urządzenia idzie do gry sygnałem `token_received` i nie trafia do logów.
 * - Koniec budowy to lokalne powiadomienie (AlarmManager + [BuildAlarmReceiver], kanał `build`), bez serwera.
 *   Gra planuje je przy wyjściu do tła i kasuje po powrocie, więc nie przychodzą w trakcie gry.
 */
class DunholdPush(godot: Godot) : GodotPlugin(godot) {

    companion object {
        private const val TAG = "DunholdPush"
        private const val META = "dunhold.firebase."
        private const val PERMISSION_REQUEST = 3030
        const val CHANNEL_ATTACKS = "attacks"
        const val CHANNEL_BUILD = "build"
        /** Najwięcej zaplanowanych powiadomień o budowie (kolejka: 1 w budowie + 3 czekające). */
        const val BUILD_SLOTS = 4
    }

    private var configured = false

    override fun getPluginName(): String = "DunholdPush"

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SignalInfo("token_received", String::class.java),
        SignalInfo("token_failed"),
        SignalInfo("permission_result", Boolean::class.javaObjectType),
    )

    override fun onMainCreate(activity: Activity): View? {
        configured = initFirebase(activity)
        createChannels(activity)
        return null
    }

    /** Czy Firebase ma konfigurację z eksportu (bez niej nie ma tokenu ani pusha). */
    @UsedByGodot
    fun is_configured(): Boolean = configured

    /** Czy gra może pokazywać powiadomienia (Android 13+: zgoda POST_NOTIFICATIONS). */
    @UsedByGodot
    fun has_permission(): Boolean {
        val ctx = activity ?: return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return true
        }
        return ctx.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
    }

    /** Systemowe pytanie o zgodę; wynik przychodzi sygnałem `permission_result`. */
    @UsedByGodot
    fun request_permission() {
        val act = activity
        if (act == null) {
            emitSignal("permission_result", false)
            return
        }
        if (has_permission()) {
            emitSignal("permission_result", true)
            return
        }
        act.runOnUiThread {
            act.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST)
        }
    }

    override fun onMainRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>?,
        grantResults: IntArray?,
    ) {
        if (requestCode != PERMISSION_REQUEST) {
            return
        }
        val granted = grantResults != null && grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        emitSignal("permission_result", granted)
    }

    /** Token FCM urządzenia; przychodzi sygnałem `token_received` albo `token_failed`. */
    @UsedByGodot
    fun request_token() {
        if (!configured) {
            emitSignal("token_failed")
            return
        }
        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            val token = if (task.isSuccessful) task.result else null
            if (token.isNullOrEmpty()) {
                Log.w(TAG, "token_failed")
                emitSignal("token_failed")
            } else {
                emitSignal("token_received", token)
            }
        }
    }

    /**
     * Lokalne powiadomienie o końcu budowy w miejscu `slot` (0..3) za `delaySeconds` sekund.
     * To samo miejsce zastępuje wcześniejsze. Nie wymaga Firebase ani serwera.
     */
    @UsedByGodot
    fun schedule_local(slot: Int, delaySeconds: Int, title: String, body: String) {
        val ctx = activity ?: return
        if (slot !in 0 until BUILD_SLOTS || delaySeconds < 1) {
            return
        }
        val at = System.currentTimeMillis() + delaySeconds * 1000L
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        // niedokładny alarm: bez uprawnienia SCHEDULE_EXACT_ALARM, Android może go przesunąć o kilka minut
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, BuildAlarmReceiver.schedule(ctx, slot, title, body))
    }

    /** Kasuje zaplanowane powiadomienia o budowie i te już widoczne (gracz wrócił do gry). */
    @UsedByGodot
    fun cancel_local() {
        val ctx = activity ?: return
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        for (slot in 0 until BUILD_SLOTS) {
            BuildAlarmReceiver.existing(ctx, slot)?.let {
                am.cancel(it)
                it.cancel()
            }
            nm.cancel(BuildAlarmReceiver.TAG_BUILD, slot)
        }
    }

    private fun initFirebase(ctx: Context): Boolean {
        if (FirebaseApp.getApps(ctx).isNotEmpty()) {
            return true
        }
        val meta: Bundle = try {
            ctx.packageManager.getApplicationInfo(ctx.packageName, PackageManager.GET_META_DATA).metaData
                ?: return false
        } catch (e: PackageManager.NameNotFoundException) {
            return false
        }
        val appId = meta.getString(META + "app_id").orEmpty()
        val apiKey = meta.getString(META + "api_key").orEmpty()
        val projectId = meta.getString(META + "project_id").orEmpty()
        val senderId = meta.getString(META + "sender_id").orEmpty()
        if (appId.isEmpty() || apiKey.isEmpty() || projectId.isEmpty() || senderId.isEmpty()) {
            Log.i(TAG, "not_configured")
            return false
        }
        val options = FirebaseOptions.Builder()
            .setApplicationId(appId)
            .setApiKey(apiKey)
            .setProjectId(projectId)
            .setGcmSenderId(senderId)
            .build()
        return try {
            FirebaseApp.initializeApp(ctx, options)
            true
        } catch (e: IllegalStateException) {
            Log.w(TAG, "init_failed")
            false
        }
    }

    private fun createChannels(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ATTACKS, "Ataki na zamek", NotificationManager.IMPORTANCE_HIGH)
        )
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_BUILD, "Koniec budowy", NotificationManager.IMPORTANCE_DEFAULT)
        )
    }
}
