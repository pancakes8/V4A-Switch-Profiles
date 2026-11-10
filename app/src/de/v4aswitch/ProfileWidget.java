package de.v4aswitch;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.Context;
import android.content.Intent;
import android.widget.RemoteViews;

public class ProfileWidget extends AppWidgetProvider {

    @Override
    public void onUpdate(Context context, AppWidgetManager manager, int[] appWidgetIds) {
        RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.widget_profiles);
        bind(context, views, R.id.btn_fx_music, Switcher.FX_MUSIC, 1);
        bind(context, views, R.id.btn_fx_voice, Switcher.FX_VOICE, 2);
        bind(context, views, R.id.btn_xhifi_music, Switcher.XHIFI_MUSIC, 3);
        bind(context, views, R.id.btn_xhifi_voice, Switcher.XHIFI_VOICE, 4);
        for (int id : appWidgetIds) {
            manager.updateAppWidget(id, views);
        }
    }

    private static void bind(Context context, RemoteViews views, int viewId, String slot, int requestCode) {
        Intent intent = new Intent(context, SwitchReceiver.class);
        intent.setAction(SwitchReceiver.ACTION);
        intent.putExtra(SwitchReceiver.EXTRA_SLOT, slot);
        PendingIntent pi = PendingIntent.getBroadcast(
                context, requestCode, intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        views.setOnClickPendingIntent(viewId, pi);
    }
}
