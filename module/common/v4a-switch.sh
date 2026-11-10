#!/system/bin/sh
# ==============================================================
# v4a-switch.sh - ViPER4Android FX: Profile per Root umschalten
# Teil des Magisk-Moduls "V4A Profile Switch"
# Standard-Paket: com.vipercn.viper4android_v2
# ==============================================================
#
# Aufruf (als root):
#   sh v4a-switch.sh load <name>   Profil laden, Dienst neu starten (App bleibt im Hintergrund)
#   sh v4a-switch.sh list          alle erkannten Profile anzeigen
#   sh v4a-switch.sh save <name>   aktuelle Einstellungen als eigenes Profil sichern
#   sh v4a-switch.sh info          Diagnose
#
# Profilquellen (in dieser Reihenfolge durchsucht):
#   1. /sdcard/ViPER4Android/Profile/<name>/    Profile der FX-App (nur lesen)
#   2. /sdcard/ViPER4Android/Switcher/<name>/   eigene Profile dieses Skripts
#
# Namen: Groß-/Kleinschreibung egal, "_" steht für ein Leerzeichen.
#   "Classic Instrumental"  =  classic_instrumental
#
# Optionale Konfiguration in /data/adb/v4a-switch.conf (Shell-Syntax), z. B.:
#   V4A_OUTPUTS="headset"
# Weitere optionale Variablen:
#   V4A_PKG, V4A_SERVICE, V4A_ACTIVITY, V4A_STORAGE, V4A_PROFILE_DIR,
#   V4A_BASE, V4A_LOG, V4A_DATA, V4A_STATE
#
# Anwenden des Profils (V4A_APPLY):
#   service   (Standard) App-Prozess beenden, Profil schreiben, nur den Dienst starten.
#             Die FX-App oeffnet sich nicht.
#   app-back  zusaetzlich die App kurz oeffnen und sofort zurueck (kurzes Aufblitzen)
#   app       zusaetzlich die App oeffnen und offen lassen (altes Verhalten)

# --- Konfigurationsdatei zuerst einlesen, damit sie alle Standardwerte überschreiben kann
CONF="${V4A_CONF:-/data/adb/v4a-switch.conf}"
[ -f "$CONF" ] && . "$CONF"

# --- Speicherort des Ordners "ViPER4Android" ermitteln
ST="$V4A_STORAGE"
if [ -z "$ST" ]; then
  for c in /sdcard/ViPER4Android /storage/emulated/0/ViPER4Android /data/media/0/ViPER4Android; do
    if [ -d "$c" ]; then
      ST="$c"
      break
    fi
  done
  [ -n "$ST" ] || ST=/sdcard/ViPER4Android
fi

# --- Standardwerte
PKG="${V4A_PKG:-com.vipercn.viper4android_v2}"
SERVICE="${V4A_SERVICE:-.service.ViPER4AndroidService}"
ACTIVITY="${V4A_ACTIVITY:-.activity.ViPER4Android}"
DATA="${V4A_DATA:-/data/data}"
PROFILE_DIR="${V4A_PROFILE_DIR:-$ST/Profile}"
BASE="${V4A_BASE:-$ST/Switcher}"
LOG="${V4A_LOG:-$ST/profile-switch-log.txt}"
STATE="${V4A_STATE:-/data/adb/v4a-switch.current}"
OUTPUTS="${V4A_OUTPUTS:-speaker headset headphone bluetooth usb}"
TAG="FX"
APPLY="${V4A_APPLY:-service}"

say() {
  echo "$*"
  { echo "$(date '+%F %T') [$TAG] $*" >> "$LOG"; } 2>/dev/null
}

# Log klein halten (letzte 200 Zeilen behalten, sobald er ca. 100 KB überschreitet)
rotate_log() {
  [ -f "$LOG" ] || return 0
  sz=$(( $(wc -c < "$LOG" 2>/dev/null) + 0 ))
  [ "$sz" -gt 100000 ] || return 0
  tail -n 200 "$LOG" > "$LOG.tmp" 2>/dev/null && cat "$LOG.tmp" > "$LOG"
  rm -f "$LOG.tmp"
}

