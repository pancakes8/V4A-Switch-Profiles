#!/system/bin/sh
# Magisk-Installationsskript (wird von Magisk eingelesen, nicht direkt starten)
# Dieses Modul legt die App als System-App ueber /system/app (systemlos) und
# kopiert die Root-Skripte nach /data/adb.

ADB="${NVBASE:-/data/adb}"
APK="$MODPATH/system/app/V4ASwitch/V4ASwitch.apk"

ui_print "- V4A Profile Switch 2.0 (System-App + Widget)"

[ -f "$APK" ] || abort "! V4ASwitch.apk fehlt im Modul (Build-Skript benutzen)"

ui_print "- Installiere Skripte nach $ADB"
for s in v4a-switch.sh xhifi-switch.sh v4a-slot.sh; do
  if [ -f "$ADB/$s" ]; then
    cp -f "$ADB/$s" "$ADB/$s.bak" 2>/dev/null &&
      ui_print "  Vorhandenes $s gesichert als $s.bak"
  fi
  cp -f "$MODPATH/common/$s" "$ADB/$s" || abort "! Kopieren von $s fehlgeschlagen"
  chmod 755 "$ADB/$s"
  ui_print "  $ADB/$s"
done

# Zuordnung Taste -> Profil nur anlegen, wenn sie noch nicht existiert
if [ ! -f "$ADB/v4a-slots.conf" ]; then
  cat > "$ADB/v4a-slots.conf" <<'CONF'
# Welches Profil laedt welche Widget-Taste? (Namen wie in den Profilordnern)
FX_MUSIC="music"
FX_VOICE="voice"
XHIFI_MUSIC="Boosted"
XHIFI_VOICE="voice"
CONF
  chmod 644 "$ADB/v4a-slots.conf"
  ui_print "  $ADB/v4a-slots.conf (neu angelegt)"
else
  ui_print "  $ADB/v4a-slots.conf bleibt unveraendert"
fi

set_perm_recursive "$MODPATH/system" 0 0 0755 0644

ui_print "- Fertig. Nach dem Neustart: Widget 'V4A Profile' hinzufuegen"
ui_print "  oder die Symbole FX Music / FX Voice / XHiFi Music / XHiFi Voice nutzen."
