package com.gamestudio100.arac_motoru;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraManager;
import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioRecord;
import android.media.AudioTrack;
import android.media.MediaRecorder;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.VibrationEffect;
import android.os.Vibrator;

/**
 * Alkışla / ıslıkla bul: mikrofonu cihazda dinleyen ön plan hizmeti.
 * Ses kaydedilmez ve hiçbir yere gönderilmez; yalnızca anlık düzey ve
 * spektrum hesaplanır. Algılama eşikleri Dart'taki SoundFinderDetector
 * (lib/src/tools/sound_finder.dart) ile aynıdır.
 */
public class FinderService extends Service {
    static final String ACTION_STOP_ALARM = "com.gamestudio100.arac_motoru.FINDER_STOP_ALARM";
    static final String ACTION_STOP = "com.gamestudio100.arac_motoru.FINDER_STOP";
    private static final int RATE = 44100;
    private static final int FRAME = 1024;
    private static final int NOTE_ID = 7301;
    private static final int ALERT_ID = 7302;
    static volatile boolean running = false;

    private volatile boolean listen = false;
    private volatile boolean ringing = false;
    private Thread worker;
    private final Handler main = new Handler(Looper.getMainLooper());
    private AudioTrack track;
    private String torchId;
    private boolean torchOn = false;
    private int savedVolume = -1;