# Paket automatisch finden, falls das Standardpaket nicht installiert ist
# (z. B. andere Variante der FX-App als System-App). XHiFi wird ausgeschlossen.
if [ -z "$V4A_PKG" ] && [ -z "$(pm path "$PKG" 2>/dev/null)" ]; then
  alt=$(pm list packages 2>/dev/null | sed 's/^package://' | grep -i 'viper' | grep -v -i 'xhifi' | head -n 1)
  [ -n "$alt" ] && PKG="$alt"
fi
PREFS="$DATA/$PKG/shared_prefs"

usage() {
  echo "Aufruf: sh $0 load|list|save|info [profilname]"
  echo "  load <name>   Profil laden, Dienst neu starten (App bleibt im Hintergrund)"
  echo "  list          alle erkannten Profile anzeigen"
  echo "  save <name>   aktuelle Einstellungen als eigenes Profil sichern"
  echo "  info          Diagnose"
}

if [ -z "$V4A_NOROOTCHECK" ] && [ "$(id -u)" != "0" ]; then
  echo "Bitte als root ausfuehren (su)."
  exit 1
fi

# Prüft, ob ein Dateiname zu einem ausgewählten Ausgang gehört.
wanted() {
  for o in $OUTPUTS; do
    case "$1" in
      *"$o"*) return 0 ;;
    esac
  done
  return 1
}

# Einstellungsdateien der ausgewählten Ausgänge finden.
pref_files() {
  for f in "$PREFS"/*.xml; do
    [ -f "$f" ] || continue
    wanted "${f##*/}" && echo "$f"
  done
}

# Nur Pfad-Tricks verbieten; Leerzeichen, "+" usw. sind erlaubt.
check_name() {
  case "$1" in
    ""|.|..|*/*)
      echo "Ungueltiger Profilname."
      exit 1
      ;;
  esac
}

# Kleinbuchstaben, Leerzeichen -> "_"
norm() {
  printf '%s' "$1" | tr 'A-Z ' 'a-z_'
}

# Prüft, ob die Datei wie eine Android-Einstellungsdatei (XML mit <map>) aussieht.
valid_xml() {
  grep -q '<map' "$1" 2>/dev/null
}

# Profilordner zu einem Namen finden (App-Profile zuerst, dann eigene).
# Gibt den Ordnerpfad aus. Erst exakter Name, dann normalisierter Vergleich.
find_profile() {
  want="$1"

  for root in "$PROFILE_DIR" "$BASE"; do
    [ -d "$root/$want" ] && {
      echo "$root/$want"
      return 0
    }
  done

  wn=$(norm "$want")
  for root in "$PROFILE_DIR" "$BASE"; do
    for d in "$root"/*/; do
      [ -d "$d" ] || continue
      nm="${d%/}"
      nm="${nm##*/}"
      if [ "$(norm "$nm")" = "$wn" ]; then
        echo "${d%/}"
        return 0
      fi
    done
  done

  return 1
}

# Der Dienst darf im Hintergrund gestartet werden (Android 8+ sperrt das sonst still).
allow_background() {
  cmd deviceidle whitelist +"$PKG" >/dev/null 2>&1
  dumpsys deviceidle whitelist +"$PKG" >/dev/null 2>&1
  cmd appops set "$PKG" RUN_IN_BACKGROUND allow >/dev/null 2>&1
  cmd appops set "$PKG" RUN_ANY_IN_BACKGROUND allow >/dev/null 2>&1
}

v4a_running() {
  dumpsys activity services "$PKG" 2>/dev/null | grep -q "ServiceRecord"
}

# Dienst und Prozess der App beenden. Erst dadurch ist der Zwischenspeicher der
# Einstellungen weg und die App ueberschreibt die neue Datei nicht mehr.
stop_v4a() {
  allow_background
  am stopservice -n "$PKG/$SERVICE" >/dev/null 2>&1
  am force-stop "$PKG" >/dev/null 2>&1
  sleep 1
}

