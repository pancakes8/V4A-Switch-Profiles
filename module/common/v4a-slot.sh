#!/system/bin/sh
# ==============================================================
# v4a-slot.sh - Widget-Taste (Platz) -> passendes Profil laden
# Teil des Magisk-Moduls "V4A Profile Switch" (wird von der App V4A Switch gerufen)
# ==============================================================
#
# Aufruf (als root):
#   sh v4a-slot.sh fx_music|fx_voice|xhifi_music|xhifi_voice [--fg]
#
# Standard: laeuft im Hintergrund, der Aufruf kehrt sofort zurueck.
# Mit --fg im Vordergrund (zum Testen per adb, Ausgabe sichtbar).
#
# Welcher Platz welches Profil laedt, steht in /data/adb/v4a-slots.conf:
#   FX_MUSIC="music"
#   FX_VOICE="voice"
#   XHIFI_MUSIC="Boosted"
#   XHIFI_VOICE="voice"
# Die Datei wird beim Installieren nur angelegt, wenn sie fehlt.

ADB="${V4A_ADB:-/data/adb}"
CONF="${V4A_SLOTS_CONF:-$ADB/v4a-slots.conf}"

FX_MUSIC="music"
FX_VOICE="voice"
XHIFI_MUSIC="Boosted"
XHIFI_VOICE="voice"
[ -f "$CONF" ] && . "$CONF"

case "$1" in
  fx_music)     eng="v4a-switch.sh";   prof="$FX_MUSIC" ;;
  fx_voice)     eng="v4a-switch.sh";   prof="$FX_VOICE" ;;
  xhifi_music)  eng="xhifi-switch.sh"; prof="$XHIFI_MUSIC" ;;
  xhifi_voice)  eng="xhifi-switch.sh"; prof="$XHIFI_VOICE" ;;
  *)
    echo "Aufruf: sh $0 fx_music|fx_voice|xhifi_music|xhifi_voice [--fg]"
    exit 1
    ;;
esac

# Ohne --fg: sich selbst vom Aufrufer geloest im Hintergrund neu starten.
if [ "$2" != "--fg" ]; then
  if command -v nohup >/dev/null 2>&1; then
    nohup sh "$0" "$1" --fg >/dev/null 2>&1 &
  else
    sh "$0" "$1" --fg >/dev/null 2>&1 &
  fi
  exit 0
fi

# Immer nur ein Umschaltvorgang gleichzeitig (schnelles Mehrfachtippen wartet in der Schlange).
LOCK="$ADB/v4a-slot.lock"
n=0
while ! mkdir "$LOCK" 2>/dev/null; do
  n=$((n + 1))
  if [ "$n" -gt 60 ]; then
    # Sperre haengt seit 60 s (z. B. nach Absturz): uebernehmen
    rm -rf "$LOCK"
    mkdir "$LOCK" 2>/dev/null
    break
  fi
  sleep 1
done
trap 'rmdir "$LOCK" 2>/dev/null' EXIT INT TERM

sh "$ADB/$eng" load "$prof"
