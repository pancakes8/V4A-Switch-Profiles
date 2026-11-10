#!/system/bin/sh
# Wird von Magisk beim Entfernen des Moduls ausgefuehrt.
# Profile, Konfigurationsdateien (v4a-slots.conf) und Logs bleiben erhalten.
ADB="${NVBASE:-/data/adb}"
rm -f "$ADB/v4a-switch.sh" "$ADB/xhifi-switch.sh" "$ADB/v4a-slot.sh"
rm -rf "$ADB/v4a-slot.lock"
