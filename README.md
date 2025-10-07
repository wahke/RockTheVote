# RockTheVote (Sven Co-op AngelScript)

Ein schlichtes, robustes **Rock-The-Vote**-Plugin für **Sven Co-op ≥ 5.x**.
Spieler starten per `/rtv` ein Map-Vote, wählen eine Map aus und alle stimmen mit **Ja/Nein** – per Menü (klickbar), Chat **oder** Keybind.
Inklusive **10→1 Countdown** (fvox-Sprachsamples), Start-/Ergebnis-Sounds, Quorum/Prozent-Regeln, Mehrsprachigkeit und eigener Konfiguration.

**Autor:** wahke.lu • **Copyright:** Created by wahke.lu

---

## Features

- Befehle: `/rtv`, `/rockthevote`, optional `/nom <map>`
- **Antworten parallel**:
  - Menü („1) Ja / 2) Nein“),
  - Chat (`/yes`, `/no`),
  - Konsolenkommandos (`rtv_yes`, `rtv_no` → frei bindbar).
- **Countdown 10–1** (fvox-Samples), Start-/Pass/Fail-Sounds (precached).
- **Konfigurierbare Regeln**: Mindestspieler, Cooldowns, Laufzeit, Quorum, benötigte JA-%, Mindest-Map-Laufzeit, „recent maps“, Nominierungen, UI-Farben/Sounds.
- **Mehrsprachig** (DE/EN) per `lang/*.txt`.
- **Map-Quellen**: `mapcycle.txt`, eigene Liste oder (optional) Indexdatei aus Ordnerscan.
- **Einfacher Rollout**: eine AS-Datei + CFG + Lang-Files. Optional kleiner **AMX Mod X-Indexer** für echten `maps/*.bsp`-Scan.

---

## Kompatibilität

- **Sven Co-op ≥ 5.x** (AngelScript-Plugins).
- Läuft als **Plugin** (nicht als Map-Script).
- Optional: **AMX Mod X** (nur für die automatische Map-Indexdatei; ansonsten nicht nötig).

---

## Verzeichnisstruktur

### A) Inhalt des ZIP-Pakets (Distribution Layout)
```
svencoop_addon/
└── scripts/
    └── plugins/
        └── RockTheVote/
            ├── RockTheVote.as
            ├── rockthevote.cfg
            └── lang/
                ├── de.txt
                └── en.txt
optional/
└── addons/
    └── amxmodx/
        └── scripting/
            └── rtv_indexer.sma           # OPTIONAL: AMXX-Helper (Quellcode)
```

### B) Zielstruktur auf deinem Server nach Installation
```
svencoop_addon/
└── scripts/
    └── plugins/
        └── RockTheVote/
            ├── RockTheVote.as
            ├── rockthevote.cfg
            └── lang/
                ├── de.txt
                └── en.txt

data/
└── rockthevote_maps_index.txt            # wird vom AMXX-Indexer erzeugt (optional)

# NUR falls du den optionalen AMXX-Indexer verwendest:
addons/
└── amxmodx/
    ├── plugins/
    │   └── rtv_indexer.amxx              # kompilierte Version, in plugins.ini eintragen
    └── scripting/
        └── rtv_indexer.sma               # Quellcode (zum Kompilieren)
```

---

## Installation

1) **Dateien kopieren**  
Lege den Ordner `RockTheVote` (mit `.as`, `.cfg`, `lang/`) nach  
`svencoop_addon/scripts/plugins/RockTheVote/`.

2) **In `default_plugins.txt` eintragen**  
Füge in `svencoop/default_plugins.txt` innerhalb des bestehenden `"plugins"`-Blocks folgenden Eintrag hinzu (Pfad **ohne** `.as`-Endung, relativ zu `scripts/plugins/`):
```text
"plugin"
{
    "name"   "RockTheVote"
    "script" "RockTheVote/RockTheVote"
}
```

3) **Server neu starten** oder Plugins neu laden**
```
as_reloadplugins
```

### (Optional) AMX Mod X – Map-Indexer aktivieren
- Der Indexer scannt `maps/*.bsp` und schreibt `data/rockthevote_maps_index.txt`.
- Vorgehen:
  1. `optional/addons/amxmodx/scripting/rtv_indexer.sma` in dein Serververzeichnis kopieren.
  2. Mit dem **AMXX-Compiler** zu `rtv_indexer.amxx` kompilieren.
  3. `rtv_indexer.amxx` nach `addons/amxmodx/plugins/` legen.
  4. In `addons/amxmodx/configs/plugins.ini` **aktivieren** (Zeile `rtv_indexer.amxx`).
  5. Server starten. Der Index wird automatisch erzeugt.

---

## Konfiguration

Die Datei `scripts/plugins/RockTheVote/rockthevote.cfg` enthält alle Optionen mit Defaults (siehe unten).
Wichtig: Setze `maps_source=auto` (empfohlen). Dann nutzt das Plugin:
1) `data/rockthevote_maps_index.txt` (falls vorhanden – via AMXX-Indexer),
2) sonst `mapcycle.txt`,
3) sonst `maplist_path`.

```ini
min_players=2
rtv_start_cooldown_sec=120
player_cooldown_sec=180
vote_duration_sec=30
pass_percent=60
pass_quorum_percent=50

# mapcycle | folder | config | auto
maps_source=auto
maplist_path=scripts/plugins/RockTheVote/maps.txt
block_recent_count=3
min_map_runtime_min=5
allow_nomination=1
messages_lang=de
admin_override_flag=""

# UI / Audio
ui_show_center=1
ui_progress_tick_sec=10
ui_color_r=0
ui_color_g=255
ui_color_b=140
sound_on_start=gman/gman_choose1.wav
sound_on_pass=events/town_gate_open1.wav
sound_on_fail=buttons/blip1.wav
enable_countdown_sounds=1
```

---

## Nutzung (In-Game)

- **Vote starten:** `/rtv` (oder `/rockthevote`) → Map-Menü erscheint.
- **Abstimmen:**
  - Menü: Ziffern **1** (Ja) / **2** (Nein),
  - Chat: `/yes` / `/no`,
  - Keybinds: `bind F6 rtv_yes`, `bind F7 rtv_no`.
- **Optional nominieren:** `/nom <mapname>` (falls aktiviert).
- **Reload:** `as_reloadplugins` (Serverkonsole).

---

## GitHub Release (automatisch)

- Versionsnummer steht in `RockTheVote.as` als `const string RTV_VERSION = "X.Y.Z";`
- Ein **Tag-Push** `vX.Y.Z` erzeugt via GitHub Actions automatisch ein ZIP und ein Release.

---

## Lizenz

MIT (siehe `LICENSE`).

## Credits

- **wahke.lu** – Idee, Implementierung, Pflege.
- **Sven Co-op Team & Community** – AngelScript-API & Beispiele.
- **Valve** – fvox/gman-Samples (Bestandteil des Spiels; werden nur genutzt, nicht neu verteilt).
