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
#   service   (Standard) Profil schreiben, App-Prozess beenden, Dienst starten.
#             Die FX-App oeffnet sich nicht.
#   app-back  zusaetzlich die App oeffnen und per Zurueck-Taste schliessen
#             (auf manchen Car-Boxen laesst sie sich so nicht schliessen)
#   app       zusaetzlich die App oeffnen und offen lassen (altes Verhalten)
#   V4A_APP_WAIT  Sekunden, die die App bei app-back offen bleibt (Standard 2)
#
# Effekt-Modus gesperrt ("Lock effect mode", z. B. bluetooth statt headset):
#   V4A_MIRROR_FROM  Modus, dessen Einstellungen das Profil bestimmen (Standard headset)
#   V4A_MIRROR_TO    Modi, die dieselben Einstellungen bekommen (Standard "bluetooth usb")
#   Damit gilt das geladene Profil in jedem dieser Modi. Abschalten: V4A_MIRROR_FROM=""

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
APP_WAIT="${V4A_APP_WAIT:-2}"
MIRROR_FROM="${V4A_MIRROR_FROM-headset}"
MIRROR_TO="${V4A_MIRROR_TO-bluetooth usb}"

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
# Manche System-App-Varianten speichern im geraetegeschuetzten Speicher (DE) statt in /data/data
PREFS_DE="${V4A_DATA_DE:-/data/user_de/0}/$PKG/shared_prefs"

usage() {
  echo "Aufruf: sh $0 load|list|save|check|info [profilname]"
  echo "  load <name>   Profil laden, App-Prozess beenden, Dienst neu starten (App oeffnet sich nicht)"
  echo "  check [name ...]  aktive Einstellungen und Profile vergleichen (Standard: music voice)"
  echo "  show [name ...]   Schalter, Kernel und EQ-Zeilen (headset) aktiv und je Profil anzeigen"
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

  # Einmalig: Speicherzugriff fuer den Dienst (z. B. IRS-Kernel unter /sdcard/ViPER4Android),
  # damit er ohne geoeffnete App auf seine Dateien zugreifen kann.
  mark="$STATE.perm.$PKG"
  if [ ! -f "$mark" ]; then
    pm grant "$PKG" android.permission.READ_EXTERNAL_STORAGE >/dev/null 2>&1
    pm grant "$PKG" android.permission.WRITE_EXTERNAL_STORAGE >/dev/null 2>&1
    cmd appops set "$PKG" MANAGE_EXTERNAL_STORAGE allow >/dev/null 2>&1
    { : > "$mark"; } 2>/dev/null
  fi
}

v4a_running() {
  dumpsys activity services "$PKG" 2>/dev/null | grep -q "ServiceRecord"
}

# Prozess der App beenden: weg ist der Zwischenspeicher der Einstellungen. Startet sich die
# App von selbst neu (persistent), liest sie dabei schon die neuen Dateien.
# Prozess-IDs aller Prozesse der App (auch Unterprozesse)
app_pids() {
  { ps -A 2>/dev/null || ps 2>/dev/null; } | grep -F "$PKG" | grep -v grep | awk '{print $2}'
}

stop_v4a() {
  p0=$(app_pids | tr '\n' ' ')
  am force-stop "$PKG" >/dev/null 2>&1
  sleep 1
  p1=$(app_pids | tr '\n' ' ')
  # Prozesse, die das Beenden ueberlebt haben, hart beenden
  killed=""
  for p in $p1; do
    case " $p0" in
      *" $p "*)
        kill -9 "$p" 2>/dev/null
        killed="$killed $p"
        ;;
    esac
  done
  if [ -n "$killed" ]; then
    sleep 1
    p1=$(app_pids | tr '\n' ' ')
  fi
  say "App-Prozess: vorher ${p0:-keiner}, nachher ${p1:-keiner}${killed:+ (hart beendet:$killed)}"
}

# App oeffnen. Bei "app-back" ohne Start-Animation und nach V4A_APP_WAIT Sekunden sofort
# zurueck, damit das Aufblitzen so kurz wie moeglich ist.
open_app() {
  if [ "$APPLY" = "app" ]; then
    am start -n "$PKG/$ACTIVITY" >/dev/null 2>&1
    return 0
  fi
  am start -W --activity-no-animation --activity-no-history \
    -n "$PKG/$ACTIVITY" >/dev/null 2>&1
  sleep "$APP_WAIT"
  input keyevent KEYCODE_BACK >/dev/null 2>&1
}

