package com.alieninnovations.alien_reader_app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val permissionRequestCode = 4201
    private var pendingPermissionResult: MethodChannel.Result? = null

    // Kept registered for the whole setup: unregistering it makes Android
    // disconnect from the reader's hotspot.
    private var hotspotCallback: ConnectivityManager.NetworkCallback? = null

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
                    "requestWifiPermission" -> requestWifiPermission(result)
                    "connectToHotspot" -> connectToHotspot(
                        call.argument<String>("ssid") ?: "",
                        call.argument<String>("passphrase"),
                        call.argument<Int>("timeoutMs") ?: 45000,
                        result,
                    )
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

    /** The runtime permission Android asks for before joining Wi-Fi for an app. */
    private fun wifiPermission(): String? = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ->
            Manifest.permission.NEARBY_WIFI_DEVICES
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ->
            Manifest.permission.ACCESS_FINE_LOCATION
        else -> null
    }

    /** Replies "granted", "denied" or "unsupported" (Android 9 and older). */
    private fun requestWifiPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.success("unsupported")
            return
        }
        val permission = wifiPermission()!!
        if (checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
            result.success("granted")
            return
        }
        if (pendingPermissionResult != null) {
            result.success("denied")
            return
        }
        pendingPermissionResult = result
        requestPermissions(arrayOf(permission), permissionRequestCode)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != permissionRequestCode) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermissionResult?.success(if (granted) "granted" else "denied")
        pendingPermissionResult = null
    }

    /**
     * Asks Android to join [ssid] for this app only. Android shows its own
     * "Connect to device?" dialog; the app never leaves the screen.
     *
     * Replies "connected" (traffic is now bound to that exact network),
     * "unavailable" (declined, not found, wrong password or timed out),
     * "unsupported" (Android 9 and older) or "failed".
     */
    private fun connectToHotspot(
        ssid: String,
        passphrase: String?,
        timeoutMs: Int,
        result: MethodChannel.Result,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.success("unsupported")
            return
        }
        releaseWifiBinding()
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val main = Handler(Looper.getMainLooper())
        var replied = false
        fun reply(value: String) = main.post {
            if (!replied) {
                replied = true
                result.success(value)
            }
        }

        try {
            val specifier = WifiNetworkSpecifier.Builder()
                .setSsid(ssid)
                .apply { if (!passphrase.isNullOrEmpty()) setWpa2Passphrase(passphrase) }
                .build()
            // No INTERNET (and so no VALIDATED) requirement: the hotspot has
            // no internet and must not be rejected or dropped for that.
            val request = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .setNetworkSpecifier(specifier)
                .build()
            val callback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    // Send every request from the app over this network, not
                    // over home Wi-Fi or mobile data.
                    cm.bindProcessToNetwork(network)
                    reply("connected")
                }

                override fun onUnavailable() {
                    hotspotCallback = null
                    reply("unavailable")
                }

                override fun onLost(network: Network) {
                    if (cm.boundNetworkForProcess == network) {
                        cm.bindProcessToNetwork(null)
                    }
                }
            }
            hotspotCallback = callback
            cm.requestNetwork(request, callback, timeoutMs)
        } catch (e: Exception) {
            hotspotCallback = null
            reply("failed")
        }
    }

    private fun releaseWifiBinding() {
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            cm.bindProcessToNetwork(null)
            hotspotCallback?.let { cm.unregisterNetworkCallback(it) }
        } catch (e: Exception) {
            // Nothing to release.
        } finally {
            hotspotCallback = null
        }
    }

    override fun onDestroy() {
        releaseWifiBinding()
        super.onDestroy()
    }
}
