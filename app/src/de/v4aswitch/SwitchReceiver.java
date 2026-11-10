package de.v4aswitch;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Empfaengt die Tasten des Widgets (nicht exportiert, nur eigene PendingIntents). */
public class SwitchReceiver extends BroadcastReceiver {

    public static final String ACTION = "de.v4aswitch.SWITCH";
    public static final String EXTRA_SLOT = "slot";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null) return;
        String slot = intent.getStringExtra(EXTRA_SLOT);
        if (!Switcher.isSlot(slot)) return;
        Switcher.trigger(context, slot, goAsync());
    }
}
