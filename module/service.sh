#!/system/bin/sh
# Wird von Magisk nach dem Start ausgefuehrt (late_start service).
# Erteilt der App V4A Switch die Root-Freigabe vorab, damit beim ersten
# Tippen kein Magisk-Dialog aufgehen muss (Magisk 24 oder neuer).

PKG="de.v4aswitch"

(
  # Auf fertigen Systemstart warten (max. ca. 4 Minuten)
  n=0
  while [ "$(getprop sys.boot_completed)" != "1" ] && [ "$n" -lt 120 ]; do
    sleep 2
    n=$((n + 1))
  done
  sleep 5

  # UID der App ermitteln (System-App wird beim Start eingelesen)
  uid=""
  n=0
  while [ -z "$uid" ] && [ "$n" -lt 30 ]; do
    uid=$(cmd package list packages -U "$PKG" 2>/dev/null |
      sed -n 's/.*uid:\([0-9][0-9]*\).*/\1/p' | head -n 1)
    [ -n "$uid" ] || sleep 2
    n=$((n + 1))
  done
  [ -n "$uid" ] || exit 0

  # policy 2 = erlauben, until 0 = dauerhaft, logging 1, notification 0
  magisk --sqlite "REPLACE INTO policies (uid,policy,until,logging,notification) VALUES($uid,2,0,1,0);" >/dev/null 2>&1
) &
