# nu-autocomplete: open the IDE completion menu automatically while typing.
#
# `use nu-autocomplete` only defines commands; nothing changes until
# `nu-autocomplete enable` is run.

use keybindings.nu [MENU DEFAULT_ACCEPT_KEYS generate is-ours parse-accept-keys]

# Completion settings applied on enable: no lone-candidate auto-insert, no
# common-prefix auto-insert, and an open menu closes when the line is emptied.
const SETTINGS = {quick: false, partial: false, persistent_menus: false}

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

# Enable automatic completion menus for the current session.
#
# Installs trigger keybindings for Emacs and Vi insert mode (never Vi normal)
# and sets `completions.quick`, `completions.partial` and
# `completions.persistent_menus` to false. Running it again replaces the
# previous installation instead of adding duplicates.
export def --env enable [
    --trigger: string = "all" # Keys that open the menu: 'all' (letters, digits, ASCII symbols, Space) or 'space'
    --accept-keys: list<string> # Keys that accept the highlighted candidate (default: [right ctrl+y]); include 'enter' to make Enter accept
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

    let others = $env.config.keybindings | where {|kb| not ($kb | is-ours) }
    let generated = generate $trigger $others $accept_keys
    set-keybindings ($others ++ $generated.bindings)

    # Remember only the settings that actually change, with their old values.
    let current = $env.config.completions
    let changed = $SETTINGS | transpose key value | where {|s| ($current | get $s.key) != $s.value }
    for s in $changed {
        $env.config.completions = ($env.config.completions | upsert $s.key $s.value)
    }

    $env.__NU_AUTOCOMPLETE = {
        enabled: true
        trigger: $trigger
        accept_keys: $accept_keys
        saved_completions: ($changed | reduce --fold {} {|s, acc| $acc | insert $s.key ($current | get $s.key) })
        skipped: $generated.skipped
    }
}

# Disable automatic completion menus and restore what enable changed.
#
# Removes every keybinding nu-autocomplete added (other bindings are kept) and
# restores each completion setting it changed, unless the setting was changed
# again after enable.
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
        menu: $MENU
    }
}
