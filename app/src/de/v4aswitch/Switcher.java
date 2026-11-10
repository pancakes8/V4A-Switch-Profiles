package de.v4aswitch;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.widget.Toast;

import java.io.IOException;

/**
 * Ruft per Root das Skript /data/adb/v4a-slot.sh des Magisk-Moduls auf.
 * Das Skript startet sich selbst im Hintergrund, su kehrt daher sofort zurueck.
 */
final class Switcher {

    static final String FX_MUSIC = "fx_music";
    static final String FX_VOICE = "fx_voice";
    static final String XHIFI_MUSIC = "xhifi_music";
    static final String XHIFI_VOICE = "xhifi_voice";

    private static final long SU_TIMEOUT_MS = 8000;

    private Switcher() {
    }

    /** Nur diese vier festen Namen werden je an die Shell uebergeben. */
    static boolean isSlot(String s) {
        return FX_MUSIC.equals(s) || FX_VOICE.equals(s)
                || XHIFI_MUSIC.equals(s) || XHIFI_VOICE.equals(s);
    }

    static String label(String slot) {
        if (FX_MUSIC.equals(slot)) return "FX Music";
        if (FX_VOICE.equals(slot)) return "FX Voice";
        if (XHIFI_MUSIC.equals(slot)) return "XHiFi Music";
        return "XHiFi Voice";
    }

    /**
     * @param pending Ergebnis von goAsync() (nur beim Aufruf aus einem Receiver), sonst null
     */
    static void trigger(Context ctx, final String slot, final BroadcastReceiver.PendingResult pending) {
        if (!isSlot(slot)) {
            if (pending != null) pending.finish();
            return;
        }

        Context appCtx = ctx.getApplicationContext();
        final Context app = appCtx != null ? appCtx : ctx;
        final Handler ui = new Handler(Looper.getMainLooper());

        toast(ui, app, label(slot) + " \u2026");

        new Thread(new Runnable() {
            @Override
            public void run() {
                String error;
                try {
                    error = runRoot(slot);
                } catch (Throwable t) {
                    error = "Fehler: " + t.getClass().getSimpleName();
                }
                if (error != null) toast(ui, app, error);
                if (pending != null) pending.finish();
            }
        }, "v4a-switch").start();
    }

    /** @return null bei Erfolg, sonst eine Fehlermeldung fuer die Anzeige */
    private static String runRoot(String slot) {
        Process p = null;
        try {
            String cmd = "sh /data/adb/v4a-slot.sh " + slot;
            p = Runtime.getRuntime().exec(new String[] {"su", "-mm", "-c", cmd});
            p.getOutputStream().close();

            long end = System.currentTimeMillis() + SU_TIMEOUT_MS;
            while (true) {
                try {
                    int rc = p.exitValue();
                    if (rc == 0) return null;
                    if (rc == 1) return "Root verweigert \u2013 in Magisk erlauben";
                    return "Skript fehlt oder Fehler (Code " + rc + ") \u2013 Modul installiert?";
                } catch (IllegalThreadStateException stillRunning) {
                    if (System.currentTimeMillis() > end) {
                        return "Keine Antwort von su (Magisk-Dialog offen?)";
                    }
                    Thread.sleep(100);
                }
            }
        } catch (IOException e) {
            return "su nicht gefunden \u2013 Root/Magisk fehlt";
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return null;
        } finally {
            if (p != null) p.destroy();
        }
    }

    private static void toast(Handler ui, final Context c, final String text) {
        ui.post(new Runnable() {
            @Override
            public void run() {
                Toast.makeText(c, text, Toast.LENGTH_SHORT).show();
            }
        });
    }
}
