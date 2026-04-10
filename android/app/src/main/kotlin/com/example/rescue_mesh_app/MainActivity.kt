package com.example.rescue_mesh_app

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
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
    private val scannerChannelName = "rescue_mesh/coded_phy_scanner"

    private var advertiser: BluetoothLeAdvertiser? = null
    private var advertiseCallback: AdvertiseCallback? = null
    private var stateSink: EventChannel.EventSink? = null
    private var isBroadcasting = false
    private var pendingResult: MethodChannel.Result? = null
    
    // Coded PHY Scanner 相关
    private var scanner: BluetoothLeScanner? = null
    private var scanCallback: ScanCallback? = null
    private var scanResultsSink: EventChannel.EventSink? = null
    private var isScanning = false
    
    // 信号积分器：用于弱信号累积检测
    private val signalAccumulator = mutableMapOf<String, SignalSample>()
    private val signalAccumulatorLock = Any()
    private var accumulatorTimer: java.util.Timer? = null
    
    data class SignalSample(
        val address: String,
        var count: Int = 0,
        var maxRssi: Int = -100,
        var sumRssi: Long = 0,
        var lastSeen: Long = 0,
        var phy: Int = 0,
        var msd: Map<String, Any>? = null,
        var name: String = ""
    ) {
        val avgRssi: Int get() = if (count > 0) (sumRssi / count).toInt() else -100
    }

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
        
        // Coded PHY 扫描事件通道
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            scannerChannelName,
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                scanResultsSink = events
            }
            override fun onCancel(arguments: Any?) {
                scanResultsSink = null
            }
        })
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
            "startCodedPhyScan" -> startCodedPhyScan(result)
            "stopCodedPhyScan" -> {
                stopCodedPhyScan()
                result.success(null)
            }
            "isCodedPhyScanning" -> result.success(isScanning)
            "supportsCodedPhy" -> result.supportsCodedPhy()
            "setSosMode" -> {
                // SOS模式下使用密集广播
                val isSos = call.argument<Boolean>("isSos") ?: false
                sosMode = isSos
                result.success(null)
            }
            "getAccumulatedSignals" -> getAccumulatedSignals(result)
            else -> result.notImplemented()
        }
    }
    
    // SOS密集广播模式
    private var sosMode = false

    private fun startSosBroadcast(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            result.error("unsupported", "BLE advertising requires Android 5.0+.", null)
            return
        }
        if (!hasBluetoothAdvertisePermissions()) {
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
        val supportedPayloadSizes = setOf(8, 10, 14)
        if (manufacturerId == null || payload == null || payload.size !in supportedPayloadSizes) {
            result.error(
                "invalid_args",
                "manufacturerId is required and payload must be 8, 10, or 14 bytes.",
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

        // ===== 广播策略 =====
        // 这里使用 Android 传统 startAdvertising API
        // 此 API 不支持通过 AdvertiseSettings.Builder 切换 legacy / coded PHY
        // 因此这里统一使用兼容性最好的广播设置，配合紧凑 payload 提升有效传播距离
        // SOS 模式下使用更高频率广播
        
        val advertiseMode = if (sosMode) {
            AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY // SOS模式: 最快广播
        } else {
            AdvertiseSettings.ADVERTISE_MODE_BALANCED    // 正常模式: 平衡功耗和距离
        }
        
        val broadcastSettings = AdvertiseSettings.Builder()
            .setAdvertiseMode(advertiseMode)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .setConnectable(false)
            .build()

        val advertiseData = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .setIncludeTxPowerLevel(false)
            .addManufacturerData(manufacturerId, payload)
            .build()

        val scanResponse = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .setIncludeTxPowerLevel(false)
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

        // 启动广播
        try {
            advertiser?.startAdvertising(
                broadcastSettings,
                advertiseData,
                advertiseCallback
            )
        } catch (e: UnsupportedOperationException) {
            // 某些设备对当前广播参数不支持，回退到传统低延迟模式
            advertiser?.startAdvertising(
                AdvertiseSettings.Builder()
                    .setAdvertiseMode(advertiseMode)
                    .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                    .setConnectable(false)
                    .build(),
                advertiseData,
                advertiseCallback
            )
        }
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

    private fun publishScanResult(payload: Map<String, Any?>) {
        runOnUiThread {
            scanResultsSink?.success(payload)
        }
    }

    private fun publishScanError(code: String, message: String, details: Any?) {
        runOnUiThread {
            scanResultsSink?.error(code, message, details)
        }
    }

    private fun hasBluetoothAdvertisePermissions(): Boolean {
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

    private fun hasBluetoothScanPermissions(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return true
        }

        val scanGranted =
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.BLUETOOTH_SCAN,
            ) == PackageManager.PERMISSION_GRANTED
        val connectGranted =
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.BLUETOOTH_CONNECT,
            ) == PackageManager.PERMISSION_GRANTED

        return scanGranted && connectGranted
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

    // ==================== Coded PHY 扫描相关方法 ====================

    private fun MethodChannel.Result.supportsCodedPhy() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            success(false)
            return
        }
        val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val adapter = bluetoothManager.adapter
        // Bluetooth 5.0+ 才支持 Coded PHY
        val supportsCodedPhy = adapter?.isLeCodedPhySupported ?: false
        success(supportsCodedPhy)
    }

    private fun startCodedPhyScan(result: MethodChannel.Result) {
        if (!hasBluetoothScanPermissions()) {
            result.error("permission", "Missing Bluetooth permissions", null)
            return
        }

        val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val adapter = bluetoothManager.adapter
        if (adapter == null || !adapter.isEnabled) {
            result.error("disabled", "Bluetooth is not enabled", null)
            return
        }

        scanner = adapter.bluetoothLeScanner
        if (scanner == null) {
            result.error("unavailable", "BluetoothLeScanner is unavailable", null)
            return
        }

        if (isScanning) {
            result.success(null)
            return
        }

        // 优化 Coded PHY 扫描设置 - 针对远距离弱信号检测
        val scanSettingsBuilder = ScanSettings.Builder()
            // LOW_POWER 模式有更长的监听窗口，更容易捕获远距离弱信号
            // 虽然延迟稍高，但对SOS场景来说可靠性比实时性更重要
            .setScanMode(ScanSettings.SCAN_MODE_LOW_POWER)
            .setReportDelay(0) // 立即报告，不要批量延迟
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // 启用 PHY 选项：优先使用 Coded PHY，回退到 1M PHY
            scanSettingsBuilder.setPhy(BluetoothDevice.PHY_LE_CODED)
            scanSettingsBuilder.setLegacy(false)
            // 匹配模式：只报告包含我们关心的制造商数据的广播
            scanSettingsBuilder.setMatchMode(ScanSettings.MATCH_MODE_AGGRESSIVE)
            // 回调类型：所有匹配都报告，不漏掉任何弱信号
            scanSettingsBuilder.setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
            // 每个匹配的最大数量
            scanSettingsBuilder.setNumOfMatches(ScanSettings.MATCH_NUM_MAX_ADVERTISEMENT)
        }

        val scanSettings = try {
            scanSettingsBuilder.build()
        } catch (e: IllegalArgumentException) {
            // Coded PHY 不被支持，回退到传统扫描
            ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .setReportDelay(0)
                .build()
        }

        // 构建扫描过滤器（可选：只扫描特定制造商数据）
        val scanFilters = mutableListOf<ScanFilter>()

        scanCallback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, scanResult: ScanResult) {
                super.onScanResult(callbackType, scanResult)
                if (scanResultsSink != null) {
                    val deviceAddress = scanResult.device.address
                    val deviceName = scanResult.device.name ?: ""
                    val rssi = scanResult.rssi
                    val phy = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        scanResult.primaryPhy
                    } else {
                        0
                    }

                    // 提取 Manufacturer Specific Data
                    val msdBytes = scanResult.scanRecord?.manufacturerSpecificData?.let { msd ->
                        if (msd.size() > 0) {
                            val companyId = msd.keyAt(0)
                            val data = msd.valueAt(0)
                            mapOf(
                                "companyId" to companyId,
                                "data" to (data?.toList() ?: emptyList<Int>())
                            )
                        } else {
                            null
                        }
                    }

                    // ===== 信号积分器：累积同一设备的多次采样 =====
                    val now = System.currentTimeMillis()
                    val sample = signalAccumulator.getOrPut(deviceAddress) {
                        SignalSample(
                            address = deviceAddress,
                            name = deviceName,
                            phy = phy,
                            msd = msdBytes
                        )
                    }
                    sample.count++
                    sample.sumRssi += rssi
                    if (rssi > sample.maxRssi) sample.maxRssi = rssi
                    sample.lastSeen = now
                    sample.phy = phy // 使用最新检测到的 PHY
                    sample.msd = msdBytes
                    
                    // 立即发送原始结果（用于实时处理）
                    publishScanResult(
                        mapOf(
                            "address" to deviceAddress,
                            "name" to deviceName,
                            "rssi" to rssi,
                            "phy" to phy,
                            "msd" to msdBytes,
                            "timestampNanos" to System.nanoTime(),
                            "accumCount" to 1,
                            "accumMaxRssi" to rssi,
                            "accumAvgRssi" to rssi
                        )
                    )
                }
            }

            override fun onScanFailed(errorCode: Int) {
                super.onScanFailed(errorCode)
                isScanning = false
                publishScanError(
                    "scan_failed",
                    "Scan failed with code: $errorCode",
                    errorCode,
                )
            }

            override fun onBatchScanResults(results: MutableList<ScanResult>) {
                super.onBatchScanResults(results)
                for (result in results) {
                    onScanResult(ScanSettings.CALLBACK_TYPE_ALL_MATCHES, result)
                }
            }
        }
        
        // 启动信号积分器定时器 - 每3秒flush一次累积的信号
        startSignalAccumulator()

        try {
            scanner?.startScan(scanFilters, scanSettings, scanCallback)
            isScanning = true
            result.success(null)
        } catch (e: Exception) {
            result.error("scan_start_failed", e.message, null)
        }
    }

    private fun stopCodedPhyScan() {
        if (!isScanning) return

        try {
            scanner?.stopScan(scanCallback)
        } catch (e: Exception) {
            // 忽略停止扫描时的异常
        }

        // 停止信号积分器
        accumulatorTimer?.cancel()
        accumulatorTimer = null
        synchronized(signalAccumulatorLock) {
            signalAccumulator.clear()
        }

        scanCallback = null
        isScanning = false
    }
    
    // ===== 信号积分器定时器 =====
    private fun startSignalAccumulator() {
        accumulatorTimer?.cancel()
        synchronized(signalAccumulatorLock) {
            signalAccumulator.clear()
        }

        val timer = java.util.Timer("SignalAccumulator", true)
        timer.scheduleAtFixedRate(
            object : java.util.TimerTask() {
                override fun run() {
                    runOnUiThread {
                        flushAccumulatedSignals()
                    }
                }
            },
            3000,
            3000,
        )
        accumulatorTimer = timer
    }

    private fun flushAccumulatedSignals() {
        val now = System.currentTimeMillis()
        val snapshots = synchronized(signalAccumulatorLock) {
            signalAccumulator.mapValues { it.value.copy() }
        }
        val toRemove = mutableListOf<String>()
        
        for ((address, sample) in snapshots) {
            // 超过5秒没更新的样本，视为过期
            if (now - sample.lastSeen > 5000) {
                toRemove.add(address)
                continue
            }
            
            // 只报告出现≥2次的信号（过滤偶发噪声）
            if (sample.count >= 2 && sample.msd != null && scanResultsSink != null) {
                publishScanResult(
                    mapOf(
                        "address" to sample.address,
                        "name" to sample.name,
                        "rssi" to sample.avgRssi,
                        "maxRssi" to sample.maxRssi,
                        "phy" to sample.phy,
                        "msd" to sample.msd,
                        "timestampNanos" to System.nanoTime(),
                        "accumCount" to sample.count,
                        "accumMaxRssi" to sample.maxRssi,
                        "accumAvgRssi" to sample.avgRssi,
                        "isAccumulated" to true
                    )
                )
            }
        }
        
        // 清理过期样本
        synchronized(signalAccumulatorLock) {
            for (addr in toRemove) {
                signalAccumulator.remove(addr)
            }
        }
    }
    
    private fun getAccumulatedSignals(result: MethodChannel.Result) {
        val signals = synchronized(signalAccumulatorLock) {
            signalAccumulator.values.map { sample ->
                mapOf(
                    "address" to sample.address,
                    "name" to sample.name,
                    "count" to sample.count,
                    "avgRssi" to sample.avgRssi,
                    "maxRssi" to sample.maxRssi,
                    "phy" to sample.phy,
                    "msd" to sample.msd
                )
            }
        }
        result.success(signals)
    }

    override fun onDestroy() {
        stopSosBroadcast()
        stopCodedPhyScan()
        accumulatorTimer?.cancel()
        accumulatorTimer = null
        synchronized(signalAccumulatorLock) {
            signalAccumulator.clear()
        }
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
