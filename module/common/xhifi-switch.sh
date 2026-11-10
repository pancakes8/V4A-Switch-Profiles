#!/system/bin/sh
# ==============================================================
# xhifi-switch.sh - ViPER4Android XHiFi: Profile per Root umschalten
# Teil des Magisk-Moduls "V4A Profile Switch"
# Standard-Paket: com.vipercn.viper4android.xhifi
# ==============================================================
#
# Nach dem Laden eines Profils wird der XHiFi-Prozess beendet. Der
# Dienst startet automatisch neu (sonst wird er ausdrücklich gestartet).
# Die App-Oberfläche wird NICHT geöffnet.
#
# Aufruf (als root):
#   sh xhifi-switch.sh load <name>      Profil laden und XHiFi-Prozess neu starten
#   sh xhifi-switch.sh loadsnap <name>  nur Snapshot-Profil laden (ignoriert .prf gleichen Namens)
#   sh xhifi-switch.sh list             alle erkannten Profile anzeigen
#   sh xhifi-switch.sh undo             Stand vor dem letzten "load" wiederherstellen
#   sh xhifi-switch.sh save <name>      aktuelle Einstellungen als Snapshot-Profil sichern
#   sh xhifi-switch.sh info             Diagnose (Bildschirm)
#   sh xhifi-switch.sh diag [name]      Diagnosebericht als Textdatei schreiben (siehe unten)
#
# Profilquellen (in dieser Reihenfolge durchsucht):
#   1. /sdcard/ViPER4Android/ProfileXHiFi/<name>.prf   Profile der XHiFi-App
#   2. /sdcard/ViPER4Android/Switcher-XHiFi/<name>/    Snapshots (Befehl "save")
#
# .prf-Format (Text), je Zeile:  schluessel=typ=wert
#   viper4android.headphone_xhifi.enable=boolean=true
#   viper4android.headphone_xhifi.playbackgain.ratio=string=100
# Die Werte werden in die passende Einstellungsdatei der App geschrieben
# (Datei wird anhand der Schlüssel gefunden). Alle anderen Einträge der Datei
# bleiben unverändert. Vorher wird alles geprüft; bei einem Fehler wird nichts
# verändert. Der vorherige Stand wird für "undo" gesichert.
#
# Diagnosebericht: "diag" schreibt /sdcard/ViPER4Android/xhifi-diagnose.txt mit
# Prozessen, App-Datenordner, Inhalt aller Einstellungsdateien, dem Modul-Log und
# dem Systemlog (nur Zeilen zu viper/xhifi). Mit "diag <name>" zusätzlich ein
# Trockentest: je Schlüssel der .prf alter und neuer Wert, ohne etwas zu ändern.
#
# Zieldatei für .prf: Jede Ausgabeart (headset, speaker, bluetooth, usb) hat eine
# eigene Einstellungsdatei mit denselben Schlüsselnamen. Standard ("auto"): der in
# XHiFi gesperrte Effektmodus ("Lock effect mode"). Ist keiner gesperrt, werden alle
# Dateien beschrieben, die diese Schlüssel enthalten. Festlegen per Konfiguration:
#   V4A_PRF_MODES="headset"   oder "headset bluetooth"   oder "all"
#
# Namen: Groß-/Kleinschreibung egal, "_" steht für ein Leerzeichen.
#
# Optionale Konfiguration in /data/adb/xhifi-switch.conf (Shell-Syntax), z. B.:
#   V4A_OUTPUTS="headset"        (nur für Snapshots)
# Weitere optionale Variablen:
#   V4A_PKG, V4A_SERVICE, V4A_STORAGE, V4A_PRF_DIR, V4A_BASE, V4A_LOG,
#   V4A_PRF_MODES, V4A_DATA, V4A_STATE, V4A_UNDO, V4A_TMP, V4A_DIAG

# --- Konfigurationsdatei zuerst einlesen, damit sie alle Standardwerte überschreiben kann
CONF="${V4A_CONF:-/data/adb/xhifi-switch.conf}"
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
PKG="${V4A_PKG:-com.vipercn.viper4android.xhifi}"
SERVICE="${V4A_SERVICE:-.service.HeadsetService}"
DATA="${V4A_DATA:-/data/data}"
PRF_DIR="${V4A_PRF_DIR:-$ST/ProfileXHiFi}"
BASE="${V4A_BASE:-$ST/Switcher-XHiFi}"
LOG="${V4A_LOG:-$ST/profile-switch-log.txt}"
STATE="${V4A_STATE:-/data/adb/xhifi-switch.current}"
UNDO="${V4A_UNDO:-/data/adb/xhifi-switch.undo}"
TMPROOT="${V4A_TMP:-/data/local/tmp}"
OUTPUTS="${V4A_OUTPUTS:-speaker headset headphone bluetooth usb}"
TAG="XHiFi"

