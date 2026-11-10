# V4A Switch – Profile umschalten ohne MacroDroid

System-App + Magisk-Modul (v2.0.0). Ersetzt die vier MacroDroid-Makros:

| Taste       | lädt (Standard)             |
|-------------|-----------------------------|
| FX Music    | FX-Profil `music`           |
| FX Voice    | FX-Profil `voice`           |
| XHiFi Music | XHiFi-Profil `Boosted`      |
| XHiFi Voice | XHiFi-Profil `voice`        |

Es gibt ein Widget (2×2 Tasten) und vier Starter-Symbole mit eigenen Icons
(erscheinen in der App-Liste, lassen sich auf den Startbildschirm ziehen).
Es läuft kein Dauerdienst: Beim Tippen ruft die App per Root das Skript
`/data/adb/v4a-slot.sh` auf, das die bisherigen Skripte `v4a-switch.sh` und
`xhifi-switch.sh` startet. Die alten Skripte und MacroDroid-Makros funktionieren weiter.

## 1. APK und Modul bauen (einmalig)

Ich konnte die App nicht selbst kompilieren (kein Android SDK in meiner Umgebung),
deshalb baut sie ein kostenloser GitHub-Server für dich – ohne Installation am PC:

1. Auf github.com ein Konto anlegen, neues (privates) Repository erstellen.
2. Den kompletten Inhalt dieses Ordners hochladen („Add file → Upload files“,
   den Ordner `.github` unbedingt mit).
3. Reiter **Actions** → **V4A Switch bauen** → **Run workflow**.
4. Nach ca. 2 Minuten beim fertigen Lauf unter **Artifacts** `V4A-Profile-Switch-Modul`
   herunterladen. Darin liegt `V4A-Profile-Switch-v2.0.0.zip` (das flashbare Modul).

Alternativ lokal (Linux/WSL): `ANDROID_HOME` setzen (build-tools und platforms ab 33,
JDK 17), dann `bash build.sh`. Ergebnis: `dist/V4A-Profile-Switch-v2.0.0.zip`.

## 2. Installieren

Magisk → Module → „Von Speicher installieren“ → ZIP wählen → Neustart.
Das alte Modul „V4A Profile Switch“ wird dabei ersetzt (gleiche ID).
Danach das Widget **V4A Profile (FX + XHiFi)** hinzufügen oder die Symbole benutzen.

## 3. Prüfen

    pm path de.v4aswitch                         # muss /system/app/V4ASwitch/... zeigen
    su -c 'sh /data/adb/v4a-slot.sh fx_music --fg'   # schaltet sichtbar im Vordergrund

Protokoll aller Wechsel: `/sdcard/ViPER4Android/profile-switch-log.txt`

## FX umschalten, ohne dass die FX-App aufgeht (ab v2.0.1)

`v4a-switch.sh` beendet beim Laden eines FX-Profils den Prozess der FX-App, schreibt die
Profildateien (fehlende Dateien werden angelegt) und startet nur den Dienst. Die App
öffnet sich nicht. Ob der Dienst lief, steht im Log
(`/sdcard/ViPER4Android/profile-switch-log.txt`).

Falls ein Profil so nicht wirkt, in `/data/adb/v4a-switch.conf` einstellen:

    V4A_APPLY="app-back"    # App kurz öffnen und sofort zurück
    V4A_APPLY="app"         # App öffnen und offen lassen (altes Verhalten)
    V4A_PKG="paket.name"    # nur nötig, wenn die FX-App anders heißt

### Nur das Skript tauschen (ohne Neubau)

    adb push v4a-switch.sh /sdcard/Download/
    adb shell su -c 'cp /sdcard/Download/v4a-switch.sh /data/adb/v4a-switch.sh && chmod 755 /data/adb/v4a-switch.sh'
    adb shell su -c 'sh /data/adb/v4a-switch.sh load music'
    adb shell su -c 'sh /data/adb/v4a-switch.sh info'

## Auf einem weiteren Gerät installieren

Das Modul-ZIP ist in sich komplett (App, Skripte, Konfiguration). Auf dem anderen Gerät:
Magisk → Module → ZIP installieren → Neustart. Weitere Schritte oder Skriptdateien sind
nicht nötig. Voraussetzungen: Magisk (ab ca. Version 20), Android 7 oder neuer,
ViPER4Android FX und/oder XHiFi installiert, und Profile, die so heißen wie in
`/data/adb/v4a-slots.conf` (Standard: FX `music`/`voice`, XHiFi `Boosted`/`voice`).
Die Profile selbst kopiert das Modul nicht: Ordner `Profile` und `ProfileXHiFi` unter
`ViPER4Android` im Gerätespeicher vom ersten Gerät übernehmen.

## Root-Freigabe

`service.sh` erteilt der App beim Start die Root-Freigabe (Magisk 24 oder neuer).
Klappt das nicht, fragt Magisk beim ersten Tippen. Bei „Root verweigert“:
Magisk → Superuser → **V4A Switch** erlauben.

## Profilnamen ändern

Datei `/data/adb/v4a-slots.conf` bearbeiten (wird bei Updates nicht überschrieben):

    FX_MUSIC="music"
    FX_VOICE="voice"
    XHIFI_MUSIC="Boosted"
    XHIFI_VOICE="voice"

## Meldungen beim Tippen

| Meldung                         | Bedeutung                                            |
|---------------------------------|------------------------------------------------------|
| „FX Music …“                    | Befehl wurde an Root übergeben                       |
| „Root verweigert“               | Magisk → Superuser → V4A Switch erlauben             |
| „Skript fehlt oder Fehler“      | Modul nicht (richtig) installiert                    |
| „su nicht gefunden“             | kein Root auf dem Gerät                              |
| „Keine Antwort von su“          | Magisk-Dialog wurde nicht beantwortet                |

## Sicherheit

Der Empfänger der Widget-Tasten ist nicht exportiert, die Symbole kennen nur die vier
festen Plätze. Fremde Apps können damit weder beliebige Profilnamen noch Befehle
an die Root-Shell schicken.