# Dienst starten, bei app/app-back danach die App oeffnen, und pruefen, ob der Dienst laeuft.
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
    app | app-back) open_app ;;
  esac

  if ! v4a_running; then
    sleep 2
  fi
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
  own=$(stat -c '%u:%g' "${2%/*}" 2>/dev/null)
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

# Name des Ausgangs aus dem Dateinamen (…speaker.xml -> speaker)
outname() {
  b="${1##*/}"
  b="${b%.xml}"
  echo "${b##*.}"
}

# Datei des Haupt-Modus (MIRROR_FROM) im Profilordner, sonst Rueckgabe 1
master_of() {
  [ -n "$MIRROR_FROM" ] || return 1
  for f in "$1"/*."$MIRROR_FROM".xml; do
    if [ -f "$f" ] && valid_xml "$f"; then
      echo "$f"
      return 0
    fi
  done
  return 1
}

# "Lock effect mode": Ist die App auf einen festen Modus gesperrt (z. B. bluetooth), soll das
# Profil trotzdem gelten. Die Einstellungen des Haupt-Modus kommen deshalb auch in die
# Dateien der Ziel-Modi.
mirror_modes() {
  m=$(master_of "$1") || return 0
  base="${m##*/}"
  prefix="${base%.${MIRROR_FROM}.xml}"
  got=""
  for to in $MIRROR_TO; do
    [ "$to" = "$MIRROR_FROM" ] && continue
    dst="$PREFS/$prefix.$to.xml"
    if [ -f "$dst" ]; then
      cat "$m" > "$dst" || continue
    else
      new_pref "$m" "$dst" || continue
    fi
    got="$got $to"
  done
  [ -n "$got" ] && say "Effekt-Modus: Einstellungen von $MIRROR_FROM auch fuer$got uebernommen."
  return 0
}

# Nutzt die App den geraetegeschuetzten Speicher (DE), bekommen dessen Dateien denselben Inhalt.
sync_de() {
  [ -d "$PREFS_DE" ] || return 0
  c=0
  for f in "$PREFS"/*.xml; do
    [ -f "$f" ] || continue
    wanted "${f##*/}" || continue
    dst="$PREFS_DE/${f##*/}"
    if [ -f "$dst" ]; then
      cat "$f" > "$dst" && c=$((c + 1))
    elif new_pref "$f" "$dst"; then
      c=$((c + 1))
    fi
  done
  [ "$c" -gt 0 ] && say "Auch im geraetegeschuetzten Speicher (DE) aktualisiert: $c Dateien."
  return 0
}

# Kurzkennung der FIR-EQ- und Convolver-Einstellungen einer Datei
sig() {
  [ -f "$1" ] || { echo "fehlt"; return; }
  grep -E 'fireq|convolver' "$1" 2>/dev/null | sort | md5sum | cut -c1-6
}

# Wert(e) eines Schalters aus einer Einstellungsdatei
flag() {
  v=$(grep "$2" "$1" 2>/dev/null | sed -n 's/.*value="\([a-z]*\)".*/\1/p' | tr '\n' ',' | sed 's/,$//')
  echo "${v:-?}"
}

desc() {
  [ -f "$1" ] || { echo "fehlt"; return; }
  echo "conv=$(flag "$1" 'convolver.enable') fir=$(flag "$1" 'fireq.enable') #$(sig "$1")"
}

# Nach dem Anwenden: stimmen die Einstellungen der App noch mit dem Profil ueberein?
verify_profile() {
  for src in "$1"/*.xml; do
    [ -f "$src" ] || continue
    wanted "${src##*/}" || continue
    valid_xml "$src" || continue
    dst="$PREFS/${src##*/}"
    exp="$src"
    on=$(outname "$src")
    for t in $MIRROR_TO; do
      if [ "$on" = "$t" ] && [ "$t" != "$MIRROR_FROM" ]; then
        mm=$(master_of "$1") && exp="$mm"
      fi
    done
    if [ "$(sig "$exp")" = "$(sig "$dst")" ]; then r="gleich"; else r="ABWEICHEND"; fi
    say "Kontrolle $on: Profil $(desc "$exp") | aktiv $(desc "$dst") -> $r"
  done
}

