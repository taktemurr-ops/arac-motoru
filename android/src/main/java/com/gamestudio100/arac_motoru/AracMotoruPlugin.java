package com.gamestudio100.arac_motoru;

import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.provider.Settings;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** Flutter köprüsü: arac_motoru/filter (lib/src/platform/filter.dart). */
public class AracMotoruPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
    private MethodChannel channel;
    private Context context;

    @Override
    public void onAttachedToEngine(FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), "arac_motoru/filter");
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        channel = null;
    }

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
}