PREFS="$DATA/$PKG/shared_prefs"

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

usage() {
  echo "Aufruf: sh $0 load|loadsnap|list|undo|save|info|diag [profilname]"
  echo "  load <name>      Profil laden (.prf, sonst Snapshot) und XHiFi-Prozess neu starten"
  echo "  loadsnap <name>  nur Snapshot-Profil laden"
  echo "  list             alle erkannten Profile anzeigen"
  echo "  undo             Stand vor dem letzten load wiederherstellen"
  echo "  save <name>      aktuelle Einstellungen als Snapshot-Profil sichern"
  echo "  info             Diagnose (Bildschirm)"
  echo "  diag [name]      Diagnosebericht als Textdatei schreiben"
}

if [ -z "$V4A_NOROOTCHECK" ] && [ "$(id -u)" != "0" ]; then
  echo "Bitte als root ausfuehren (su)."
  exit 1
fi

# Prüft, ob ein Dateiname zu einem ausgewählten Ausgang gehört (für Snapshots).
wanted() {
  for o in $OUTPUTS; do
    case "$1" in
      *"$o"*) return 0 ;;
    esac
  done
  return 1
}

# Einstellungsdateien der ausgewählten Ausgänge finden (für Snapshots).
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

# .prf-Datei der XHiFi-App zu einem Namen finden. Gibt den Dateipfad aus.
find_prf() {
  want="$1"

  [ -f "$PRF_DIR/$want.prf" ] && {
    echo "$PRF_DIR/$want.prf"
    return 0
  }

  wn=$(norm "$want")
  for f in "$PRF_DIR"/*.prf; do
    [ -f "$f" ] || continue
    nm="${f##*/}"
    nm="${nm%.prf}"
    if [ "$(norm "$nm")" = "$wn" ]; then
      echo "$f"
      return 0
    fi
  done

  return 1
}

# Snapshot-Ordner zu einem Namen finden. Gibt den Ordnerpfad aus.
find_profile() {
  want="$1"

  [ -d "$BASE/$want" ] && {
    echo "$BASE/$want"
    return 0
  }

  wn=$(norm "$want")
  for d in "$BASE"/*/; do
    [ -d "$d" ] || continue
    nm="${d%/}"
    nm="${nm##*/}"
    if [ "$(norm "$nm")" = "$wn" ]; then
      echo "${d%/}"
      return 0
    fi
  done

  return 1
}

