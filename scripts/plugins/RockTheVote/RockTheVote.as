    // RockTheVote.as
    // Plugin: RockTheVote
    // Author: wahke.lu
    // Description: Rock-The-Vote with menu, chat, binds, countdown and sounds.

    namespace RTV
    {
        const string RTV_VERSION = "1.0.5";

        // ---------- Config ----------
        class Cfg {
            // Voting
            uint minPlayers = 1;
            uint rtvStartCooldownSec = 0;
            uint playerCooldownSec = 0;
            uint voteDurationSec = 10;
            uint passPercent = 40;
            uint quorumPercent = 0;
            bool instantPass = true; // finish immediately if pass guaranteed (good for tests)

            // Maps
            string mapsSource = "mapcycle"; // auto | mapcycle | config | folder
            string maplistPath = "scripts/plugins/RockTheVote/maps.txt";
            uint blockRecentCount = 0;
            uint minMapRuntimeMin = 0;
            bool allowNomination = true;

            // Language
            string messagesLang = "de";

            // Admin overrides
            string adminOverrideFlag = ""; // placeholder if you later integrate a flag system
            string adminIdsPath = "scripts/plugins/RockTheVote/admins.txt";
            bool adminRequireForForce  = true; // protect /rtv_force
            bool adminRequireForFinish = true; // protect /rtv_finish

            // UI / Audio
            bool uiShowCenter = true;
            uint uiProgressTickSec = 5;
            uint uiR = 0, uiG = 255, uiB = 140;

            // Center HUD timings (new)
            float uiCenterHoldSec    = 6.0f;
            float uiCenterFadeInSec  = 0.05f;
            float uiCenterFadeOutSec = 0.25f;

            string soundOnStart = "gman/gman_choose1.wav";
            string soundOnPass  = "events/town_gate_open1.wav";
            string soundOnFail  = "buttons/blip1.wav";
            bool   enableCountdownSounds = true;
        }
        Cfg g_cfg;

        // ---------- State ----------
        bool g_voteActive = false;
        string g_candidateMap;
        dictionary g_yesVotes; // steamid -> true
        dictionary g_noVotes;
        array<string> g_mapPool;
        array<string> g_recentMaps;

        dictionary g_playerCooldownUntil; // steamid -> time
        float g_lastVoteStart = 0.0f;

        array<string> g_nominations; // simple FIFO

        // Keep menus alive
        CTextMenu@ g_menuMap = null;
        CTextMenu@ g_menuYesNo = null;

        // Admin list
        array<string> g_adminIds;

        // ---------- Language helpers ----------
        dictionary g_Lang;
        string g_LangSel = "de";

        void LangSet(const string &in code) { g_LangSel = code; }

        void LangSeedDefaultsEN() {
            g_Lang.set("VOTE_START", "Vote: Switch to '{MAP}'? Type /yes or /no. Remaining: {SEC}s");
            g_Lang.set("VOTE_TICK",  "YES:{YES} NO:{NO} | Players:{ONLINE} (Quorum:{QUORUM}%)");
            g_Lang.set("VOTE_PASS",  "Accepted ({PCT}% YES, {VOTES} votes). Changing to {MAP}…");
            g_Lang.set("VOTE_FAIL",  "Rejected ({PCT}% YES, {VOTES} votes; Quorum {QUORUM}%).");
            g_Lang.set("VOTE_BUSY",  "A vote is already running.");
            g_Lang.set("VOTE_FEW",   "Too few players online.");
            g_Lang.set("VOTE_COOLDOWN","Please wait before starting another vote.");
            g_Lang.set("MENU_TITLE", "RockTheVote – Choose a map");
            g_Lang.set("NO_MAPS_FOUND", "No maps found (mapcycle/config/index empty?)");
            g_Lang.set("NOM_DISABLED", "Nominations are disabled.");
            g_Lang.set("NOM_ADDED", "Nominated: {MAP}");
            g_Lang.set("VOTE_QUESTION", "RockTheVote - {MAP} ?");
            g_Lang.set("YES", "Yes");
            g_Lang.set("NO", "No");
            g_Lang.set("DEBUG_CHAT", "lang={LANG} keys={KEYS} pool={POOL}");
            g_Lang.set("ADMIN_ONLY_FORCE", "Only admins may use /rtv_force.");
            g_Lang.set("ADMIN_ONLY_FINISH", "Only admins may use /rtv_finish.");
        }

        bool LangLoad(const string &in path) {
            File@ f = g_FileSystem.OpenFile(path, OpenFile::READ);
            if (f is null || !f.IsOpen()) {
                g_Game.AlertMessage(at_warning, "[RTV] LangLoad failed: " + path + "\\n");
                return false;
            }
            string line;
            while (!f.EOFReached()) {
                f.ReadLine(line);
                line.Trim();
                if (line.Length() == 0) continue;
                if (line[0] == '#') continue;
                array<string>@ kv = line.Split("=");
                if (kv.length() == 2) g_Lang[kv[0]] = kv[1];
            }
            f.Close();
            return true;
        }

        string LangT(const string &in key, dictionary@ vars = null) {
            string s;
            if (!g_Lang.get(key, s)) s = key;
            if (vars !is null) {
                array<string> ks = vars.getKeys();
                for (uint i=0;i<ks.length();++i) {
                    string k = ks[i]; string v; vars.get(k, v);
                    s = s.Replace("{" + k + "}", v);
                }
            }
            return s;
        }

        // ---------- Admins ----------
        void LoadAdmins() {
            g_adminIds.resize(0);
            File@ f = g_FileSystem.OpenFile(g_cfg.adminIdsPath, OpenFile::READ);
            if (f is null || !f.IsOpen()) {
                g_Game.AlertMessage(at_warning, "[RTV] Admin list not found: " + g_cfg.adminIdsPath + "\\n");
                return;
            }
            string line;
            while (!f.EOFReached()) {
                f.ReadLine(line); line.Trim();
                if (line.Length() == 0 || line[0] == '#') continue;
                g_adminIds.insertLast(line);
            }
            f.Close();
            g_Game.AlertMessage(at_logged, "[RTV] Loaded " + g_adminIds.length() + " admin id(s)\\n");
        }

        bool IsAdmin(CBasePlayer@ pl) {
            if (pl is null) return false;
            string id = g_EngineFuncs.GetPlayerAuthId(pl.edict());
            return g_adminIds.find(id) >= 0;
        }

        // ---------- Utility ----------
        string SteamId(CBasePlayer@ pl) {
            return g_EngineFuncs.GetPlayerAuthId(pl.edict());
        }
        uint OnlineCount() { return uint(g_PlayerFuncs.GetNumPlayers()); }

        void PrintAll(const string &in msg, bool center = false) {
            string withCopy = msg + "\\n\\nCreated by wahke.lu"; // real newlines

            if (center && g_cfg.uiShowCenter) {
                HUDTextParams p; p.x = -1; p.y = 0.30; p.effect = 0;
                p.r1 = g_cfg.uiR; p.g1 = g_cfg.uiG; p.b1 = g_cfg.uiB; p.a1 = 255;
                p.fadeinTime  = g_cfg.uiCenterFadeInSec;
                p.fadeoutTime = g_cfg.uiCenterFadeOutSec;
                p.holdTime    = g_cfg.uiCenterHoldSec;
                g_PlayerFuncs.HudMessageAll(p, withCopy);
            }

            g_PlayerFuncs.ClientPrintAll(HUD_PRINTTALK, "[RTV v" + RTV_VERSION + "] " + msg + "\\n");
        }

        void PrintTo(CBasePlayer@ pl, const string &in msg) {
            g_PlayerFuncs.ClientPrint(pl, HUD_PRINTTALK, "[RTV v" + RTV_VERSION + "] " + msg + "\\n");
        }

        void PlaySoundAll(const string &in sample) {
            for (int i = 1; i <= g_Engine.maxClients; ++i) {
                CBasePlayer@ pl = g_PlayerFuncs.FindPlayerByIndex(i);
                if (pl is null || !pl.IsConnected()) continue;
                g_SoundSystem.EmitSoundDyn(pl.edict(), CHAN_AUTO, sample, 1.0f, ATTN_NORM, 0, PITCH_NORM);
            }
        }

        string FvoxForNumber(int n) {
            if (n == 10) return "fvox/ten.wav";
            if (n == 9)  return "fvox/nine.wav";
            if (n == 8)  return "fvox/eight.wav";
            if (n == 7)  return "fvox/seven.wav";
            if (n == 6)  return "fvox/six.wav";
            if (n == 5)  return "fvox/five.wav";
            if (n == 4)  return "fvox/four.wav";
            if (n == 3)  return "fvox/three.wav";
            if (n == 2)  return "fvox/two.wav";
            if (n == 1)  return "fvox/one.wav";
            return "";
        }

        // ---------- Config ----------
        void LoadConfig() {
            File@ f = g_FileSystem.OpenFile("scripts/plugins/RockTheVote/rockthevote.cfg", OpenFile::READ);
            if (f is null || !f.IsOpen()) {
                g_Game.AlertMessage(at_warning, "[RTV] Config not found, using defaults.\\n");
                return;
            }
            string line;
            while (!f.EOFReached()) {
                f.ReadLine(line); line.Trim();
                if (line.Length() == 0 || line[0] == '#') continue;
                array<string>@ kv = line.Split("="); if (kv.length() != 2) continue;

                string k = kv[0]; k = k.ToLowercase(); k.Trim();
                string v = kv[1]; v.Trim();

                if (k == "min_players") g_cfg.minPlayers = atoi(v);
                else if (k == "rtv_start_cooldown_sec") g_cfg.rtvStartCooldownSec = atoi(v);
                else if (k == "player_cooldown_sec") g_cfg.playerCooldownSec = atoi(v);
                else if (k == "vote_duration_sec") g_cfg.voteDurationSec = atoi(v);
                else if (k == "pass_percent") g_cfg.passPercent = atoi(v);
                else if (k == "pass_quorum_percent") g_cfg.quorumPercent = atoi(v);
                else if (k == "instant_pass") g_cfg.instantPass = (v == "1" || v == "true");

                else if (k == "maps_source") g_cfg.mapsSource = v;
                else if (k == "maplist_path") g_cfg.maplistPath = v;
                else if (k == "block_recent_count") g_cfg.blockRecentCount = atoi(v);
                else if (k == "min_map_runtime_min") g_cfg.minMapRuntimeMin = atoi(v);
                else if (k == "allow_nomination") g_cfg.allowNomination = (v == "1");

                else if (k == "messages_lang") g_cfg.messagesLang = v;

                else if (k == "admin_override_flag") g_cfg.adminOverrideFlag = v;
                else if (k == "admin_ids_path") g_cfg.adminIdsPath = v;
                else if (k == "admin_require_for_force") g_cfg.adminRequireForForce = (v == "1" || v == "true");
                else if (k == "admin_require_for_finish") g_cfg.adminRequireForFinish = (v == "1" || v == "true");

                else if (k == "ui_show_center") g_cfg.uiShowCenter = (v == "1");
                else if (k == "ui_progress_tick_sec") g_cfg.uiProgressTickSec = atoi(v);
                else if (k == "ui_color_r") g_cfg.uiR = atoi(v);
                else if (k == "ui_color_g") g_cfg.uiG = atoi(v);
                else if (k == "ui_color_b") g_cfg.uiB = atoi(v);
                else if (k == "ui_center_hold_sec") g_cfg.uiCenterHoldSec = atof(v);
                else if (k == "ui_center_fadein_sec") g_cfg.uiCenterFadeInSec = atof(v);
                else if (k == "ui_center_fadeout_sec") g_cfg.uiCenterFadeOutSec = atof(v);

                else if (k == "sound_on_start") g_cfg.soundOnStart = v;
                else if (k == "sound_on_pass") g_cfg.soundOnPass = v;
                else if (k == "sound_on_fail") g_cfg.soundOnFail = v;
                else if (k == "enable_countdown_sounds") g_cfg.enableCountdownSounds = (v == "1");
            }
            f.Close();
            g_Game.AlertMessage(at_logged, "[RTV] Config loaded (lang=" + g_cfg.messagesLang + ", source=" + g_cfg.mapsSource + ", instant=" + (g_cfg.instantPass ? "1" : "0") + ")\\n");
        }

        // ---------- Map list ----------
        bool LoadListFile(const string &in path) {
            File@ f = g_FileSystem.OpenFile(path, OpenFile::READ);
            if (f is null || !f.IsOpen()) return false;
            string line; bool any = false;
            while (!f.EOFReached()) {
                f.ReadLine(line); line.Trim();
                if (line.Length() == 0 || line[0] == '#') continue;
                g_mapPool.insertLast(line);
                any = true;
            }
            f.Close();
            return any;
        }

        void BuildMapPool() {
            g_mapPool.resize(0);
            bool ok = false;

            if (g_cfg.mapsSource == "auto") {
                ok = LoadListFile("data/rockthevote_maps_index.txt");
                if (!ok) { ok = BuildFromMapCycle(); }
                if (!ok) ok = LoadListFile(g_cfg.maplistPath);
            } else if (g_cfg.mapsSource == "mapcycle") {
                ok = BuildFromMapCycle();
            } else if (g_cfg.mapsSource == "config") {
                ok = LoadListFile(g_cfg.maplistPath);
            } else if (g_cfg.mapsSource == "folder") {
                ok = LoadListFile("data/rockthevote_maps_index.txt");
            }

            if (g_cfg.allowNomination && g_nominations.length() > 0) {
                for (int i=int(g_nominations.length())-1; i>=0; --i) {
                    string m = g_nominations[i];
                    int idx = g_mapPool.find(m);
                    if (idx >= 0) g_mapPool.removeAt(uint(idx));
                    g_mapPool.insertAt(0, m);
                }
            }

            g_Game.AlertMessage(at_logged, "[RTV] Map pool built: " + g_mapPool.length() + " entries (source=" + g_cfg.mapsSource + ")\\n");
        }

        bool BuildFromMapCycle() {
            array<string>@ arr = g_MapCycle.GetMapCycle();
            if (arr is null) {
                g_Game.AlertMessage(at_warning, "[RTV] g_MapCycle returned null\\n");
                return false;
            }
            bool any = false;
            for (uint i=0; i<arr.length(); ++i) {
                string m = arr[i];
                m.Trim();
                if (m.Length() == 0) continue;
                if (m[0] == '#') continue;
                g_mapPool.insertLast(m);
                any = true;
            }
            return any;
        }

        // ---------- Menus ----------
        void OpenMapMenu(CBasePlayer@ pl) {
            if (g_voteActive) { PrintAll(LangT("VOTE_BUSY")); return; }
            if (OnlineCount() < g_cfg.minPlayers) { PrintAll(LangT("VOTE_FEW")); return; }

            string id = SteamId(pl);
            if (!CanStartNewVote(id)) { PrintAll(LangT("VOTE_COOLDOWN")); return; }

            BuildMapPool();
            if (g_mapPool.length() == 0) { PrintAll(LangT("NO_MAPS_FOUND")); return; }

            @g_menuMap = CTextMenu(@OnMapChosen);
            g_menuMap.SetTitle(LangT("MENU_TITLE"));
            for (uint i=0; i<g_mapPool.length(); ++i) {
                g_menuMap.AddItem(g_mapPool[i], any(g_mapPool[i]));
            }
            g_menuMap.Register();
            g_menuMap.Open(0, 0, pl);
        }

        void OnMapChosen(CTextMenu@ menu, CBasePlayer@ pl, int item, const CTextMenuItem@ pItem) {
            if (item < 0 or pItem is null) return;
            string chosen = pItem.m_szName;
            any@ data = pItem.m_pUserData;
            if (data !is null) data.retrieve(chosen);
            StartVote(chosen);
        }

        void OpenYesNoMenuAll() {
            @g_menuYesNo = CTextMenu(@OnYesNo);
            dictionary v; v["MAP"] = g_candidateMap;
            g_menuYesNo.SetTitle(LangT("VOTE_QUESTION", v));
            g_menuYesNo.AddItem(LangT("YES"), any(true));
            g_menuYesNo.AddItem(LangT("NO"), any(false));
            g_menuYesNo.Register();
            for (int i = 1; i <= g_Engine.maxClients; ++i) {
                CBasePlayer@ pl = g_PlayerFuncs.FindPlayerByIndex(i);
                if (pl is null || !pl.IsConnected()) continue;
                g_menuYesNo.Open(0, 0, pl);
            }
        }

        void OnYesNo(CTextMenu@, CBasePlayer@ pl, int item, const CTextMenuItem@ pItem) {
            if (item < 0 or pItem is null) return;
            any@ data = pItem.m_pUserData;
            bool yes = (pItem.m_szName == LangT("YES"));
            if (data !is null) data.retrieve(yes);
            Vote(pl, yes);
        }

        // ---------- Vote flow ----------
        bool CanStartNewVote(const string &in steamid) {
            float now = g_Engine.time;
            if (now - g_lastVoteStart < g_cfg.rtvStartCooldownSec) return false;

            float until = 0.0f;
            if (g_playerCooldownUntil.get(steamid, until) && now < until) return false;

            g_playerCooldownUntil[steamid] = now + float(g_cfg.playerCooldownSec);
            return true;
        }

        void StartVote(const string &in map) {
            g_voteActive = true;
            g_candidateMap = map;
            g_yesVotes.deleteAll(); g_noVotes.deleteAll();
            g_lastVoteStart = g_Engine.time;

            dictionary vd; vd["MAP"] = map; vd["SEC"] = "" + g_cfg.voteDurationSec;
            PrintAll(LangT("VOTE_START", vd), true);
            if (g_cfg.soundOnStart.Length() > 0) PlaySoundAll(g_cfg.soundOnStart);

            OpenYesNoMenuAll();
            g_Scheduler.SetTimeout("RTV::TickProgress", float(g_cfg.uiProgressTickSec));
            g_Scheduler.SetTimeout("RTV::Countdown", 1.0f, g_cfg.voteDurationSec);
            g_Scheduler.SetTimeout("RTV::FinishVote", float(g_cfg.voteDurationSec));
        }

        void Countdown(int secondsLeft) {
            if (!g_voteActive) return;
            if (secondsLeft <= 0) return;

            if (g_cfg.enableCountdownSounds && secondsLeft <= 10) {
                string s = FvoxForNumber(secondsLeft);
                if (s.Length() > 0) PlaySoundAll(s);
            }

            HUDTextParams p; p.x = -1; p.y = 0.40; p.effect = 0;
            p.r1 = 255; p.g1 = 255; p.b1 = 255; p.a1 = 255;
            p.fadeinTime = 0.02f; p.fadeoutTime = 0.1f; p.holdTime = 0.9f;
            g_PlayerFuncs.HudMessageAll(p, "" + secondsLeft);

            g_Scheduler.SetTimeout("RTV::Countdown", 1.0f, secondsLeft - 1);
        }

        void TickProgress() {
            if (!g_voteActive) return;
            dictionary v; v["YES"] = "" + g_yesVotes.getSize();
            v["NO"] = "" + g_noVotes.getSize();
            v["ONLINE"] = "" + OnlineCount();
            v["QUORUM"] = "" + g_cfg.quorumPercent;
            PrintAll(LangT("VOTE_TICK", v), false);
            g_Scheduler.SetTimeout("RTV::TickProgress", float(g_cfg.uiProgressTickSec));
        }

        void Vote(CBasePlayer@ pl, bool yes) {
            if (!g_voteActive) return;
            string id = SteamId(pl);
            g_yesVotes.delete(id); g_noVotes.delete(id);
            if (yes) g_yesVotes[id] = true; else g_noVotes[id] = true;

            uint y = g_yesVotes.getSize();
            uint n = g_noVotes.getSize();
            dictionary v; v["YES"] = "" + y; v["NO"] = "" + n;
            v["ONLINE"] = "" + OnlineCount(); v["QUORUM"] = "" + g_cfg.quorumPercent;
            PrintAll(LangT("VOTE_TICK", v));

            if (g_cfg.instantPass) {
                TryFinishEarly();
            }
        }

        void TryFinishEarly() {
            if (!g_voteActive) return;
            uint y = g_yesVotes.getSize();
            uint n = g_noVotes.getSize();
            uint votes = y + n;
            uint online = OnlineCount();
            if (votes == 0) return;

            uint yesPct = uint((100 * y) / votes);
            uint needQuorum = (online * g_cfg.quorumPercent + 99) / 100;
            uint quorumMin = (needQuorum > 0 ? needQuorum : 1);
            bool quorumOk = votes >= quorumMin;
            if (quorumOk && yesPct >= g_cfg.passPercent) {
                FinishVote();
            }
        }

        void FinishVote() {
            if (!g_voteActive) return;
            g_voteActive = false;

            uint y = g_yesVotes.getSize();
            uint n = g_noVotes.getSize();
            uint votes = y + n;
            uint online = OnlineCount();

            uint needQuorum = (online * g_cfg.quorumPercent + 99) / 100;
            bool quorumOk = votes >= (needQuorum > 0 ? needQuorum : 1);

            uint yesPct = votes > 0 ? uint((100 * y) / votes) : 0;
            bool passed = quorumOk && (yesPct >= g_cfg.passPercent);

            if (passed) {
                dictionary v; v["PCT"] = "" + yesPct; v["VOTES"] = "" + votes; v["MAP"] = g_candidateMap; v["QUORUM"] = "" + g_cfg.quorumPercent;
                PrintAll(LangT("VOTE_PASS", v), true);
                if (g_cfg.soundOnPass.Length() > 0) PlaySoundAll(g_cfg.soundOnPass);
                g_EngineFuncs.ServerCommand("changelevel " + g_candidateMap + "\\n");
            } else {
                dictionary v; v["PCT"] = "" + yesPct; v["VOTES"] = "" + votes; v["QUORUM"] = "" + g_cfg.quorumPercent;
                PrintAll(LangT("VOTE_FAIL", v), true);
                if (g_cfg.soundOnFail.Length() > 0) PlaySoundAll(g_cfg.soundOnFail);
            }
        }

        // ---------- Nomination ----------
        void Nominate(CBasePlayer@, const string &in map) {
            if (!g_cfg.allowNomination) { PrintAll(LangT("NOM_DISABLED")); return; }
            string m = map; m.Trim();
            if (m.Length() == 0) return;
            if (g_nominations.find(m) < 0) g_nominations.insertLast(m);
            dictionary v; v["MAP"] = m;
            PrintAll(LangT("NOM_ADDED", v));
        }

        // ---------- Hooks / Commands ----------
        HookReturnCode OnSay(SayParameters@ p) {
            CBasePlayer@ pl = p.GetPlayer();
            string orig = p.GetArguments().Arg(0);
            string t = orig.ToLowercase();

            if (t == "/rtv" || t == "/rockthevote") { OpenMapMenu(pl); p.ShouldHide = true; return HOOK_HANDLED; }
            if (t == "/yes" || t == "yes")          { Vote(pl, true);  p.ShouldHide = true; return HOOK_HANDLED; }
            if (t == "/no"  || t == "no")           { Vote(pl, false); p.ShouldHide = true; return HOOK_HANDLED; }
            if (t.StartsWith("/nom "))              { Nominate(pl, orig.SubString(5)); p.ShouldHide = true; return HOOK_HANDLED; }

            if (t == "/rtv_version") {
                PrintTo(pl, "RockTheVote v" + RTV_VERSION);
                p.ShouldHide = true; return HOOK_HANDLED;
            }
            if (t == "/rtv_debug") {
                BuildMapPool();
                dictionary vars; vars["LANG"] = g_LangSel; vars["KEYS"] = "" + g_Lang.getSize(); vars["POOL"] = "" + g_mapPool.length();
                PrintTo(pl, LangT("DEBUG_CHAT", vars));
                p.ShouldHide = true; return HOOK_HANDLED;
            }
            if (t.StartsWith("/rtv_force ")) {
                if (g_cfg.adminRequireForForce && !IsAdmin(pl)) {
                    PrintTo(pl, LangT("ADMIN_ONLY_FORCE"));
                    p.ShouldHide = true; return HOOK_HANDLED;
                }
                string m = orig.SubString(11); m.Trim();
                if (m.Length() > 0) {
                    g_EngineFuncs.ServerCommand("changelevel " + m + "\\n");
                }
                p.ShouldHide = true; return HOOK_HANDLED;
            }
            if (t == "/rtv_finish") {
                if (g_cfg.adminRequireForFinish && !IsAdmin(pl)) {
                    PrintTo(pl, LangT("ADMIN_ONLY_FINISH"));
                    p.ShouldHide = true; return HOOK_HANDLED;
                }
                FinishVote();
                p.ShouldHide = true; return HOOK_HANDLED;
            }

            return HOOK_CONTINUE;
        }

        // Optional client console cmds
        CClientCommand g_cmdYes("rtv_yes", "Vote YES", @CmdYes);
        CClientCommand g_cmdNo ("rtv_no",  "Vote NO",  @CmdNo);
        CClientCommand g_cmdVersion("rtv_version", "Show RockTheVote version", @CmdVersion);
        CClientCommand g_cmdDebug("rtv_debug", "RTV debug info", @CmdDebug);

        void CmdYes(const CCommand@) { CBasePlayer@ pl = g_ConCommandSystem.GetCurrentPlayer(); if (pl !is null) Vote(pl, true); }
        void CmdNo (const CCommand@) { CBasePlayer@ pl = g_ConCommandSystem.GetCurrentPlayer(); if (pl !is null) Vote(pl, false); }
        void CmdVersion(const CCommand@) { CBasePlayer@ pl = g_ConCommandSystem.GetCurrentPlayer(); if (pl !is null) PrintTo(pl, "RockTheVote v" + RTV_VERSION); }
        void CmdDebug(const CCommand@) {
            CBasePlayer@ pl = g_ConCommandSystem.GetCurrentPlayer();
            BuildMapPool();
            dictionary vars; vars["LANG"] = g_LangSel; vars["KEYS"] = "" + g_Lang.getSize(); vars["POOL"] = "" + g_mapPool.length();
            if (pl !is null) PrintTo(pl, LangT("DEBUG_CHAT", vars));
            g_Game.AlertMessage(at_logged, "[RTV] DEBUG " + LangT("DEBUG_CHAT", vars) + "\\n");
        }

        // ---------- Engine lifecycle ----------
        void PluginInit() {
            g_Hooks.RegisterHook(Hooks::Player::ClientSay, @OnSay);
            g_Game.AlertMessage(at_logged, "[RTV] RockTheVote v" + RTV_VERSION + " initialized\\n");
        }

        void MapInit() {
            LoadConfig();

            // Language: defaults -> chosen -> fallback en
            g_Lang.deleteAll();
            LangSeedDefaultsEN();
            LangSet(g_cfg.messagesLang);
            string langPath = "scripts/plugins/RockTheVote/lang/" + g_cfg.messagesLang + ".txt";
            bool ok = LangLoad(langPath);
            if (!ok && g_cfg.messagesLang != "en") {
                g_Game.AlertMessage(at_warning, "[RTV] Falling back to EN language file.\\n");
                LangLoad("scripts/plugins/RockTheVote/lang/en.txt");
            }

            LoadAdmins();
            PrecacheSounds();
        }

        void PrecacheSounds() {
            if (g_cfg.soundOnStart.Length() > 0) { g_Game.PrecacheGeneric("sound/" + g_cfg.soundOnStart); g_SoundSystem.PrecacheSound(g_cfg.soundOnStart); }
            if (g_cfg.soundOnPass.Length()  > 0) { g_Game.PrecacheGeneric("sound/" + g_cfg.soundOnPass);  g_SoundSystem.PrecacheSound(g_cfg.soundOnPass);  }
            if (g_cfg.soundOnFail.Length()  > 0) { g_Game.PrecacheGeneric("sound/" + g_cfg.soundOnFail);  g_SoundSystem.PrecacheSound(g_cfg.soundOnFail);  }

            array<string> fx = {
                "fvox/ten.wav","fvox/nine.wav","fvox/eight.wav","fvox/seven.wav","fvox/six.wav",
                "fvox/five.wav","fvox/four.wav","fvox/three.wav","fvox/two.wav","fvox/one.wav"
            };
            for (uint i=0;i<fx.length();++i) {
                g_Game.PrecacheGeneric("sound/" + fx[i]);
                g_SoundSystem.PrecacheSound(fx[i]);
            }
        }
    } // namespace RTV

    // Global exports: ScriptInfo only here
    void PluginInit() {
        g_Module.ScriptInfo.SetAuthor("wahke.lu");
        g_Module.ScriptInfo.SetContactInfo("RockTheVote v" + RTV::RTV_VERSION + " - Created by wahke.lu");
        RTV::PluginInit();
    }
    void MapInit()    { RTV::MapInit();    }
