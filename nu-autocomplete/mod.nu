# nu-autocomplete: open the IDE completion menu automatically while typing.
#
# `use nu-autocomplete` only defines commands; nothing changes until
# `nu-autocomplete enable` is run.

use keybindings.nu [MENU AUTO_MENU DEFAULT_ACCEPT_KEYS auto-menu cached-generate history-first-source is-ours parse-accept-keys]

# Completion settings applied on enable: no lone-candidate auto-insert, no
# common-prefix auto-insert, and an open menu closes when the line is emptied.
const SETTINGS = {quick: false, partial: false, persistent_menus: false}

# Line editor selection style applied on enable: the selection that marks a
# selected candidate is drawn like plain text instead of in reverse video.
const SELECTION_STYLE = {attr: n}

# Where enable caches generated keybindings, or null without a cache dir.
def cache-dir []: nothing -> any {
    let base = $nu.cache-dir? | default ""
    if ($base | is-empty) { null } else { $base | path join nu-autocomplete }
}

def state []: nothing -> record {
    $env.__NU_AUTOCOMPLETE? | default {enabled: false}
}

# Replace the keybinding list. Assigning a list to `$env.config.keybindings`
# merges it into the current one (Nushell >= 0.116), so entries can only be
# dropped by clearing the list first.
def --env set-keybindings [bindings: list]: nothing -> nothing {
    $env.config.keybindings = []
    if ($bindings | is-not-empty) {
        $env.config.keybindings = $bindings
    }
}

# Add or replace menus by name. Assigning a list to `$env.config.menus`
# merges it by name in Nushell 0.116 but replaces the whole list from 0.117,
# so the full list is assigned. When several menus share a name, the last
# one is in effect and the earlier ones are replaced too.
def --env set-menus [menus: list]: nothing -> nothing {
    let current = $env.config.menus
    let replaced = $current | each {|m| $menus | where name == $m.name | get 0? | default $m }
    $env.config.menus = $replaced ++ ($menus | where name not-in ($current | get name))
}

# The definition of `MENU` in effect.
def current-menu []: nothing -> record {
    $env.config.menus | where name == $MENU | last
}

# Enable automatic completion menus for the current session.
#
# Installs trigger keybindings for Emacs and Vi insert mode (never Vi normal),
# defines the menu `nu_autocomplete_menu` (a copy of `ide_completion_menu`
# that shows no selection), sets `completions.quick`, `completions.partial` and
# `completions.persistent_menus` to false and `color_config.selection` to
# `{attr: n}`. With SQLite history, both menus get a source that lists the
# history hint first, unless `--no-history-hint` is given or
# `ide_completion_menu` has a source of its own.
# Running it again replaces the previous installation instead of adding
# duplicates.
export def --env enable [
    --trigger: string = "all" # Keys that open the menu: 'all' (letters, digits, ASCII symbols, Space) or 'space'
    --accept-keys: list<string> # Keys that accept the selected candidate besides Enter (default: [ctrl+y]); in Vi insert, include 'enter' to make Enter accept
    --no-history-hint # Do not list the SQLite history hint as the first candidate
]: nothing -> nothing {
    let accept_keys = $accept_keys | default $DEFAULT_ACCEPT_KEYS
    if $trigger not-in [all space] {
        error make {msg: $"unknown trigger set '($trigger)'; expected 'all' or 'space'"}
    }
    # Fails on an invalid key spec before anything is changed.
    parse-accept-keys $accept_keys | ignore
    if $MENU not-in ($env.config.menus | get name) {
        error make {msg: $"the menu '($MENU)' is not defined in $env.config.menus"}
    }
    if (state).enabled { disable }

    # `AUTO_MENU` is derived from the current `MENU`. Menus cannot be removed
    # again; disable leaves it defined but unused.
    let history_hint = not $no_history_hint and $env.config.history.file_format == "sqlite" and (current-menu).source? == null
    let menu = if $history_hint { current-menu | merge {source: (history-first-source $nu.history-path)} } else { current-menu }
    set-menus [$menu ($menu | auto-menu)]

    let others = $env.config.keybindings | where {|kb| not ($kb | is-ours) }
    let generated = cached-generate (cache-dir) $trigger $others $accept_keys
    set-keybindings ($others ++ $generated.bindings)

    # Remember only the settings that actually change, with their old values.
    let current = $env.config.completions
    let changed = $SETTINGS | transpose key value | where {|s| ($current | get $s.key) != $s.value }
    for s in $changed {
        $env.config.completions = ($env.config.completions | upsert $s.key $s.value)
    }

    # `saved_selection` holds the old style only when enable changed it; a
    # null `value` means the key was unset.
    let selection = $env.config.color_config.selection?
    let saved_selection = if $selection == $SELECTION_STYLE { null } else { {value: $selection} }
    $env.config.color_config.selection = $SELECTION_STYLE

    $env.__NU_AUTOCOMPLETE = {
        enabled: true
        trigger: $trigger
        accept_keys: $accept_keys
        saved_completions: ($changed | reduce --fold {} {|s, acc| $acc | insert $s.key ($current | get $s.key) })
        saved_selection: $saved_selection
        history_hint: $history_hint
        skipped: $generated.skipped
    }
}

# Disable automatic completion menus and restore what enable changed.
#
# Removes every keybinding nu-autocomplete added (other bindings are kept) and
# restores each completion setting, the selection style and the menu source
# it changed, unless the setting was changed again after enable.
export def --env disable []: nothing -> nothing {
    let st = state
    if ($env.config.keybindings | any {|kb| $kb | is-ours }) {
        set-keybindings ($env.config.keybindings | where {|kb| not ($kb | is-ours) })
    }
    if not $st.enabled {
        return
    }

    for s in ($st.saved_completions | transpose key value) {
        if ($env.config.completions | get $s.key) == ($SETTINGS | get $s.key) {
            $env.config.completions = ($env.config.completions | upsert $s.key $s.value)
        }
    }

    let saved = $st.saved_selection? | default null
    if $saved != null and $env.config.color_config.selection? == $SELECTION_STYLE {
        if $saved.value == null {
            $env.config.color_config = ($env.config.color_config | reject selection)
        } else {
            $env.config.color_config.selection = $saved.value
        }
    }

    if ($st.history_hint? | default false) and (current-menu).source? == (history-first-source $nu.history-path) {
        set-menus [(current-menu | merge {source: null})]
    }

    $env.__NU_AUTOCOMPLETE = {enabled: false}
}

# Show whether nu-autocomplete is enabled and what it installed.
export def status []: nothing -> record {
    let st = state
    let ours = $env.config.keybindings | where {|kb| $kb | is-ours }
    {
        enabled: $st.enabled
        trigger: ($st.trigger? | default null)
        accept_keys: ($st.accept_keys? | default null)
        edit_mode: $env.config.edit_mode
        keybindings: ($ours | length)
        keybindings_by_mode: ($ours | group-by mode | items {|mode, kbs| {$mode: ($kbs | length)} } | reduce --fold {} {|it, acc| $acc | merge $it })
        skipped_keys: ($st.skipped? | default [])
        completions: ($env.config.completions | select quick partial persistent_menus)
        selection_style: ($env.config.color_config.selection? | default null)
        history_hint: ($st.history_hint? | default false)
        menu: $MENU
        auto_menu: $AUTO_MENU
    }
}
