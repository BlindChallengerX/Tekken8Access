--[[
  TekkenA11y v0.3 - config.lua
  ----------------------------------------------------------------------------
  Names below were filled in from a real dump (main menu, options, character
  select, stage select, pause, story). Some are confident; a few are marked
  VERIFY and may need one more targeted dump if a screen stays silent.
]]

local Config = {}

Config.keys = {
    read_focused = "F8",
    read_screen  = "F9",
    toggle_subs  = "F10",
    dump         = "F11",
    toggle_auto_dump = "F7",
    toggle_auto  = "F6",   -- master on/off for automatic reading (kill switch)
}

Config.timing = {
    focus_poll_ms     = 150,
    subtitle_poll_ms  = 150,
    dedupe_window_ms  = 250,
    state_expiry_ms   = 2500,
}

Config.verbosity = {
    speak_descriptions = true,
    speak_notation     = true,
}

Config.tekken = {
    -- Highlighted-item reading. We look for the one of these that currently has
    -- keyboard/user focus and read its text. Ordered most-specific first.
    focused_item_classes = {
        "WBP_UI_Dialog_LR_TextButton_C",  -- confirm/cancel dialog buttons
        "WBP_UI_Pause_MenuButton_C",      -- pause menu (5 buttons)
        "WBP_UI_OP_List_Button_C",        -- Options list
        "WBP_UI_MainMenu_Menu_ListSub_C", -- main-menu submenu rows
        "WBP_UI_MainMenu_Menu_List_C",    -- main-menu rows
        "WBP_UI_MainMenu_Tab_Item_C",     -- top tabs
        "WBP_UI_StageSelect_Button_C",    -- stage grid
    },

    -- Single readout widgets: poll their text, announce when it changes. These
    -- aren't lists -- they display "the current thing".
    readout_classes = {
        { class = "WBP_CharacterSelect_BG_Character_Name_C", key = "char_name" }, -- VERIFY: hovered fighter name
        { class = "WBP_UI_SideSelect_C",                     key = "side" },      -- choose play side
    },

    -- PRIMARY: event hooks. PlayAnimSelect fires on the item that just became
    -- the cursor target -> we read exactly that item (no scanning, no confusion
    -- from multiple State==1 rows across tabs, no per-list state-value issues).
    select_anim_hooks = {
        -- main menu list rows
        "/Game/UI/Widget/MainMenu/WBP_UI_MainMenu_Menu_List.WBP_UI_MainMenu_Menu_List_C:PlayAnimSelect",
        "/Game/UI/Widget/MainMenu/WBP_UI_MainMenu_Menu_List.WBP_UI_MainMenu_Menu_List_C:Select_Transiton",
        -- submenu rows
        "/Game/UI/Widget/MainMenu/WBP_UI_MainMenu_Menu_ListSub.WBP_UI_MainMenu_Menu_ListSub_C:PlayAnimSelect",
        "/Game/UI/Widget/MainMenu/WBP_UI_MainMenu_Menu_ListSub.WBP_UI_MainMenu_Menu_ListSub_C:Select_Transiton",
        -- top tabs (L/R)
        "/Game/UI/Widget/MainMenu/WBP_UI_MainMenu_Tab_Item.WBP_UI_MainMenu_Tab_Item_C:PlayAnimSelect",
        "/Game/UI/Widget/MainMenu/WBP_UI_MainMenu_Tab_Item.WBP_UI_MainMenu_Tab_Item_C:PlayAnimHover",
        -- shortcut bar
        "/Game/UI/Widget/MainMenu/WBP_UI_MainMenu_Shortcut_Item.WBP_UI_MainMenu_Shortcut_Item_C:PlayAnimSelect",
    },

    -- FALLBACK ONLY (used until the first hook fires): the row whose State
    -- equals the per-class value is the highlighted one. Different lists use
    -- different numbers (main list = 1, submenu = 2).
    stateful_menu_classes = {
        { class = "WBP_UI_MainMenu_Menu_List_C",    state = 1 },
        { class = "WBP_UI_MainMenu_Menu_ListSub_C", state = 2 },
    },
    selected_state_value = 1,

    -- Pop-ups / pre-menu screens to read when they appear (SF6-style):
    -- title screen, license, news, notices, dialogs ("Quit? Yes/No"), etc.
    announce_on_appear = {
        "WBP_UI_Dialog_C",
        "WBP_UI_Dialog_Menu_C",
        "WBP_UI_Dialog_LR_C",
        "WBP_UI_Notice_C",
        "WBP_UI_News_Content_C",
        "WBP_UI_News_Log_C",
        "WBP_UI_StartUp_Licence_C",
        "WBP_UI_Title_C",
        "WBP_UI_Loading_Dialog_C",
    },

    -- Story / cutscene subtitles.  CONFIDENT.
    subtitle_widget_classes = { "WBP_UI_Subtitle_C" },

    -- Read-screen (F9) noise filters.
    screen_read_ignore = {},                          -- by leaf class (rarely useful: all text is PolarisTextBlock)
    screen_read_ignore_text = { "[ID]", "fps" },      -- exact text to drop (FPS/debug overlay)
    screen_read_ignore_numbers = true,                -- drop standalone short numbers (fps "60", timers)

    -- Primary selection hooks (filled in after the next dump shows menu funcs).
    selection_hooks = {},

    -- Map "<height_cm>|<weight_kg>" (exactly as the game shows it) to a fighter.
    -- Built from your charselect_profiles.txt capture (ground truth), so these
    -- are exact in-game values, not conflicting web data. Height+weight is unique
    -- per fighter, which avoids the mis-naming that style-only matching would hit.
    char_names = {
        ["188|82"]  = "Victor",
        ["181|85"]  = "Kazuya",
        ["168|56"]  = "Nina",
        ["184|80"]  = "Hwoarang",
        ["190|83"]  = "Feng Wei",
        ["178|67"]  = "Yoshimitsu",
        ["183|83.5"] = "Clive",
        ["156|48"]  = "Kunimitsu",
        ["179|88"]  = "Devil Jin",
        ["277|320"] = "Kuma",
        ["167|57"]  = "Asuka",
        ["159|49"]  = "Xiaoyu",
        ["200|147"] = "King",
        ["225|400"] = "Jack-8",
        ["170|57"]  = "Jun",
        ["180|85"]  = "Lars",
        ["165|60"]  = "Alisa",
        ["180|66"]  = "Lili",
        ["280|360"] = "Panda",
        ["165|55"]  = "Anna",
        ["227|170"] = "Fahkumram",
        ["186|87"]  = "Bryan",
        ["192|98"]  = "Dragunov",
        ["184|72"]  = "Steve",
        ["180|80"]  = "Claudio",
        ["195|122"] = "Armor King",
        ["158|52"]  = "Miary Zo",
        ["177|67"]  = "Lidia",
        ["178|58"]  = "Leo",
        ["185|80"]  = "Shaheen",
        ["184|79"]  = "Raven",
        ["169|54"]  = "Zafina",
        ["188|89"]  = "Eddy",
        -- best guess from height/weight + nationality; PLEASE VERIFY these:
        ["183|87"]  = "Heihachi",
        ["178|72"]  = "Jin",
        ["179|80"]  = "Marshall Law",
    },

    name_overrides = {},
}

return Config
