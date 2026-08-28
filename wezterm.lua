-- [How I Use Wezterm & Zsh For An Amazing Terminal Setup On My Mac | Josean Martinez](https://www.youtube.com/watch?v=TTgQV21X0SQ)
-- [How I use Wezterm by Matthew Weier O'Phinney](https://mwop.net/blog/2024-07-04-how-i-use-wezterm.html)
-- [My Wezterm Config | acklackl](https://www.youtube.com/watch?v=V1X4WQTaxrc)
-- [Make Wezterm Mimic Tmux by Lovelin](https://dev.to/lovelindhoni/make-wezterm-mimic-tmux-5893)
-- [Okay, I really like WezTerm by Alex Plescan](https://alexplescan.com/posts/2024/08/10/wezterm/)

-- [How to switch from Tmux to WezTerm by Florian Bellmann](https://www.florianbellmann.com/blog/switch-from-tmux-to-wezterm)
-- [Multiplexing](https://wezfurlong.org/wezterm/multiplexing.html)

-- Pull in the wezterm API
local os = require("os")
local wezterm = require("wezterm")
local resurrect = wezterm.plugin.require("https://github.com/MLFlexer/resurrect.wezterm")
local act = wezterm.action
local mux = wezterm.mux

-- --------------------------------------------------------------------
-- FUNCTIONS AND EVENT BINDINGS
-- --------------------------------------------------------------------

-- Resurrect state management
-- See https://github.com/MLFlexer/resurrect.wezterm
--
-- periodic_save writes state/workspace/<name>.json, but resurrect_on_gui_startup
-- reads state/current_state -- a file nothing in the plugin ever writes. Hence
-- the periodic_save.finished hook below; without it, startup restore no-ops.
--
-- save_windows/save_tabs off: periodic_save skips windows and tabs with empty
-- titles, and the workspace snapshot already nests every window, tab and pane.
resurrect.state_manager.periodic_save({
	interval_seconds = 900,
	save_workspaces = true,
	save_windows = false,
	save_tabs = false,
})

-- No scrollback capture is possible here: resurrect only saves pane text in the
-- "local" domain, and default_domain is "unix". The mux keeps live scrollback
-- across GUI restarts anyway; only a reboot loses it. Layout and cwd still
-- restore, and set_max_nlines() is omitted since it governed only that capture.
local function remember_active_workspace()
	resurrect.state_manager.write_current_state(mux.get_active_workspace(), "workspace")
end

wezterm.on("resurrect.state_manager.periodic_save.finished", remember_active_workspace)

-- Never restore on top of a live mux: it has already reattached the real
-- windows, and the snapshot would duplicate every one of them.
wezterm.on("gui-startup", function(cmd)
	if #mux.all_windows() > 0 then
		return
	end

	resurrect.state_manager.resurrect_on_gui_startup()

	-- restore_workspace spawns synchronously, so an empty list means nothing was
	-- restored -- open a window rather than starting with none.
	if #mux.all_windows() == 0 then
		mux.spawn_window(cmd or {})
	end
end)

-- --------------------------------------------------------------------
-- PROJECT SESSIONIZER
--
-- tmux-sessionizer equivalent: one keystroke to a workspace rooted at a project
-- directory, created on first visit. Uses InputSelector, so no fzf or zoxide.
-- --------------------------------------------------------------------

local sessionizer_roots = {
	wezterm.home_dir .. "/Workbench",
}

local sessionizer_pinned = {
	wezterm.home_dir .. "/.config/nvim",
	wezterm.home_dir .. "/.config/wezterm",
	wezterm.home_dir .. "/.config/ghostty",
}

local function discover_projects()
	local seen, projects = {}, {}

	local function add(path)
		path = path:gsub("/+$", "")
		local name = path:match("([^/]+)$")
		if name and not seen[path] then
			seen[path] = true
			table.insert(projects, { id = path, label = name })
		end
	end

	for _, root in ipairs(sessionizer_roots) do
		for _, dir in ipairs(wezterm.glob(root .. "/*/")) do
			add(dir)
		end
	end

	for _, dir in ipairs(sessionizer_pinned) do
		add(dir)
	end

	table.sort(projects, function(a, b)
		return a.label:lower() < b.label:lower()
	end)

	return projects
end

local switch_to_project = wezterm.action_callback(function(window, pane)
	window:perform_action(
		act.InputSelector({
			title = "Projects",
			description = "Select a project to open as a workspace",
			fuzzy = true,
			fuzzy_description = "Project: ",
			choices = discover_projects(),
			action = wezterm.action_callback(function(inner_window, inner_pane, id, label)
				if not id then
					return
				end

				-- Snapshot the outgoing workspace while it is still active.
				resurrect.state_manager.save_state(resurrect.workspace_state.get_workspace_state())
				resurrect.state_manager.write_current_state(label, "workspace")

				inner_window:perform_action(
					act.SwitchToWorkspace({ name = label, spawn = { cwd = id } }),
					inner_pane
				)
			end),
		}),
		pane
	)
end)

-- --------------------------------------------------------------------
-- CONFIGURATION
-- --------------------------------------------------------------------

-- This table will hold the configuration.
local config = {}

-- In newer versions of wezterm, use the config_builder which will
-- help provide clearer error messages
if wezterm.config_builder then
	config = wezterm.config_builder()
end

config.adjust_window_size_when_changing_font_size = false
config.automatically_reload_config = true
config.color_scheme = "Poimandres"

config.enable_scroll_bar = true
config.enable_wayland = true
config.font = wezterm.font("IBM Plex Mono")
config.font_size = 19
-- config.font = wezterm.font('Hack')
config.hide_tab_bar_if_only_one_tab = false
-- The leader is similar to how tmux defines a set of keys to hit in order to
-- invoke tmux bindings.
--
-- CMD, not CTRL: cmd chords are handled by the GUI and never written to the
-- pty, so this hands ctrl-a back to the remote side, where tmux uses it as its
-- own prefix. The modifier now tells you which layer you are driving --
-- cmd+<key> acts locally, ctrl-a <key> acts on the tmux session -- while the
-- suffixes stay identical in both.
config.leader = { key = "a", mods = "CMD", timeout_milliseconds = 2000 }
config.mouse_bindings = {
	-- Open URLs with Ctrl+Click
	{
		event = { Up = { streak = 1, button = "Left" } },
		mods = "CTRL",
		action = act.OpenLinkAtMouseCursor,
	},
}
config.pane_focus_follows_mouse = true
config.scrollback_lines = 5000
config.use_dead_keys = false
config.warn_about_missing_glyphs = false
config.window_decorations = "TITLE | RESIZE"
config.window_padding = {
	left = 0,
	right = 0,
	top = 0,
	bottom = 0,
}

-- Tab bar
config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = true
config.switch_to_last_active_tab_when_closing_tab = true
config.tab_max_width = 32
config.colors = {
	tab_bar = {
		active_tab = {
			fg_color = "#073642",
			bg_color = "#2aa198",
		},
	},
	split = "#418fde",
}

-- Setup muxing by default
config.unix_domains = {
	{
		name = "unix",
	},
}

-- Spawn panes into the mux server rather than locally, so that workspaces,
-- tabs and running processes survive quitting the GUI.
config.default_domain = "unix"

-- Custom key bindings
config.keys = {
	-- -- Disable Alt-Enter combination (already used in tmux to split pane)
	-- {
	--     key = 'Enter',
	--     mods = 'ALT',
	--     action = act.DisableDefaultAssignment,
	-- },

	-- Copy mode
	{
		key = "[",
		mods = "LEADER",
		action = act.ActivateCopyMode,
	},
	{ key = "c", mods = "CMD", action = wezterm.action.CopyTo("Clipboard") },
	{ key = "v", mods = "CMD", action = wezterm.action.PasteFrom("Clipboard") },
	{ key = "LeftArrow", mods = "OPT", action = wezterm.action.SendString("\x1bb") },
	{ key = "RightArrow", mods = "OPT", action = wezterm.action.SendString("\x1bf") },
	{ key = "LeftArrow", mods = "CMD", action = wezterm.action.SendString("\x01") },
	{ key = "RightArrow", mods = "CMD", action = wezterm.action.SendString("\x05") },
	{ key = "f", mods = "CMD", action = wezterm.action.Search("CurrentSelectionOrEmptyString") },

	-- ----------------------------------------------------------------
	-- TABS
	--
	-- Where possible, I'm using the same combinations as I would in tmux
	-- ----------------------------------------------------------------

	-- Show tab navigator; similar to listing panes in tmux
	{
		key = "w",
		mods = "LEADER",
		action = act.ShowTabNavigator,
	},
	-- Create a tab (alternative to Ctrl-Shift-Tab)
	{
		key = "c",
		mods = "LEADER",
		action = act.SpawnTab("CurrentPaneDomain"),
	},
	-- Rename current tab; analagous to command in tmux
	{
		key = ",",
		mods = "LEADER",
		action = act.PromptInputLine({
			description = "Enter new name for tab",
			action = wezterm.action_callback(function(window, pane, line)
				if line then
					window:active_tab():set_title(line)
				end
			end),
		}),
	},
	-- Move to next TAB
	{
		key = "n",
		mods = "LEADER",
		action = act.ActivateTabRelative(1),
	},
	-- Move to previous TAB
	{
		key = "p",
		mods = "LEADER",
		action = act.ActivateTabRelative(-1),
	},
	-- Close tab
	{
		key = "&",
		mods = "LEADER|SHIFT",
		action = act.CloseCurrentTab({ confirm = true }),
	},
	-- Move tab backward with Leader + ,
	{
		key = "<",
		mods = "LEADER|SHIFT",
		action = wezterm.action.MoveTabRelative(-1),
	},
	-- Move tab forward with Leader + .
	{
		key = ">",
		mods = "LEADER|SHIFT",
		action = wezterm.action.MoveTabRelative(1),
	},

	-- ----------------------------------------------------------------
	-- PANES
	--
	-- These are great and get me most of the way to replacing tmux
	-- entirely, particularly as you can use "wezterm ssh" to ssh to another
	-- server, and still retain Wezterm as your terminal there.
	-- ----------------------------------------------------------------

	-- -- Vertical split
	{
		-- |
		key = "|",
		mods = "LEADER|SHIFT",
		action = act.SplitPane({
			direction = "Right",
			size = { Percent = 50 },
		}),
	},
	-- Horizontal split
	{
		-- -
		key = "-",
		mods = "LEADER",
		action = act.SplitPane({
			direction = "Down",
			size = { Percent = 50 },
		}),
	},
	-- CMD + (h,j,k,l) to move between panes.
	--
	-- CMD, not CTRL: cmd chords are handled by the GUI and never written to the
	-- pty, so this leaves ctrl+h/j/k/l free for whatever is running in the pane --
	-- nvim's window navigation (init.lua:249-252), oil's splits, and ctrl+l
	-- clear-screen in the shell, all of which a CTRL binding here swallowed.
	--
	-- Overrides two WezTerm defaults: cmd+h was HideApplication (cmd+m still
	-- minimizes) and cmd+k was ClearScrollback.
	{
		key = "h",
		mods = "CMD",
		action = act.ActivatePaneDirection("Left"),
	},
	{
		key = "j",
		mods = "CMD",
		action = act.ActivatePaneDirection("Down"),
	},
	{
		key = "k",
		mods = "CMD",
		action = act.ActivatePaneDirection("Up"),
	},
	{
		key = "l",
		mods = "CMD",
		action = act.ActivatePaneDirection("Right"),
	},
	-- LEADER + (h,j,k,l) to resize panes
	{
		key = "h",
		mods = "LEADER",
		action = act.AdjustPaneSize({ "Left", 5 }),
	},
	{
		key = "j",
		mods = "LEADER",
		action = act.AdjustPaneSize({ "Down", 5 }),
	},
	{
		key = "k",
		mods = "LEADER",
		action = act.AdjustPaneSize({ "Up", 5 }),
	},
	{
		key = "l",
		mods = "LEADER",
		action = act.AdjustPaneSize({ "Right", 5 }),
	},
	-- Close/kill active pane
	{
		key = "x",
		mods = "LEADER",
		action = act.CloseCurrentPane({ confirm = true }),
	},
	-- Swap active pane with another one
	{
		key = "{",
		mods = "LEADER|SHIFT",
		action = act.PaneSelect({ mode = "SwapWithActiveKeepFocus" }),
	},
	-- Zoom current pane (toggle)
	{
		key = "z",
		mods = "LEADER",
		action = act.TogglePaneZoomState,
	},
	{
		key = "f",
		mods = "ALT",
		action = act.TogglePaneZoomState,
	},
	-- Move to next/previous pane
	{
		key = ";",
		mods = "LEADER",
		action = act.ActivatePaneDirection("Prev"),
	},
	{
		key = "o",
		mods = "LEADER",
		action = act.ActivatePaneDirection("Next"),
	},

	-- ----------------------------------------------------------------
	-- Workspaces
	--
	-- These are roughly equivalent to tmux sessions.
	-- ----------------------------------------------------------------

	-- Attach to muxer
	{
		key = "a",
		mods = "LEADER",
		action = act.AttachDomain("unix"),
	},

	-- Detach from muxer
	{
		key = "d",
		mods = "LEADER",
		action = act.DetachDomain({ DomainName = "unix" }),
	},

	-- Show list of workspaces that already exist
	{
		key = "s",
		mods = "LEADER",
		action = act.ShowLauncherArgs({ flags = "WORKSPACES" }),
	},
	-- Jump to any project directory, creating its workspace on first visit
	{
		key = "f",
		mods = "LEADER",
		action = switch_to_project,
	},
	-- Create a new named session; analagous to command in tmux
	{
		key = "N",
		mods = "LEADER|SHIFT",
		action = act.PromptInputLine({
			description = "Enter name for new workspace",
			action = wezterm.action_callback(function(window, pane, line)
				if line then
					window:perform_action(act.SwitchToWorkspace({ name = line }), pane)
				end
			end),
		}),
	},
	-- Rename current session; analagous to command in tmux
	{
		key = "$",
		mods = "LEADER|SHIFT",
		action = act.PromptInputLine({
			description = "Enter new name for session",
			action = wezterm.action_callback(function(window, pane, line)
				if line then
					mux.rename_workspace(window:mux_window():get_workspace(), line)
				end
			end),
		}),
	},

	-- Save the current workspace state
	{
		key = "s",
		mods = "LEADER|SHIFT",
		action = wezterm.action_callback(function(window, _)
			resurrect.state_manager.save_state(resurrect.workspace_state.get_workspace_state())
			remember_active_workspace()
			window:toast_notification("WezTerm", "Workspace state saved", nil, 4000)
		end),
	},
	-- Restore a saved workspace, window or tab via the fuzzy picker
	{
		key = "R",
		mods = "LEADER|SHIFT",
		action = wezterm.action_callback(function(window, pane)
			resurrect.fuzzy_loader.fuzzy_load(window, pane, function(id, _)
				local state_type = string.match(id, "^([^/]+)")
				id = string.match(id, "([^/]+)$")
				id = string.match(id, "(.+)%..+$")

				-- No restore_text: pane text is never captured under the unix domain.
				local opts = {
					relative = true,
					on_pane_restore = resurrect.tab_state.default_on_pane_restore,
				}

				if state_type == "workspace" then
					resurrect.workspace_state.restore_workspace(resurrect.state_manager.load_state(id, "workspace"), opts)
				elseif state_type == "window" then
					opts.window = pane:window()
					resurrect.window_state.restore_window(pane:window(), resurrect.state_manager.load_state(id, "window"), opts)
				elseif state_type == "tab" then
					resurrect.tab_state.restore_tab(pane:tab(), resurrect.state_manager.load_state(id, "tab"), opts)
				end
			end)
		end),
	},
}

-- --------------------------------------------------------------------
-- LEADER + number to activate that tab
-- --------------------------------------------------------------------

for i = 0, 9 do
	table.insert(config.keys, {
		key = tostring(i),
		mods = "LEADER",
		action = act.ActivateTab(i - 1),
	})
end

-- --------------------------------------------------------------------
-- Add status when wezterm is listening (after pressing leader key)
-- --------------------------------------------------------------------

wezterm.on("update-right-status", function(window, _)
	local SOLID_LEFT_ARROW = ""
	local ARROW_FOREGROUND = { Foreground = { Color = "#ffbf00" } }
	local prefix = ""

	if window:leader_is_active() then
		prefix = " " .. utf8.char(0x1f54c) -- [UTF8 icon Mosque](https://www.utf8icons.com/character/128332/mosque)
		SOLID_LEFT_ARROW = utf8.char(0xe0b2)
	end

	if window:active_tab():tab_id() ~= 0 then
		ARROW_FOREGROUND = { Foreground = { Color = "#ffbf00" } }
	end -- arrow color based on if tab is first pane

	window:set_left_status(wezterm.format({
		{ Background = { Color = "#418fde" } },
		{ Text = prefix },
		ARROW_FOREGROUND,
		{ Text = SOLID_LEFT_ARROW },
	}))
end)
-- and finally, return the configuration to wezterm
return config