# Dienst starten (ohne die App zu oeffnen) und pruefen, ob er laeuft.
start_v4a() {
  out=$(am startservice -n "$PKG/$SERVICE" 2>&1)
  case "$out" in
    *[Ee]rror*|*"not allowed"*|*"Not allowed"*|*"in background"*)
      say "startservice: $(printf '%s' "$out" | tr '\n' ' ')"
      # Ersatz: Start-Signal an die App, ihr Empfaenger darf den Dienst starten
      am broadcast -a android.intent.action.BOOT_COMPLETED -p "$PKG" >/dev/null 2>&1
      ;;
  esac

  case "$APPLY" in
    app | app-back)
      sleep 2
      am start -n "$PKG/$ACTIVITY" >/dev/null 2>&1
      if [ "$APPLY" = "app-back" ]; then
        sleep 2
        input keyevent KEYCODE_BACK >/dev/null 2>&1
      fi
      ;;
  esac

  sleep 2
  if v4a_running; then
    RUNTXT="Dienst laeuft"
  else
    RUNTXT="Dienst NICHT gestartet"
  fi
}

# Datenordner fuer die Einstellungsdateien sicherstellen.
ensure_prefs_dir() {
  [ -d "$PREFS" ] && return 0
  [ -d "$DATA/$PKG" ] || return 1
  mkdir -p "$PREFS" || return 1
  own=$(stat -c '%u:%g' "$DATA/$PKG" 2>/dev/null)
  [ -n "$own" ] && chown "$own" "$PREFS" 2>/dev/null
  chmod 771 "$PREFS" 2>/dev/null
  restorecon "$PREFS" >/dev/null 2>&1
  return 0
}

# Fehlende Einstellungsdatei neu anlegen (Besitzer und SELinux-Kontext wie der Ordner).
new_pref() {
  cat "$1" > "$2" || return 1
  own=$(stat -c '%u:%g' "$PREFS" 2>/dev/null)
  [ -n "$own" ] && chown "$own" "$2" 2>/dev/null
  chmod 660 "$2" 2>/dev/null
  restorecon "$2" >/dev/null 2>&1
  return 0
}

do_save() {
  check_name "$1"
  rotate_log

  dir="$BASE/$1"
  mkdir -p "$dir" || {
    say "Ordner $dir nicht anlegbar"
    exit 1
  }

  n=0
  for f in $(pref_files); do
    cp "$f" "$dir/${f##*/}" && n=$((n + 1))
  done

  if [ "$n" -eq 0 ]; then
    say "Keine Einstellungsdateien in $PREFS gefunden (Befehl 'info' ausfuehren)."
    exit 1
  fi

  { echo "$1" > "$STATE"; } 2>/dev/null
  say "Profil '$1' gespeichert ($n Dateien) in $dir"
}

# Geht die Profildateien durch. Modus "count": zaehlt nur, was ladbar waere.
# Modus "write": schreibt in die Einstellungen der App. Ergebnis in n.
scan_profile() {
  n=0
  for src in "$1"/*.xml; do
    [ -f "$src" ] || continue
    wanted "${src##*/}" || continue

    if ! valid_xml "$src"; then
      [ "$2" = "write" ] && say "Uebersprungen (keine Einstellungsdatei): ${src##*/}"
      continue
    fi

    if [ "$2" = "count" ]; then
      n=$((n + 1))
      continue
    fi

    dst="$PREFS/${src##*/}"
    if [ -f "$dst" ]; then
      # cat statt cp: Besitzer, Rechte und SELinux-Kontext
      # der App-Einstellungsdatei bleiben erhalten.
      cat "$src" > "$dst" && n=$((n + 1))
    elif new_pref "$src" "$dst"; then
      say "Neu angelegt (fehlte): ${src##*/}"
      n=$((n + 1))
    else
      say "Uebersprungen (Zieldatei nicht anlegbar): ${src##*/}"
    fi
  done
}