# Zeigt aktive Einstellungen und den Inhalt von Profilen zum Vergleichen
do_check() {
  [ "$#" -gt 0 ] || set -- music voice
  echo "Spiegelung: ${MIRROR_FROM:-aus} -> $MIRROR_TO"
  echo "Lock-Einstellungen der App:"
  grep -i 'lock' "$PREFS"/*.xml 2>/dev/null | sed 's#^[^:]*/##' | cut -c1-170
  echo "Aktiv in $PREFS:"
  for f in "$PREFS"/*.xml; do
    [ -f "$f" ] || continue
    wanted "${f##*/}" || continue
    echo "  $(outname "$f"): $(desc "$f")"
  done
  if [ -d "$PREFS_DE" ]; then
    echo "Aktiv im geraetegeschuetzten Speicher $PREFS_DE:"
    for f in "$PREFS_DE"/*.xml; do
      [ -f "$f" ] || continue
      wanted "${f##*/}" || continue
      echo "  $(outname "$f"): $(desc "$f")"
    done
  else
    echo "Kein geraetegeschuetzter Speicher (DE) vorhanden: $PREFS_DE"
  fi
  echo "Alle Einstellungsdateien der App (Zeit, Pfad):"
  find /data -maxdepth 6 -path '*shared_prefs*' -name "$PKG*.xml" -exec ls -l {} \; 2>/dev/null |
    awk '{print "  " $6, $7, $8}'
  echo "Gesperrte Modi / Lock siehe oben."
  for p in "$@"; do
    d=$(find_profile "$p") || { echo "Profil '$p': nicht gefunden"; continue; }
    echo "Profil '$p' ($d):"
    for f in "$d"/*.xml; do
      [ -f "$f" ] || continue
      wanted "${f##*/}" || continue
      echo "  $(outname "$f"): $(desc "$f")"
    done
  done
}

# Zeigt die Schalter und Kernel-/EQ-Zeilen einer Einstellungsdatei (zum Vergleich mit der App)
show_file() {
  if [ -f "$1" ]; then
    grep -E 'enable|kernel|fireq|convolver' "$1" | sed 's/^[ \t]*//' | cut -c1-150 | sed 's/^/    /'
  else
    echo "    (Datei fehlt)"
  fi
}

# show [name ...]: Einstellungen des Modus (Standard headset) aktiv und je Profil
do_show() {
  [ "$#" -gt 0 ] || set -- music voice
  mode="${V4A_SHOW_MODE:-headset}"
  echo "=== aktiv ($mode) ==="
  show_file "$PREFS/$PKG.$mode.xml"
  if [ -d "$PREFS_DE" ]; then
    echo "=== aktiv im DE-Speicher ($mode) ==="
    show_file "$PREFS_DE/$PKG.$mode.xml"
  fi
  for p in "$@"; do
    d=$(find_profile "$p") || { echo "=== Profil '$p': nicht gefunden ==="; continue; }
    echo "=== Profil '$p' ($mode) ==="
    show_file "$d/$PKG.$mode.xml"
  done
}

do_load() {
  check_name "$1"
  rotate_log
  T0=$(date +%s)

  dir=$(find_profile "$1") || {
    say "Profil '$1' nicht gefunden (Befehl 'list' zeigt die vorhandenen Profile)."
    exit 1
  }

  # Erst pruefen, ob etwas ladbar ist, bevor etwas veraendert wird.
  scan_profile "$dir" count
  if [ "$n" -eq 0 ]; then
    say "Es wurde keine Datei geladen (Profil '$1' in $dir, Ausgaenge: $OUTPUTS)."
    exit 1
  fi

  ensure_prefs_dir || {
    say "Datenordner $DATA/$PKG fehlt. Ist die FX-App (Paket $PKG) installiert? Befehl 'info' zeigt Details."
    exit 1
  }

  say "Lade Profil '${dir##*/}' ..."

  # 1) Dateien sofort schreiben (nach dieser Zeile steht das Profil in den Einstellungen)
  scan_profile "$dir" write
  written="$n"
  mirror_modes "$dir"
  sync_de
  { echo "${dir##*/}" > "$STATE"; } 2>/dev/null

  # 2) Hintergrunderlaubnis parallel setzen, App-Prozess beenden, Dienst neu starten
  allow_background &
  bgpid=$!
  stop_v4a
  wait "$bgpid" 2>/dev/null
  start_v4a
  verify_profile "$dir"

  if [ "$written" -eq 0 ]; then
    say "Es wurde keine Datei geschrieben (Profil '$1' in $dir, Ordner $PREFS)."
    exit 1
  fi

  say "Profil '${dir##*/}' geladen ($written Dateien), $RUNTXT, Modus $APPLY, Paket $PKG, $(( $(date +%s) - T0 )) s."
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
  echo "--- shared_prefs (DE)"
  ls -l "$PREFS_DE" 2>&1

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
  check) shift; do_check "$@" ;;
  show) shift; do_show "$@" ;;
  *) usage ;;
esac