# Gesperrter Effektmodus der App ("Lock effect mode"): headset, speaker, ...
# Gibt den Wert aus (leer, wenn nichts gesperrt oder nicht lesbar).
get_lock_mode() {
  for f in "$PREFS"/*settings.xml; do
    [ -f "$f" ] || continue
    sed -n 's#.*name="viper4android\.settings\.lock_effect">\([^<]*\)</string>.*#\1#p' "$f" | head -1
    return 0
  done
}

# Zieldateien für eine Schlüsselgruppe (z. B. "headphone_xhifi") bestimmen.
# Jede Ausgabeart (headset, speaker, bluetooth, usb) hat eine eigene Einstellungs-
# datei mit denselben Schlüsselnamen. Welche gilt, bestimmt V4A_PRF_MODES:
#   auto (Standard)  der gesperrte Effektmodus ("lock_effect"); ist keiner gesperrt
#                    oder gibt es dessen Datei nicht, alle Dateien mit diesen Schlüsseln
#   all              alle Dateien, die diese Schlüssel enthalten
#   headset, "headset bluetooth", ...   genau diese Ausgänge
# Gibt je Zeile einen Dateipfad aus.
find_targets() {
  g="$1"
  modes="${V4A_PRF_MODES:-auto}"
  auto=0

  if [ "$modes" = "auto" ]; then
    auto=1
    lock=$(get_lock_mode)
    case "$lock" in
      headset|speaker|bluetooth|usb) modes="$lock" ;;
      *) modes="all" ;;
    esac
  fi

  if [ "$modes" != "all" ]; then
    found=0
    for m in $modes; do
      for f in "$PREFS"/*.xml; do
        [ -f "$f" ] || continue
        case "${f##*/}" in
          *".$m.xml")
            echo "$f"
            found=1
            ;;
        esac
      done
    done
    [ "$found" -eq 1 ] && return 0
    [ "$auto" -eq 1 ] || return 1
  fi

  grep -l "viper4android\.$g\." "$PREFS"/*.xml 2>/dev/null
  return 0
}

# Sicherungsordner für "undo" leeren und neu anlegen.
prepare_undo() {
  rm -rf "$UNDO"
  mkdir -p "$UNDO" 2>/dev/null
}

# XHiFi-Prozess beenden, auf den automatischen Neustart warten und den
# Dienst bei Bedarf ausdrücklich starten. Keine Activity, keine Home-Taste.
restart_v4a() {
  old_pids=$(pidof "$PKG")

  if [ -n "$old_pids" ]; then
    say "Starte XHiFi-Prozess neu: $old_pids"
    kill -9 $old_pids || {
      say "Fehler: XHiFi-Prozess konnte nicht beendet werden."
      exit 1
    }
  fi

  sleep 3

  if ! pidof "$PKG" >/dev/null 2>&1; then
    say "Starte XHiFi-Dienst explizit."
    am startservice -n "$PKG/$SERVICE" || {
      say "Fehler beim Starten des XHiFi-Dienstes."
      exit 1
    }
    sleep 3
  fi

  new_pids=$(pidof "$PKG")
  if [ -z "$new_pids" ]; then
    say "Fehler: Nach dem Neustart kein XHiFi-Prozess gefunden."
    exit 1
  fi

  say "XHiFi laeuft mit PID(s): $new_pids"
}

# --------------------------------------------------------------
# .prf anwenden
# Rückgabe 0 = ok (APPLIED_KEYS / APPLIED_FILES gesetzt), 1 = Fehler.
# Geschrieben wird erst ganz am Ende, nachdem alles geprüft wurde.
# --------------------------------------------------------------
apply_prf() {
  prf="$1"
  T="$TMPROOT/xhifi-prf.$$"

  rm -rf "$T"
  mkdir -p "$T/w" || {
    say "Temporaerer Ordner $T nicht anlegbar."
    return 1
  }

  # Zeilenenden bereinigen, letzte Zeile sicher abschließen
  tr -d '\r' < "$prf" > "$T/in"
  echo >> "$T/in"

  # 1) Jede Zeile prüfen (Format schluessel=typ=wert)
  : > "$T/kv"
  cnt=0
  bad=0
  while IFS= read -r line; do
    case "$line" in
      ""|"#"*|profile_name=*) continue ;;
    esac

    case "$line" in
      *=*=*) ;;
      *)
        say "Ungueltige Zeile in ${prf##*/}: $line"
        bad=1
        continue
        ;;
    esac

    key="${line%%=*}"
    rest="${line#*=}"
    type="${rest%%=*}"
    val="${rest#*=}"
    ok=1

    case "$key" in
      viper4android.*) ;;
      *) ok=0 ;;
    esac
    case "$key" in
      *[!A-Za-z0-9_.]*) ok=0 ;;
    esac

    case "$type" in
      boolean)
        case "$val" in
          true|false) ;;
          *) ok=0 ;;
        esac
        ;;
      int|long)
        case "$val" in
          ""|*[!0-9-]*) ok=0 ;;
        esac
        ;;
      float)
        case "$val" in
          ""|*[!0-9.eE+-]*) ok=0 ;;
        esac
        ;;
      string) ;;
      *) ok=0 ;;
    esac

    if [ "$ok" -ne 1 ]; then
      say "Nicht unterstuetzte Zeile in ${prf##*/}: $line"
      bad=1
      continue
    fi

    echo "$line" >> "$T/kv"
    cnt=$((cnt + 1))
  done < "$T/in"

  if [ "$bad" -ne 0 ]; then
    rm -rf "$T"
    return 1
  fi

  if [ "$cnt" -eq 0 ]; then
    say "Keine Einstellungen in ${prf##*/} gefunden."
    rm -rf "$T"
    return 1
  fi

  # 2) Schlüsselgruppen bestimmen (viper4android.<gruppe>.<name>)
  groups=""
  while IFS= read -r line; do
    g="${line#viper4android.}"
    g="${g%%.*}"
    case " $groups " in
      *" $g "*) ;;
      *) groups="$groups $g" ;;
    esac
  done < "$T/kv"

  # 3) Je Gruppe Zieldatei suchen und eine Arbeitskopie anpassen
  for g in $groups; do
    tlist=$(find_targets "$g")
    if [ -z "$tlist" ]; then
      say "Keine passende Einstellungsdatei fuer '$g' in $PREFS gefunden (Befehl 'info')."
      rm -rf "$T"
      return 1
    fi

    for tgt in $tlist; do
    base="${tgt##*/}"
    [ -f "$T/w/$base" ] || cp "$tgt" "$T/w/$base"

    grep "^viper4android\.$g\." "$T/kv" > "$T/g.kv"
    : > "$T/del.sed"
    : > "$T/add.xml"

    while IFS= read -r line; do
      key="${line%%=*}"
      rest="${line#*=}"
      type="${rest%%=*}"
      val="${rest#*=}"

      # alte Zeile dieses Schlüssels später entfernen
      ekey=$(printf '%s' "$key" | sed 's/\./\\./g')
      printf '/name="%s"/d\n' "$ekey" >> "$T/del.sed"

      # neue Zeile im Android-Einstellungsformat
      case "$type" in
        string)
          ev=$(printf '%s' "$val" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')
          printf '    <string name="%s">%s</string>\n' "$key" "$ev" >> "$T/add.xml"
          ;;
        *)
          printf '    <%s name="%s" value="%s" />\n' "$type" "$key" "$val" >> "$T/add.xml"
          ;;
      esac
    done < "$T/g.kv"

    want=$(( $(wc -l < "$T/g.kv") + 0 ))

    sed -f "$T/del.sed" -e '/<\/map>/d' -e 's#<map */>#<map>#' "$T/w/$base" > "$T/new.xml" 2>/dev/null
    cat "$T/add.xml" >> "$T/new.xml"
    echo "</map>" >> "$T/new.xml"

    # Plausibilitätsprüfung: <map> vorhanden und alle Schlüssel der Gruppe enthalten
    have=$(grep -c "name=\"viper4android\.$g\." "$T/new.xml")
    if ! grep -q '<map>' "$T/new.xml" || [ "${have:-0}" -lt "$want" ]; then
      say "Vorbereitung von $base fehlgeschlagen, es wurde nichts veraendert."
      rm -rf "$T"
      return 1
    fi

    cat "$T/new.xml" > "$T/w/$base"
    done
  done

  # 4) Erst jetzt schreiben (vorher Stand für "undo" sichern)
  files=0
  names=""
  for w in "$T/w"/*; do
    [ -f "$w" ] || continue
    base="${w##*/}"
    dst="$PREFS/$base"

    cp -f "$dst" "$UNDO/$base" 2>/dev/null

    # cat statt cp: Besitzer, Rechte und SELinux-Kontext der App-Datei bleiben erhalten.
    if ! cat "$w" > "$dst"; then
      say "Fehler beim Schreiben von $base (mit 'undo' zuruecksetzen)."
      rm -rf "$T"
      return 1
    fi
    files=$((files + 1))
    names="$names $base"
  done

  APPLIED_KEYS="$cnt"
  APPLIED_FILES="$files"
  APPLIED_NAMES="$names"
  rm -rf "$T"
  return 0
}

