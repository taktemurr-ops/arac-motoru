package com.gamestudio100.arac_motoru;

import android.annotation.SuppressLint;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothManager;
import android.bluetooth.le.BluetoothLeScanner;
import android.bluetooth.le.ScanCallback;
import android.bluetooth.le.ScanResult;
import android.bluetooth.le.ScanSettings;
import android.content.ActivityNotFoundException;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.hardware.ConsumerIrManager;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * Flutter köprüsü:
 * arac_motoru/filter (göz koruma filtresi), arac_motoru/ir (kızılötesi
 * kumanda), arac_motoru/finder (alkışla/ıslıkla bul hizmeti),
 * arac_motoru/bt + arac_motoru/bt_scan (Bluetooth cihaz bulucu).
 */
public class AracMotoruPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
    private MethodChannel filter, ir, finder, bt;
    private EventChannel btScan;
    private Context context;
    private final Handler main = new Handler(Looper.getMainLooper());

    // Bluetooth taraması
    private EventChannel.EventSink sink;
    private ScanCallback leCallback;
    private BroadcastReceiver classicReceiver;

    @Override
    public void onAttachedToEngine(FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        filter = new MethodChannel(binding.getBinaryMessenger(), "arac_motoru/filter");
        filter.setMethodCallHandler(this);
        ir = new MethodChannel(binding.getBinaryMessenger(), "arac_motoru/ir");
        ir.setMethodCallHandler(this::onIr);
        finder = new MethodChannel(binding.getBinaryMessenger(), "arac_motoru/finder");
        finder.setMethodCallHandler(this::onFinder);
        bt = new MethodChannel(binding.getBinaryMessenger(), "arac_motoru/bt");
        bt.setMethodCallHandler(this::onBt);
        btScan = new EventChannel(binding.getBinaryMessenger(), "arac_motoru/bt_scan");
        btScan.setStreamHandler(new EventChannel.StreamHandler() {
            @Override
            public void onListen(Object arguments, EventChannel.EventSink events) {
                sink = events;
                startScan();
            }

            @Override
            public void onCancel(Object arguments) {
                stopScan();
                sink = null;
            }
        });
    }

    @Override
    public void onDetachedFromEngine(FlutterPluginBinding binding) {
        stopScan();
        filter.setMethodCallHandler(null);
        ir.setMethodCallHandler(null);
        finder.setMethodCallHandler(null);
        bt.setMethodCallHandler(null);
        btScan.setStreamHandler(null);
        filter = ir = finder = bt = null;
        btScan = null;
    }

    // ------------------------------------------------------ ekran filtresi

    @Override
    public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        try {
            switch (call.method) {
                case "canDraw":
                    result.success(Settings.canDrawOverlays(context));
                    return;
                case "requestPermission": {
                    Intent i = new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:" + context.getPackageName()));
                    i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                    try {
                        context.startActivity(i);
                        result.success(true);
                    } catch (ActivityNotFoundException | SecurityException e) {
                        result.success(false);
                    }
                    return;
                }
                case "start": {
                    if (!Settings.canDrawOverlays(context)) {
                        result.success(false);
                        return;
                    }
                    Number color = call.argument("color");
                    Number alpha = call.argument("alpha");
                    Intent i = new Intent(context, ScreenFilterService.class);
                    i.putExtra("color", color == null ? 0xFFFF8F00 : color.intValue());
                    i.putExtra("alpha", alpha == null ? 0.3f : alpha.floatValue());
                    context.startService(i);
                    result.success(true);
                    return;
                }
                case "stop":
                    ScreenFilterService.clear(context);
                    context.stopService(new Intent(context, ScreenFilterService.class));
                    result.success(true);
                    return;
                case "running":
                    result.success(ScreenFilterService.running);
                    return;
                default:
                    result.notImplemented();
            }
        } catch (Exception e) {
            result.error("filter", e.getMessage(), null);
        }
    }

    // ------------------------------------------------------ kızılötesi

    private void onIr(MethodCall call, MethodChannel.Result result) {
        try {
            ConsumerIrManager m = (ConsumerIrManager) context.getSystemService(Context.CONSUMER_IR_SERVICE);
            switch (call.method) {
                case "has":
                    result.success(m != null && m.hasIrEmitter());
                    return;
                case "transmit": {
                    if (m == null || !m.hasIrEmitter()) {
                        result.success(false);
                        return;
                    }
                    Number carrier = call.argument("carrier");
                    List<Number> pattern = call.argument("pattern");
                    if (carrier == null || pattern == null || pattern.isEmpty()) {
                        result.success(false);
                        return;
                    }
                    int[] p = new int[pattern.size()];
                    for (int i = 0; i < p.length; i++) p[i] = pattern.get(i).intValue();
                    m.transmit(carrier.intValue(), p);
                    result.success(true);
                    return;
                }
                default:
                    result.notImplemented();
            }
        } catch (Exception e) {
            result.success(false);
        }
    }

    // --------------------------------------------------- alkışla bul

    private void onFinder(MethodCall call, MethodChannel.Result result) {
        try {
            switch (call.method) {
                case "start": {
                    Intent i = new Intent(context, FinderService.class);
                    for (String k : new String[] {"claps", "whistle", "sound", "flash", "vibrate"}) {
                        Boolean b = call.argument(k);
                        i.putExtra(k, b == null || b);
                    }
                    Number s = call.argument("sensitivity");
                    i.putExtra("sensitivity", s == null ? 0.5 : s.doubleValue());
                    for (String k : new String[] {"title", "body", "alertTitle", "stopLabel", "stopListen"}) {
                        String v = call.argument(k);
                        i.putExtra(k, v == null ? "" : v);
                    }
                    if (Build.VERSION.SDK_INT >= 26) {
                        context.startForegroundService(i);
                    } else {
                        context.startService(i);
                    }
                    result.success(true);
                    return;
                }
                case "stop":
                    context.stopService(new Intent(context, FinderService.class));
                    result.success(true);
                    return;
                case "running":
                    result.success(FinderService.running);
                    return;
                default:
                    result.notImplemented();
            }
        } catch (Exception e) {
            result.success(false);
        }
    }

    // ------------------------------------------------------ Bluetooth

    private BluetoothAdapter adapter() {
        BluetoothManager bm = (BluetoothManager) context.getSystemService(Context.BLUETOOTH_SERVICE);
        return bm == null ? null : bm.getAdapter();
    }

    private void onBt(MethodCall call, MethodChannel.Result result) {
        try {
            switch (call.method) {
                case "state": {
                    BluetoothAdapter a = adapter();
                    if (a == null) {
                        result.success("unsupported");
                    } else {
                        result.success(a.isEnabled() ? "on" : "off");
                    }
                    return;
                }
                case "settings": {
                    Intent i = new Intent(Settings.ACTION_BLUETOOTH_SETTINGS);
                    i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                    try {
                        context.startActivity(i);
                        result.success(true);
                    } catch (ActivityNotFoundException e) {
                        result.success(false);
                    }
                    return;
                }
                default:
                    result.notImplemented();
            }
        } catch (SecurityException e) {
            result.success("unauthorized");
        } catch (Exception e) {
            result.success("unknown");
        }
    }

    @SuppressLint("MissingPermission")
    private void emit(BluetoothDevice d, int rssi, String type) {
        final EventChannel.EventSink s = sink;
        if (s == null || d == null) return;
        String name = null;
        boolean bonded = false;
        try {
            name = d.getName();
            bonded = d.getBondState() == BluetoothDevice.BOND_BONDED;
        } catch (SecurityException ignored) {
        }
        final Map<String, Object> m = new HashMap<>();
        m.put("id", d.getAddress());
        m.put("name", name == null ? "" : name);
        m.put("rssi", rssi);
        m.put("type", type);
        m.put("bonded", bonded);
        main.post(() -> {
            EventChannel.EventSink now = sink;
            if (now != null) now.success(m);
        });
    }

    @SuppressLint("MissingPermission")
    private void startScan() {
        BluetoothAdapter a = adapter();
        if (a == null) {
            fail("unsupported");
            return;
        }
        if (!a.isEnabled()) {
            fail("off");
            return;
        }
        try {
            BluetoothLeScanner le = a.getBluetoothLeScanner();
            if (le != null) {
                leCallback = new ScanCallback() {
                    @Override
                    public void onScanResult(int callbackType, ScanResult r) {
                        emit(r.getDevice(), r.getRssi(), "le");
                    }

                    @Override
                    public void onBatchScanResults(List<ScanResult> results) {
                        for (ScanResult r : results) emit(r.getDevice(), r.getRssi(), "le");
                    }
                };
                ScanSettings settings = new ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build();
                le.startScan(null, settings, leCallback);
            }
            classicReceiver = new BroadcastReceiver() {
                @Override
                @SuppressLint("MissingPermission")
                @SuppressWarnings("deprecation")
                public void onReceive(Context c, Intent intent) {
                    String action = intent.getAction();
                    if (BluetoothDevice.ACTION_FOUND.equals(action)) {
                        BluetoothDevice d = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE);
                        int rssi = intent.getShortExtra(BluetoothDevice.EXTRA_RSSI, Short.MIN_VALUE);
                        if (rssi != Short.MIN_VALUE) emit(d, rssi, "classic");
                    } else if (BluetoothAdapter.ACTION_DISCOVERY_FINISHED.equals(action)) {
                        // Klasik keşif ~12 sn sürer; dinlendiği sürece yeniden başlat.
                        if (sink != null) {
                            try {
                                BluetoothAdapter ad = adapter();
                                if (ad != null) ad.startDiscovery();
                            } catch (SecurityException ignored) {
                            }
                        }
                    }
                }
            };
            IntentFilter f = new IntentFilter();
            f.addAction(BluetoothDevice.ACTION_FOUND);
            f.addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED);
            if (Build.VERSION.SDK_INT >= 33) {
                context.registerReceiver(classicReceiver, f, Context.RECEIVER_EXPORTED);
            } else {
                context.registerReceiver(classicReceiver, f);
            }
            a.startDiscovery();
        } catch (SecurityException e) {
            fail("unauthorized");
        } catch (Exception e) {
            fail("error");
        }
    }

    private void fail(String code) {
        final EventChannel.EventSink s = sink;
        if (s != null) main.post(() -> s.error(code, code, null));
    }

    @SuppressLint("MissingPermission")
    private void stopScan() {
        BluetoothAdapter a = adapter();
        try {
            if (a != null && leCallback != null) {
                BluetoothLeScanner le = a.getBluetoothLeScanner();
                if (le != null) le.stopScan(leCallback);
            }
            if (a != null) a.cancelDiscovery();
        } catch (Exception ignored) {
        }
        leCallback = null;
        if (classicReceiver != null) {
            try {
                context.unregisterReceiver(classicReceiver);
            } catch (Exception ignored) {
            }
            classicReceiver = null;
        }
    }
}