do_load() {
  check_name "$1"
  rotate_log

  dir=$(find_profile "$1") || {
    say "Profil '$1' nicht gefunden (Befehl 'list' zeigt die vorhandenen Profile)."
    exit 1
  }

  # Erst pruefen, ob etwas ladbar ist, bevor die App beendet wird.
  scan_profile "$dir" count
  if [ "$n" -eq 0 ]; then
    say "Es wurde keine Datei geladen (Profil '$1' in $dir, Ausgaenge: $OUTPUTS)."
    exit 1
  fi

  ensure_prefs_dir || {
    say "Datenordner $DATA/$PKG fehlt. Ist die FX-App (Paket $PKG) installiert? Befehl 'info' zeigt Details."
    exit 1
  }

  stop_v4a
  scan_profile "$dir" write
  written="$n"

  { echo "${dir##*/}" > "$STATE"; } 2>/dev/null
  start_v4a

  if [ "$written" -eq 0 ]; then
    say "Es wurde keine Datei geschrieben (Profil '$1' in $dir, Ordner $PREFS)."
    exit 1
  fi

  say "Profil '${dir##*/}' geladen ($written Dateien), $RUNTXT, Modus $APPLY, Paket $PKG."
  if [ "$RUNTXT" != "Dienst laeuft" ] && [ "$APPLY" = "service" ]; then
    say "Hinweis: Dienst startet nicht von selbst. In /data/adb/v4a-switch.conf V4A_APPLY=\"app-back\" setzen."
  fi
}

# Alle Unterordner eines Verzeichnisses als Profile auflisten.
list_dir() {
  cnt=0
  for d in "$1"/*/; do
    [ -d "$d" ] || continue
    nm="${d%/}"
    nm="${nm##*/}"
    cnt=$((cnt + 1))

    if [ "$nm" = "$cur" ]; then
      echo "* $nm   (zuletzt geladen)"
    else
      echo "  $nm"
    fi
  done
  [ "$cnt" -gt 0 ] || echo "  (keine)"
}

do_list() {
  cur=""
  [ -f "$STATE" ] && cur=$(cat "$STATE")

  echo "Profile der App ($PROFILE_DIR):"
  list_dir "$PROFILE_DIR"
  echo "Eigene Profile ($BASE):"
  list_dir "$BASE"
  echo "Namen mit Leerzeichen: in Anfuehrungszeichen oder mit _ statt Leerzeichen."
}

do_info() {
  echo "Paket:        $PKG"
  echo "Dienst:       $PKG/$SERVICE"
  echo "Activity:     $PKG/$ACTIVITY"
  echo "Installiert:  $(pm path "$PKG" 2>/dev/null | head -1)"
  echo "App-UID:      $(stat -c %u "$DATA/$PKG" 2>/dev/null)"
  echo "Ausgaenge:    $OUTPUTS"
  echo "Modus:        $APPLY"
  v4a_running && echo "Dienst:       laeuft" || echo "Dienst:       laeuft nicht"
  echo "Speicherort:  $ST"
  echo "App-Profile:  $PROFILE_DIR"
  echo "Eigene:       $BASE"
  echo "Log:          $LOG"

  echo "--- shared_prefs"
  ls -l "$PREFS" 2>&1

  echo "--- erkannte Ausgangs-Dateien"
  pref_files

  echo "--- Profile"
  cur=""
  [ -f "$STATE" ] && cur=$(cat "$STATE")
  list_dir "$PROFILE_DIR"
  list_dir "$BASE"

  echo "--- Komponenten der App"
  dumpsys package "$PKG" 2>/dev/null | grep -E " $PKG/" | head -20

  echo "--- laufende Dienste (App vorher einmal oeffnen / Musik spielen)"
  dumpsys activity services "$PKG" 2>/dev/null |
    grep -E "ServiceRecord|intent=" |
    head -10
}

case "$1" in
  load) do_load "$2" ;;
  list) do_list ;;
  save) do_save "$2" ;;
  info) do_info ;;
  *) usage ;;
esac