load_prf() {
  nm="${2##*/}"
  nm="${nm%.prf}"

  prepare_undo
  if ! apply_prf "$2"; then
    say "Profil '$nm' (.prf) wurde nicht vollstaendig geladen. Details stehen oben."
    exit 1
  fi

  { echo "$nm" > "$STATE"; } 2>/dev/null
  restart_v4a
  say "Profil '$nm' (.prf) geladen ($APPLIED_KEYS Einstellungen in $APPLIED_FILES Datei(en):$APPLIED_NAMES), XHiFi-Prozessneustart abgeschlossen (ohne App-Oberflaeche)."
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
  say "Snapshot-Profil '$1' gespeichert ($n Dateien) in $dir"
}

do_load() {
  check_name "$1"
  rotate_log

  # 1. Profil der XHiFi-App (.prf)
  if prf=$(find_prf "$1"); then
    load_prf "$1" "$prf"
    return
  fi

  # 2. Snapshot-Profil
  load_snapshot "$1"
}

# Snapshot-Profil laden (Ordner mit XML-Dateien, mit "save" angelegt).
load_snapshot() {
  dir=$(find_profile "$1") || {
    say "Profil '$1' nicht gefunden (Befehl 'list' zeigt die vorhandenen Profile)."
    exit 1
  }

  prepare_undo
  n=0
  for src in "$dir"/*.xml; do
    [ -f "$src" ] || continue
    wanted "${src##*/}" || continue

    if ! valid_xml "$src"; then
      say "Uebersprungen (keine Einstellungsdatei): ${src##*/}"
      continue
    fi

    dst="$PREFS/${src##*/}"
    if [ -f "$dst" ]; then
      cp -f "$dst" "$UNDO/${dst##*/}" 2>/dev/null
      # cat statt cp: Besitzer, Rechte und SELinux-Kontext
      # der App-Einstellungsdatei bleiben erhalten.
      cat "$src" > "$dst" && n=$((n + 1))
    else
      say "Uebersprungen (Zieldatei fehlt): ${src##*/}"
    fi
  done

  if [ "$n" -eq 0 ]; then
    say "Es wurde keine Datei geladen (Profil '$1' in $dir)."
    exit 1
  fi

  { echo "${dir##*/}" > "$STATE"; } 2>/dev/null
  restart_v4a
  say "Snapshot-Profil '${dir##*/}' geladen ($n Dateien), XHiFi-Prozessneustart abgeschlossen (ohne App-Oberflaeche)."
}

