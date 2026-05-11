package com.bigfoottrailers.bigfoot_mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val securityChannel = "com.bigfoottrailers.mobile_security"
	private val notificationChannelId = "bigfoot_alerts"

	override fun onCreate(savedInstanceState: Bundle?) {
		super.onCreate(savedInstanceState)
		createNotificationChannel()
	}

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, securityChannel)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"isDeviceRooted" -> result.success(isDeviceRooted())
					"enableSecureScreen" -> {
						runOnUiThread {
							window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
							result.success(null)
						}
					}
					"disableSecureScreen" -> {
						runOnUiThread {
							window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
							result.success(null)
						}
					}
					else -> result.notImplemented()
				}
			}
	}

	private fun createNotificationChannel() {
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

		val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
		if (manager.getNotificationChannel(notificationChannelId) != null) return

		val channel = NotificationChannel(
			notificationChannelId,
			"Bigfoot Alerts",
			NotificationManager.IMPORTANCE_HIGH,
		).apply {
			description = "Critical production, QC, and delivery alerts"
			enableVibration(true)
			val defaultSound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
			val audioAttributes = AudioAttributes.Builder()
				.setUsage(AudioAttributes.USAGE_NOTIFICATION)
				.setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
				.build()
			setSound(defaultSound, audioAttributes)
		}

		manager.createNotificationChannel(channel)
	}

	private fun isDeviceRooted(): Boolean {
		val testKeys = Build.TAGS?.contains("test-keys") == true
		val suPaths = listOf(
			"/system/app/Superuser.apk",
			"/sbin/su",
			"/system/bin/su",
			"/system/xbin/su",
			"/data/local/xbin/su",
			"/data/local/bin/su",
			"/system/sd/xbin/su",
			"/system/bin/failsafe/su",
			"/data/local/su",
		)
		val hasSuBinary = suPaths.any { path ->
			try {
				java.io.File(path).exists()
			} catch (_: Exception) {
				false
			}
		}

		val adbEnabled = try {
			Settings.Global.getInt(contentResolver, Settings.Global.ADB_ENABLED, 0) == 1
		} catch (_: Exception) {
			false
		}

		return testKeys || hasSuBinary || adbEnabled
	}
}
