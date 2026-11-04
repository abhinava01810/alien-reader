package com.alieninnovations.alien_reader_app

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "naadh/network")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "bindToWifi" -> result.success(bindToWifi())
                    "release" -> {
                        releaseWifiBinding()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // The reader's setup hotspot has no internet, so Android may send app
    // traffic over mobile data instead. Pinning the process to Wi-Fi keeps
    // requests to the reader on the hotspot. Released when setup ends.
    @Suppress("DEPRECATION")
    private fun bindToWifi(): Boolean {
        return try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val wifi = cm.allNetworks.firstOrNull {
                cm.getNetworkCapabilities(it)
                    ?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
            } ?: return false
            cm.bindProcessToNetwork(wifi)
        } catch (e: Exception) {
            false
        }
    }

    private fun releaseWifiBinding() {
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            cm.bindProcessToNetwork(null)
        } catch (e: Exception) {
            // Nothing to release.
        }
    }

    override fun onDestroy() {
        releaseWifiBinding()
        super.onDestroy()
    }
}
