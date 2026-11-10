package de.v4aswitch;

import android.app.Activity;
import android.os.Bundle;

/** Unsichtbare Activity: loest den Wechsel aus und schliesst sich sofort. */
public abstract class BaseSwitchActivity extends Activity {

    protected abstract String slot();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Switcher.trigger(this, slot(), null);
        finish();
        overridePendingTransition(0, 0);
    }
}