do_loadsnap() {
  check_name "$1"
  rotate_log
  load_snapshot "$1"
}

do_undo() {
  rotate_log

  if [ ! -d "$UNDO" ]; then
    say "Keine Sicherung vorhanden."
    exit 1
  fi

  n=0
  for b in "$UNDO"/*.xml; do
    [ -f "$b" ] || continue
    dst="$PREFS/${b##*/}"
    [ -f "$dst" ] || continue
    cat "$b" > "$dst" && n=$((n + 1))
  done

  if [ "$n" -eq 0 ]; then
    say "Keine Sicherung vorhanden."
    exit 1
  fi

  restart_v4a
  say "Stand vor dem letzten Laden wiederhergestellt ($n Dateien)."
}

do_list() {
  cur=""
  [ -f "$STATE" ] && cur=$(cat "$STATE")

  echo "Profile der XHiFi-App ($PRF_DIR):"
  cnt=0
  for f in "$PRF_DIR"/*.prf; do
    [ -f "$f" ] || continue
    nm="${f##*/}"
    nm="${nm%.prf}"
    cnt=$((cnt + 1))

    if [ "$nm" = "$cur" ]; then
      echo "* $nm   (zuletzt geladen)"
    else
      echo "  $nm"
    fi
  done
  [ "$cnt" -gt 0 ] || echo "  (keine)"

  echo "Snapshot-Profile ($BASE):"
  cnt=0
  for d in "$BASE"/*/; do
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

  echo "Namen mit Leerzeichen: in Anfuehrungszeichen oder mit _ statt Leerzeichen."
}

# Diagnosebericht als Textdatei schreiben (alles nur lesend).
do_diag() {
  OUT="${V4A_DIAG:-$ST/xhifi-diagnose.txt}"
  prof="$1"

  {
    echo "=== XHiFi-Diagnose $(date '+%F %T') ==="
    echo "Modul: xhifi-switch.sh (V4A Profile Switch)"
    echo "Paket: $PKG   Dienst: $SERVICE"
    echo "Android: $(getprop ro.build.version.release) (SDK $(getprop ro.build.version.sdk))   Geraet: $(getprop ro.product.model)"
    echo "Speicherort: $ST"
    echo
    echo "=== Prozesse (viper/xhifi) ==="
    ps -A 2>/dev/null | grep -i -E 'viper|xhifi'
    echo
    echo "=== Dateien in $PREFS ==="
    ls -l "$PREFS" 2>&1
    echo
    echo "=== Dateien mit XHiFi-Schluesseln (Anzahl Treffer je Datei) ==="
    for f in "$PREFS"/*.xml; do
      [ -f "$f" ] || continue
      echo "${f##*/}: $(grep -c 'viper4android\..*_xhifi\.' "$f")"
    done
    echo
    echo "=== App-Datenordner ($DATA/$PKG), Auszug ==="
    ls -lR "$DATA/$PKG" 2>&1 | head -n 80
    echo
    echo "=== Inhalt der Einstellungsdateien ==="
    for f in "$PREFS"/*; do
      [ -f "$f" ] || continue
      echo "----- ${f##*/} ($(wc -c < "$f") Bytes)"
      head -c 6000 "$f"
      echo
    done

    if [ -n "$prof" ]; then
      echo
      echo "=== Trockentest fuer Profil '$prof' (nichts wird veraendert) ==="
      echo "Gesperrter Effektmodus (lock_effect): '$(get_lock_mode)'   Zielmodi (V4A_PRF_MODES): ${V4A_PRF_MODES:-auto}"
      if prf=$(find_prf "$prof"); then
        echo "Datei: $prf ($(wc -c < "$prf") Bytes)"
        tmp="$TMPROOT/xhifi-diag.$$"
        tr -d '\r' < "$prf" > "$tmp"
        echo >> "$tmp"
        while IFS= read -r line; do
          case "$line" in
            ""|"#"*|profile_name=*) continue ;;
          esac
          case "$line" in
            *=*=*) ;;
            *)
              echo "UNGUELTIG: $line"
              continue
              ;;
          esac
          key="${line%%=*}"
          rest="${line#*=}"
          type="${rest%%=*}"
          val="${rest#*=}"
          g="${key#viper4android.}"
          g="${g%%.*}"
          tlist=$(find_targets "$g")
          echo "$key"
          echo "   neu  : $type = $val"
          [ -n "$tlist" ] || echo "   Ziel : (keine Datei gefunden)"
          for tgt in $tlist; do
            old=$(grep -F "name=\"$key\"" "$tgt" 2>/dev/null | head -1)
            echo "   Ziel : ${tgt##*/}"
            echo "   alt  : ${old:-(Schluessel in dieser Datei nicht vorhanden)}"
          done
        done < "$tmp"
        rm -f "$tmp"
      else
        echo "Keine .prf mit diesem Namen gefunden."
      fi
    fi

    echo
    echo "=== Modul-Log (letzte 30 Zeilen) ==="
    tail -n 30 "$LOG" 2>/dev/null
    echo
    echo "=== Systemlog (nur Zeilen zu viper/xhifi, letzte 80) ==="
    logcat -d -v time 2>/dev/null | grep -i -E 'viper|xhifi' | tail -n 80
  } > "$OUT" 2>&1

  say "Diagnosebericht geschrieben: $OUT"
}