    private boolean claps = true, whistle = true, sound = true, flash = true, vibrate = true;
    private double sensitivity = 0.5;
    private String title = "", body = "", alertTitle = "", stopLabel = "", stopListen = "";

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent == null ? null : intent.getAction();
        if (ACTION_STOP_ALARM.equals(action)) {
            stopAlarm();
            return START_NOT_STICKY;
        }
        if (ACTION_STOP.equals(action)) {
            stopSelf();
            return START_NOT_STICKY;
        }
        if (intent != null) {
            claps = intent.getBooleanExtra("claps", true);
            whistle = intent.getBooleanExtra("whistle", true);
            sensitivity = intent.getDoubleExtra("sensitivity", 0.5);
            sound = intent.getBooleanExtra("sound", true);
            flash = intent.getBooleanExtra("flash", true);
            vibrate = intent.getBooleanExtra("vibrate", true);
            title = str(intent.getStringExtra("title"));
            body = str(intent.getStringExtra("body"));
            alertTitle = str(intent.getStringExtra("alertTitle"));
            stopLabel = str(intent.getStringExtra("stopLabel"));
            stopListen = str(intent.getStringExtra("stopListen"));
        }
        channels();
        Notification n = note(false);
        try {
            if (Build.VERSION.SDK_INT >= 30) {
                startForeground(NOTE_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE);
            } else {
                startForeground(NOTE_ID, n);
            }
        } catch (Exception e) {
            stopSelf();
            return START_NOT_STICKY;
        }
        startListening();
        running = true;
        return START_NOT_STICKY;
    }

    private static String str(String s) {
        return s == null ? "" : s;
    }

    private void channels() {
        if (Build.VERSION.SDK_INT < 26) return;
        NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm == null) return;
        NotificationChannel c = new NotificationChannel("finder", title, NotificationManager.IMPORTANCE_LOW);
        c.setShowBadge(false);
        nm.createNotificationChannel(c);
        NotificationChannel a = new NotificationChannel("finder_alert", alertTitle, NotificationManager.IMPORTANCE_HIGH);
        a.setSound(null, null);
        nm.createNotificationChannel(a);
    }

    private PendingIntent self(String action, int code) {
        Intent i = new Intent(this, FinderService.class).setAction(action);
        int f = PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0);
        return PendingIntent.getService(this, code, i, f);
    }

    private PendingIntent openApp() {
        Intent launch = getPackageManager().getLaunchIntentForPackage(getPackageName());
        if (launch == null) return null;
        int f = PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0);
        return PendingIntent.getActivity(this, 3, launch, f);
    }

    @SuppressWarnings("deprecation")
    private Notification note(boolean alert) {
        Notification.Builder b = Build.VERSION.SDK_INT >= 26
                ? new Notification.Builder(this, alert ? "finder_alert" : "finder")
                : new Notification.Builder(this);
        b.setSmallIcon(android.R.drawable.ic_lock_silent_mode_off)
                .setContentTitle(alert ? alertTitle : title)
                .setContentText(alert ? stopLabel : body)
                .setOngoing(!alert)
                .setAutoCancel(alert)
                .setContentIntent(alert ? self(ACTION_STOP_ALARM, 1) : openApp());
        if (alert) {
            b.addAction(new Notification.Action.Builder(android.R.drawable.ic_menu_close_clear_cancel, stopLabel, self(ACTION_STOP_ALARM, 1)).build());
            if (Build.VERSION.SDK_INT < 26) b.setPriority(Notification.PRIORITY_HIGH);
            b.setCategory(Notification.CATEGORY_ALARM);
        } else {
            b.addAction(new Notification.Action.Builder(android.R.drawable.ic_menu_close_clear_cancel, stopListen, self(ACTION_STOP, 2)).build());
        }
        return b.build();
    }

    // ------------------------------------------------------------ dinleme

    private void startListening() {
        if (worker != null) return;
        listen = true;
        worker = new Thread(this::loop, "finder");
        worker.start();
    }

    private void loop() {
        int min = AudioRecord.getMinBufferSize(RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT);
        AudioRecord rec;
        try {
            rec = new AudioRecord(MediaRecorder.AudioSource.MIC, RATE, AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT, Math.max(min, FRAME * 8));
            if (rec.getState() != AudioRecord.STATE_INITIALIZED) {
                rec.release();
                main.post(this::stopSelf);
                return;
            }
            rec.startRecording();
        } catch (SecurityException | IllegalStateException | IllegalArgumentException e) {
            main.post(this::stopSelf);
            return;
        }
        Detector det = new Detector(RATE, sensitivity, claps, whistle);
        short[] buf = new short[FRAME];
        double[] f = new double[FRAME];
        while (listen) {
            int n = 0;
            while (n < FRAME && listen) {
                int r = rec.read(buf, n, FRAME - n);
                if (r <= 0) break;
                n += r;
            }
            if (n < FRAME) continue;
            if (ringing) continue;
            for (int i = 0; i < FRAME; i++) f[i] = buf[i] / 32768.0;
            if (det.process(f)) {
                det.reset();
                main.post(this::alarm);
            }
        }
        try {
            rec.stop();
        } catch (IllegalStateException ignored) {
        }
        rec.release();
    }

    // -------------------------------------------------------------- alarm

    private void alarm() {
        if (ringing) return;
        ringing = true;
        NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm != null) {
            try {
                nm.notify(ALERT_ID, note(true));
            } catch (SecurityException ignored) {
            }
        }
        if (sound) playSiren();
        if (vibrate) vibrate();
        if (flash) blink(0);
        main.postDelayed(this::stopAlarm, 30000);
    }

    private void playSiren() {
        try {
            AudioManager am = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
            if (am != null) {
                savedVolume = am.getStreamVolume(AudioManager.STREAM_ALARM);
                am.setStreamVolume(AudioManager.STREAM_ALARM, am.getStreamMaxVolume(AudioManager.STREAM_ALARM), 0);
            }
        } catch (SecurityException ignored) {
            savedVolume = -1;
        }
        int rate = 22050;
        int len = rate; // 1 sn: 1760/2350 Hz kare dalga, döngüde
        short[] pcm = new short[len];
        for (int i = 0; i < len; i++) {
            double t = (double) i / rate;
            double hz = ((int) (t / 0.12)) % 2 == 0 ? 1760 : 2350;
            pcm[i] = (short) (Math.sin(2 * Math.PI * hz * t) >= 0 ? 26000 : -26000);
        }
        try {
            AudioAttributes attrs = new AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build();
            AudioFormat fmt = new AudioFormat.Builder()
                    .setSampleRate(rate)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build();
            track = new AudioTrack(attrs, fmt, len * 2, AudioTrack.MODE_STATIC, AudioManager.AUDIO_SESSION_ID_GENERATE);
            track.write(pcm, 0, len);
            track.setLoopPoints(0, len, -1);
            track.play();
        } catch (Exception e) {
            track = null;
        }
    }

    @SuppressWarnings("deprecation")
    private void vibrate() {
        Vibrator v = (Vibrator) getSystemService(Context.VIBRATOR_SERVICE);
        if (v == null || !v.hasVibrator()) return;
        long[] pattern = {0, 600, 300};
        if (Build.VERSION.SDK_INT >= 26) {
            v.vibrate(VibrationEffect.createWaveform(pattern, 0));
        } else {
            v.vibrate(pattern, 0);
        }
    }

    private void blink(int step) {
        if (!ringing) {
            torch(false);
            return;
        }
        torch(step % 2 == 0);
        main.postDelayed(() -> blink(step + 1), 180);
    }

    private void torch(boolean on) {
        if (Build.VERSION.SDK_INT < 23) return;
        try {
            CameraManager cm = (CameraManager) getSystemService(Context.CAMERA_SERVICE);
            if (cm == null) return;
            if (torchId == null) {
                for (String id : cm.getCameraIdList()) {
                    Boolean has = cm.getCameraCharacteristics(id).get(CameraCharacteristics.FLASH_INFO_AVAILABLE);
                    if (has != null && has) {
                        torchId = id;
                        break;
                    }
                }
            }
            if (torchId != null && torchOn != on) {
                cm.setTorchMode(torchId, on);
                torchOn = on;
            }
        } catch (Exception ignored) {
        }
    }

    private void stopAlarm() {
        main.removeCallbacksAndMessages(null);
        ringing = false;
        torch(false);
        if (track != null) {
            try {
                track.stop();
            } catch (IllegalStateException ignored) {
            }
            track.release();
            track = null;
        }
        if (savedVolume >= 0) {
            try {
                AudioManager am = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
                if (am != null) am.setStreamVolume(AudioManager.STREAM_ALARM, savedVolume, 0);
            } catch (SecurityException ignored) {
            }
            savedVolume = -1;
        }
        Vibrator v = (Vibrator) getSystemService(Context.VIBRATOR_SERVICE);
        if (v != null) v.cancel();
        NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm != null) nm.cancel(ALERT_ID);
    }

    @Override
    public void onDestroy() {
        listen = false;
        running = false;
        stopAlarm();
        if (worker != null) {
            worker.interrupt();
            worker = null;
        }
        super.onDestroy();
    }

    // ------------------------------------------------------- algılayıcı

    /** SoundFinderDetector'ın (Dart) Java karşılığı. */
    static final class Detector {
        private final int rate;
        private final double s;
        private final boolean claps, whistle;
        private final double[] re = new double[FRAME], im = new double[FRAME], win = new double[FRAME];
        private final double[] cos = new double[FRAME / 2], sin = new double[FRAME / 2];
        private final int[] rev = new int[FRAME];
        private int frameNo = 0, onsetAt = -100000, cooldownUntil = 0, tonal = 0, miss = 0;
        private double floor = 0.01, prev = 0, peak = 0, flat = 0, lastHz = 0;
        private boolean pending = false;
        private final java.util.ArrayList<Integer> clapFrames = new java.util.ArrayList<>();

        Detector(int rate, double sensitivity, boolean claps, boolean whistle) {
            this.rate = rate;
            this.s = Math.max(0, Math.min(1, sensitivity));
            this.claps = claps;
            this.whistle = whistle;
            for (int i = 0; i < FRAME / 2; i++) {
                cos[i] = Math.cos(2 * Math.PI * i / FRAME);
                sin[i] = -Math.sin(2 * Math.PI * i / FRAME);
            }
            for (int i = 0; i < FRAME; i++) win[i] = 0.5 - 0.5 * Math.cos(2 * Math.PI * i / (FRAME - 1));
            int bits = 0;
            while ((1 << bits) < FRAME) bits++;
            for (int i = 0; i < FRAME; i++) {
                int r = 0;
                for (int b = 0; b < bits; b++) if (((i >> b) & 1) == 1) r |= 1 << (bits - 1 - b);
                rev[i] = r;
            }
        }

        private static double lerp(double a, double b, double t) {
            return a + (b - a) * t;
        }

        private int frames(double ms) {
            return (int) Math.round(ms * rate / 1000.0 / FRAME);
        }

        void reset() {
            pending = false;
            clapFrames.clear();
            tonal = 0;
            miss = 0;
            cooldownUntil = frameNo + frames(2500);
        }

        private double[] magnitudes(double[] x) {
            for (int i = 0; i < FRAME; i++) {
                re[rev[i]] = x[i] * win[i];
                im[rev[i]] = 0;
            }
            for (int size = 2; size <= FRAME; size <<= 1) {
                int half = size >> 1, step = FRAME / size;
                for (int start = 0; start < FRAME; start += size) {
                    for (int k = 0; k < half; k++) {
                        double c = cos[k * step], sn = sin[k * step];
                        int a = start + k, b = a + half;
                        double tr = re[b] * c - im[b] * sn, ti = re[b] * sn + im[b] * c;
                        re[b] = re[a] - tr;
                        im[b] = im[a] - ti;
                        re[a] += tr;
                        im[a] += ti;
                    }
                }
            }
            double[] out = new double[FRAME / 2];
            for (int i = 0; i < FRAME / 2; i++) out[i] = Math.sqrt(re[i] * re[i] + im[i] * im[i]);
            return out;
        }

        private double flatness(double[] mag) {
            int lo = Math.max(1, (int) Math.floor(300.0 * FRAME / rate));
            int hi = Math.min(mag.length - 1, (int) Math.ceil(8000.0 * FRAME / rate));
            double logSum = 0, sum = 0;
            for (int i = lo; i <= hi; i++) {
                double p = mag[i] * mag[i] + 1e-12;
                logSum += Math.log(p);
                sum += p;
            }
            int n = hi - lo + 1;
            return Math.exp(logSum / n) / (sum / n);
        }

        boolean process(double[] x) {
            frameNo++;
            double sum = 0;
            for (double v : x) sum += v * v;
            double rms = Math.sqrt(sum / FRAME);
            double[] mag = magnitudes(x);
            if (!pending) {
                floor = rms < floor * 3 ? floor * 0.97 + rms * 0.03 : floor * 0.999 + rms * 0.001;
                floor = Math.max(0.0005, Math.min(0.2, floor));
            }
            boolean hit = false;
            if (frameNo >= cooldownUntil) {
                if (claps) hit = clap(rms, mag);
                if (!hit && whistle) hit = whistle(rms, mag);
            }
            prev = rms;
            return hit;
        }

        private boolean clap(double rms, double[] mag) {
            double k = lerp(12, 4, s), absMin = lerp(0.15, 0.03, s);
            if (pending) {
                if (rms > peak) {
                    peak = rms;
                    flat = Math.max(flat, flatness(mag));
                }
                if (rms < peak * 0.35) {
                    pending = false;
                    if (flat < 0.2) return false;
                    clapFrames.add(onsetAt);
                    while (!clapFrames.isEmpty() && frameNo - clapFrames.get(0) > frames(1500)) clapFrames.remove(0);
                    int n = clapFrames.size();
                    if (n >= 2) {
                        int gap = clapFrames.get(n - 1) - clapFrames.get(n - 2);
                        return gap >= frames(120) && gap <= frames(900);
                    }
                } else if (frameNo - onsetAt > frames(250)) {
                    pending = false;
                    clapFrames.clear();
                }
                return false;
            }
            if (rms > absMin && rms > floor * k && rms > prev * 2.5 && frameNo - onsetAt > frames(100)) {
                pending = true;
                onsetAt = frameNo;
                peak = rms;
                flat = flatness(mag);
            }
            return false;
        }

        private boolean whistle(double rms, double[] mag) {
            int lo = (int) Math.floor(900.0 * FRAME / rate);
            int hi = Math.min(mag.length - 1, (int) Math.ceil(4000.0 * FRAME / rate));
            int pk = lo;
            double pm = 0;
            for (int i = lo; i <= hi; i++) {
                if (mag[i] > pm) {
                    pm = mag[i];
                    pk = i;
                }
            }
            double side = 0;
            int n = 0;
            for (int i = lo; i <= hi; i++) {
                if (Math.abs(i - pk) > 2) {
                    side += mag[i];
                    n++;
                }
            }
            double ratio = pm / Math.max(1e-12, side / Math.max(1, n));
            double hz = (double) pk * rate / FRAME;
            boolean isTonal = ratio > lerp(28, 10, s) && rms > floor * 2.5 && rms > lerp(0.02, 0.004, s);
            if (isTonal && (tonal == 0 || Math.abs(hz - lastHz) <= lastHz * 0.15)) {
                tonal++;
                miss = 0;
                lastHz = hz;
                return tonal >= frames(lerp(700, 350, s));
            } else if (tonal > 0) {
                miss++;
                if (miss > 2) {
                    tonal = 0;
                    miss = 0;
                }
            }
            return false;
        }
    }
}
