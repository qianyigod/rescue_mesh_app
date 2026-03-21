package com.example.rescue_mesh_app

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), EventChannel.StreamHandler {
    private val broadcastChannelName = "rescue_mesh/advertiser"
    private val broadcastStateChannelName = "rescue_mesh/advertiser_state"

    private var advertiser: BluetoothLeAdvertiser? = null
    private var advertiseCallback: AdvertiseCallback? = null
    private var stateSink: EventChannel.EventSink? = null
    private var isBroadcasting = false
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            broadcastChannelName,
        ).setMethodCallHandler(::handleBroadcastCall)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            broadcastStateChannelName,
        ).setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        stateSink = events
        publishBroadcastState()
    }

    override fun onCancel(arguments: Any?) {
        stateSink = null
    }

    private fun handleBroadcastCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startSosBroadcast" -> startSosBroadcast(call, result)
            "stopSosBroadcast" -> {
                stopSosBroadcast()
                result.success(null)
            }
            "isBroadcasting" -> result.success(isBroadcasting)
            else -> result.notImplemented()
        }
    }

    private fun startSosBroadcast(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            result.error("unsupported", "BLE advertising requires Android 5.0+.", null)
            return
        }
        if (!hasBluetoothRuntimePermissions()) {
            result.error(
                "permission",
                "BLUETOOTH_ADVERTISE or BLUETOOTH_CONNECT permission is missing.",
                null,
            )
            return
        }

        val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val adapter: BluetoothAdapter = bluetoothManager.adapter
            ?: run {
                result.error("unavailable", "Bluetooth adapter is unavailable.", null)
                return
            }

        if (!adapter.isEnabled) {
            result.error("disabled", "Bluetooth is turned off.", null)
            return
        }
        if (!adapter.isMultipleAdvertisementSupported) {
            result.error("unsupported", "BLE advertising is not supported on this device.", null)
            return
        }

        val manufacturerId = extractManufacturerId(call)
        val payload = extractPayloadBytes(call)
        if (manufacturerId == null || payload == null || payload.size != 10) {
            result.error(
                "invalid_args",
                "manufacturerId is required and payload must be exactly 10 bytes.",
                null,
            )
            return
        }

        stopSosBroadcast()

        advertiser = adapter.bluetoothLeAdvertiser
        if (advertiser == null) {
            result.error("unavailable", "BluetoothLeAdvertiser is unavailable.", null)
            return
        }

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_POWER)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .setConnectable(false)
            .build()

        val advertiseData = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .setIncludeTxPowerLevel(false)
            .addManufacturerData(manufacturerId, payload)
            .build()

        pendingResult = result
        advertiseCallback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                isBroadcasting = true
                publishBroadcastState()
                pendingResult?.success(null)
                pendingResult = null
            }

            override fun onStartFailure(errorCode: Int) {
                isBroadcasting = false
                advertiseCallback = null
                publishBroadcastState()
                pendingResult?.error(
                    "broadcast_failed",
                    mapAdvertiseError(errorCode),
                    errorCode,
                )
                pendingResult = null
            }
        }

        advertiser?.startAdvertising(settings, advertiseData, advertiseCallback)
    }

    private fun stopSosBroadcast() {
        advertiser?.let { activeAdvertiser ->
            advertiseCallback?.let { callback ->
                activeAdvertiser.stopAdvertising(callback)
            }
        }
        advertiseCallback = null
        advertiser = null
        pendingResult = null
        isBroadcasting = false
        publishBroadcastState()
    }

    private fun publishBroadcastState() {
        runOnUiThread {
            stateSink?.success(isBroadcasting)
        }
    }

    private fun hasBluetoothRuntimePermissions(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return true
        }

        val advertiseGranted =
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.BLUETOOTH_ADVERTISE,
            ) == PackageManager.PERMISSION_GRANTED
        val connectGranted =
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.BLUETOOTH_CONNECT,
            ) == PackageManager.PERMISSION_GRANTED

        return advertiseGranted && connectGranted
    }

    private fun mapAdvertiseError(errorCode: Int): String {
        return when (errorCode) {
            AdvertiseCallback.ADVERTISE_FAILED_ALREADY_STARTED ->
                "Advertising already started."
            AdvertiseCallback.ADVERTISE_FAILED_DATA_TOO_LARGE ->
                "Advertising payload is too large."
            AdvertiseCallback.ADVERTISE_FAILED_FEATURE_UNSUPPORTED ->
                "BLE advertising is unsupported on this device."
            AdvertiseCallback.ADVERTISE_FAILED_INTERNAL_ERROR ->
                "Internal BLE advertising error."
            AdvertiseCallback.ADVERTISE_FAILED_TOO_MANY_ADVERTISERS ->
                "Too many active BLE advertisers."
            else -> "Unknown BLE advertising error."
        }
    }

    override fun onDestroy() {
        stopSosBroadcast()
        super.onDestroy()
    }

    private fun extractManufacturerId(call: MethodCall): Int? {
        val rawArguments = call.arguments as? Map<*, *>
        val rawManufacturerId = rawArguments?.get("manufacturerId")
        return when (rawManufacturerId) {
            is Int -> rawManufacturerId
            is Number -> rawManufacturerId.toInt()
            else -> null
        }
    }

    private fun extractPayloadBytes(call: MethodCall): ByteArray? {
        val rawArguments = call.arguments as? Map<*, *>
        val rawPayload = rawArguments?.get("payload")
        return when (rawPayload) {
            is ByteArray -> rawPayload
            is List<*> -> {
                val output = ByteArray(rawPayload.size)
                for (index in rawPayload.indices) {
                    val value = rawPayload[index] as? Number ?: return null
                    output[index] = value.toByte()
                }
                output
            }
            else -> null
        }
    }
}