do_info() {
  echo "Paket:        $PKG"
  echo "Dienst:       $PKG/$SERVICE"
  echo "Installiert:  $(pm path "$PKG" 2>/dev/null | head -1)"
  echo "App-UID:      $(stat -c %u "$DATA/$PKG" 2>/dev/null)"
  echo "Prozess-PIDs: $(pidof "$PKG" 2>/dev/null)"
  echo "Speicherort:  $ST"
  echo "App-.prf:     $PRF_DIR"
  echo "Snapshots:    $BASE"
  echo "Undo-Ordner:  $UNDO"
  echo "Log:          $LOG"

  echo "--- shared_prefs"
  ls -l "$PREFS" 2>&1

  echo "--- Gesperrter Effektmodus: '$(get_lock_mode)'   Zielmodi: ${V4A_PRF_MODES:-auto}"
  echo "--- Zieldateien fuer .prf (Gruppe headphone_xhifi)"
  find_targets headphone_xhifi

  echo "--- Snapshot-Dateien (Ausgaenge: $OUTPUTS)"
  pref_files

  echo "--- Profile"
  do_list

  echo "--- Komponenten der App"
  dumpsys package "$PKG" 2>/dev/null | grep -E " $PKG/" | head -20

  echo "--- laufende Dienste (Musik spielen / App vorher einmal starten)"
  dumpsys activity services "$PKG" 2>/dev/null |
    grep -E "ServiceRecord|intent=" |
    head -10
}

case "$1" in
  load) do_load "$2" ;;
  loadsnap) do_loadsnap "$2" ;;
  list) do_list ;;
  undo) do_undo ;;
  save) do_save "$2" ;;
  info) do_info ;;
  diag) do_diag "$2" ;;
  *) usage ;;
esac
