# Generation of the keybindings nu-autocomplete installs.
#
# Everything here is pure: it takes the current `$env.config.keybindings` and
# returns new entries, so it can be tested without touching the config.

# Prefix of every keybinding name nu-autocomplete owns.
export const NAME_PREFIX = "nu_autocomplete_"

# Edit modes the bindings are installed in. Vi normal/visual are never touched.
export const MODES = [emacs vi_insert]

# Edit modes with an unselected state: typing opens `AUTO_MENU`, which hides
# its highlight, and Tab, Shift+Tab, Ctrl+N or Ctrl+P switch to `MENU` and mark
# the line, so Enter and the accept keys can tell an explicit selection from
# the (hidden) first entry. Vi insert is left out: its Esc switches to normal
# mode without consulting keybindings and would leave the mark behind as a
# selection that normal-mode commands act on.
export const MARK_MODES = [emacs]

# The menu that shows a selected candidate (and, in Vi insert, the menu that
# is opened while typing).
export const MENU = "ide_completion_menu"

# The menu that is opened while typing in a mark mode: a copy of `MENU` whose
# selected entry looks like the others.
export const AUTO_MENU = "nu_autocomplete_menu"

# Keys that accept the highlighted candidate unless `enable --accept-keys` says otherwise.
export const DEFAULT_ACCEPT_KEYS = [ctrl+y]

# Keys that cannot be accept keys: nu-autocomplete binds them for another role
# (Tab, Left) or the open menu needs them (Shift+Tab, Esc, Backspace, Up, Down).
const RESERVED_KEYS = [tab backtab left esc backspace up down]

# Ctrl+<key> combinations that move through the menu in a mark mode.
const NAV_CTRL_KEYS = {n: menunext, p: menuprevious}

# Named keys an accept key spec may use, besides single chars and f1..f35.
const NAMED_KEYS = [enter right home end pageup pagedown delete insert space]

const MODIFIER_ALIASES = {ctrl: control, control: control, alt: alt, shift: shift, super: super}

# Printable ASCII symbols (no letters, digits or space).
const SYMBOLS = r#'!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~'#

# The key events a trigger set reacts to.
#
# crossterm (legacy, non-kitty input) reports a lowercase letter, a digit or a
# symbol with no modifier, and an uppercase letter as SHIFT + the uppercase
# char. Reedline lowercases the char before looking up a binding whenever a
# modifier is present, so uppercase letters are bound as `shift` + `char_<lower>`.
# Symbols and Space are also bound with `shift`, which is how terminals that
# report the Shift key for shifted symbols deliver them; the inserted char is
# the same either way.
#
# `key` is the normalized `<modifier> <keycode>` used to look up existing
# bindings: each keycode stands for its lowercased char.
export def trigger-keys [trigger: string = "all"]: nothing -> list<record<id: string, modifier: string, keycode: string, char: string, key: string>> {
    let space = [
        {id: space, modifier: none, keycode: space, char: " "}
        {id: shift_space, modifier: shift, keycode: space, char: " "}
    ]
    let keys = match $trigger {
        "space" => $space
        "all" => {
            let lower = (seq char a z)
            let letters = $lower | each {|c| {id: $c, modifier: none, keycode: $"char_($c)", char: $c} }
            let upper = $lower | each {|c|
                let u = $c | str uppercase
                {id: $"shift_($c)", modifier: shift, keycode: $"char_($c)", char: $u}
            }
            let digits = (seq 0 9) | each {|n|
                let c = $n | into string
                {id: $c, modifier: none, keycode: $"char_($c)", char: $c}
            }
            let symbols = $SYMBOLS | split chars | each {|c|
                let code = $c | into binary | encode hex | str lowercase
                # `char_u<hex>` avoids any quoting/case issue in the keycode string.
                [
                    {id: $"u($code)", modifier: none, keycode: $"char_u($code)", char: $c}
                    {id: $"shift_u($code)", modifier: shift, keycode: $"char_u($code)", char: $c}
                ]
            } | flatten
            $letters ++ $upper ++ $digits ++ $symbols ++ $space
        }
        _ => (error make {msg: $"unknown trigger set '($trigger)'; expected 'all' or 'space'"})
    }
    $keys | insert key {|k| $"($k.modifier) char_($k.char | str lowercase)" }
}

# Normalize a keycode the way Nushell parses it, so `char_A`, `char_a` and
# `char_u61` compare equal.
export def normalize-keycode [keycode: string]: nothing -> string {
    let k = $keycode | str lowercase
    if ($k | str starts-with "char_u") and ($k | str length) > 6 {
        let hex = $k | str substring 6..
        let c = try { $hex | into int --radix 16 | char --integer $in } catch { null }
        if $c != null { return $"char_($c)" }
    }
    if $k == "space" { return "char_ " }
    $k
}

# Normalize a modifier string (`Shift_Control` == `control_shift`).
export def normalize-modifier [modifier: string]: nothing -> string {
    $modifier | str lowercase | split row "_" | where $it != "none" | sort | str join "_"
    | if ($in | is-empty) { "none" } else { $in }
}

# Whether a keybinding entry was created by nu-autocomplete.
export def is-ours []: record -> bool {
    ($in.name? | default "" | into string) starts-with $NAME_PREFIX
}

# Whether a keybinding entry applies to `mode` (string or list of modes).
def applies-to [mode: string]: record -> bool {
    let m = $in.mode? | default []
    if ($m | describe | str starts-with "list") { $mode in $m } else { $m == $mode }
}

# Parse an accept key spec (`right`, `ctrl+y`, `ctrl+alt+l`, `enter`; case
# insensitive) into a keybinding modifier and keycode. Keys reserved for
# another role and keys that type a char are rejected.
export def parse-key-spec [spec: string]: nothing -> record<modifier: string, keycode: string> {
    let fail = {|why| error make {msg: $"invalid accept key '($spec)': ($why)"} }
    let m = $spec | str lowercase | parse --regex '^(?<mods>(?:[a-z]+\+)*)(?<key>.+)$'
    if ($m | is-empty) { do $fail "expected [modifier+]key, e.g. 'right' or 'ctrl+y'" }
    let names = $m.0.mods | split row "+" | where $it != ""
    let unknown = $names | where $it not-in ($MODIFIER_ALIASES | columns)
    if ($unknown | is-not-empty) {
        do $fail $"unknown modifier '($unknown.0)'; expected ctrl, alt, shift or super"
    }
    let mods = $names | each {|mod| $MODIFIER_ALIASES | get $mod } | uniq | sort
    let modifier = if ($mods | is-empty) { "none" } else { $mods | str join "_" }
    let key = $m.0.key
    if $key in $RESERVED_KEYS and $modifier == none {
        do $fail $"($key) is used by nu-autocomplete or the menu for something else"
    }
    if $key in ($NAV_CTRL_KEYS | columns) and $modifier == control {
        do $fail $"ctrl+($key) moves through the menu"
    }
    let keycode = if ($key | str length) == 1 {
        if $key =~ '^[a-z0-9]$' { $"char_($key)" } else { $"char_u($key | into binary | encode hex | str lowercase)" }
    } else if $key in ($NAMED_KEYS ++ $RESERVED_KEYS) or $key =~ '^f([1-9]|[12][0-9]|3[0-5])$' {
        $key
    } else {
        do $fail $"unknown key '($key)'"
    }
    # Reedline inserts a char for these modifier sets (Ctrl+Alt is AltGr).
    if (normalize-keycode $keycode) starts-with "char_" and $modifier in [none shift alt_control alt_control_shift] {
        do $fail "a key that types a char needs ctrl, alt or super (not ctrl+alt)"
    }
    {modifier: $modifier, keycode: $keycode}
}

# Parse a list of accept key specs, dropping specs that name the same key.
export def parse-accept-keys [specs: list<string>]: nothing -> list<record<modifier: string, keycode: string>> {
    $specs | each {|spec| parse-key-spec $spec }
    | insert key {|k| $"(normalize-modifier $k.modifier) (normalize-keycode $k.keycode)" }
    | uniq-by key | reject key
}

# Convert Reedline's debug form of an event (as shown by `keybindings default`)
# into a keybinding event record, or null for a form this does not handle.
#
# MenuLeft/MenuRight are dropped: an open IDE menu reports them as handled
# without doing anything, which would swallow the key.
def event-from-debug [debug: string]: nothing -> any {
    let d = $debug | str trim
    let inner = {|prefix| $d | str substring ($prefix | str length)..-3 }
    if ($d | str starts-with "UntilFound([") or ($d | str starts-with "Multiple([") {
        let until = $d | str starts-with "UntilFound"
        let items = split-top-level (do $inner (if $until { "UntilFound([" } else { "Multiple([" }))
        | where $it not-in [MenuLeft MenuRight]
        | each {|it| event-from-debug $it }
        if null in $items { return null }
        if $until { {until: $items} } else { $items }
    } else if ($d | str starts-with "Edit([") {
        let edits = split-top-level (do $inner "Edit([")
        if ($edits | length) != 1 { return null }
        let e = $edits.0 | parse --regex '^(?<name>[A-Za-z]+)(?: \{ select: (?<select>true|false) \})?$'
        if ($e | is-empty) { return null }
        let edit = {edit: ($e.0.name | str lowercase)}
        if ($e.0.select | is-empty) { $edit } else { $edit | insert select ($e.0.select == "true") }
    } else if $d =~ '^[A-Za-z]+$' {
        {send: ($d | str lowercase)}
    } else {
        null
    }
}

# Split on commas that are not nested in brackets or braces.
def split-top-level [text: string]: nothing -> list<string> {
    let acc = $text | split chars | reduce --fold {depth: 0, cur: "", out: []} {|c, acc|
        if $c == "," and $acc.depth == 0 {
            $acc | update out { append ($acc.cur | str trim) } | update cur ""
        } else {
            let depth = $acc.depth + (if $c in ["(" "[" "{"] { 1 } else if $c in [")" "]" "}"] { -1 } else { 0 })
            $acc | update depth $depth | update cur ($acc.cur + $c)
        }
    }
    $acc.out | append ($acc.cur | str trim) | where $it != ""
}

# The event Reedline itself binds to a key in a mode (`{send: none}` when it
# binds nothing). Vi insert has no Enter entry but submits on an unbound Enter.
export def reedline-default [mode: string, modifier: string, keycode: string]: nothing -> any {
    let mod = normalize-modifier $modifier
    let key = normalize-keycode $keycode
    # Match the keycode first with column-wise string ops (keeping the forms
    # normalize-keycode rewrites), so the custom commands only run on the few
    # remaining entries.
    let found = keybindings default | where mode == $mode
    | str replace --regex "^Char\\('(.*)'\\)$" 'char_$1' code | str replace --regex '^F\((\d+)\)$' 'f$1' code | str lowercase code
    | where code == $key or code starts-with "char_u" or code == "space"
    | where {|kb|
        let m = $kb.modifier | str replace --regex '^KeyModifiers\((.*)\)$' '$1' | str replace "0x0" none | str replace --all " | " "_"
        (normalize-modifier $m) == $mod and (normalize-keycode $kb.code) == $key
    }
    if ($found | is-empty) {
        return (if $mod == none and $key == enter { {send: enter} } else { {send: none} })
    }
    let event = event-from-debug $found.0.event
    if $event == null {
        error make {msg: $"cannot reproduce Reedline's default for ($modifier) ($keycode) in ($mode) \(($found.0.event)\); bind the key yourself before enable or choose another accept key"}
    }
    $event
}

# Normalized `<modifier> <keycode>` lookup key.
def key-id [modifier: string, keycode: string]: nothing -> string {
    $"(normalize-modifier $modifier) (normalize-keycode $keycode)"
}

# The bindings (other than ours) that apply to a mode, grouped by key-id in
# their original order. Build it once per mode: normalizing every binding
# for each looked-up key made enable take hundreds of milliseconds.
def key-index [mode: string]: list -> record {
    where {|kb| not ($kb | is-ours) }
    | where {|kb| $kb | applies-to $mode }
    | group-by {|kb| key-id ($kb.modifier | into string) ($kb.keycode | into string) }
}

# The binding (other than ours) that currently handles a key in a key-index:
# the last matching entry wins, as in Nushell. Returns null when only the
# built-in Reedline default applies.
def lookup [modifier: string, keycode: string]: record -> any {
    get --optional (key-id $modifier $keycode) | default [] | last
}

# The binding (other than ours) that currently handles a key in a mode.
export def find-existing [mode: string, modifier: string, keycode: string]: list -> any {
    key-index $mode | lookup $modifier $keycode
}

# The event the existing binding sends, or `fallback` for a Reedline default.
def existing-event [index: record, modifier: string, keycode: string, fallback: any]: nothing -> any {
    let found = $index | lookup $modifier $keycode
    if $found == null { $fallback } else { $found.event }
}

# The event the existing binding sends, or the Reedline default for the key.
def previous-event [index: record, mode: string, modifier: string, keycode: string]: nothing -> any {
    let found = $index | lookup $modifier $keycode
    if $found == null { reedline-default $mode $modifier $keycode } else { $found.event }
}

# The definition of `AUTO_MENU`, given the definition of `MENU`: the same menu
# with its selected entry styled like the others, so nothing looks selected.
export def auto-menu []: record -> record {
    let menu = $in
    let style = $menu.style? | default {}
    let text = $style.text? | default default
    $menu | upsert name $AUTO_MENU | upsert style ($style | upsert selected_text $text | upsert selected_match_text ($style.match_text? | default $text))
}

# Event for a trigger key: insert the char once, then open the menu.
#
# `menu` is a no-op (Inapplicable) while a menu is already open, so it never
# cycles the selection; the insert itself makes Reedline refilter an open
# menu. The plain `edit` fallback keeps typing working in history-search mode
# (Ctrl+Q), where a `Multiple` event is ignored but `until` is honored.
export def trigger-event [char: string]: nothing -> record {
    let insert = {edit: insertchar, value: $char}
    {until: [[$insert {send: menu, name: $MENU}] $insert]}
}

# Event that drops the selection mark. Moving right until NUL never finds the
# char, so the cursor stays; the motion only collapses the selection, and is
# therefore Handled exactly when the line was marked.
export def unmark-event []: nothing -> record {
    {edit: moverightuntil, value: (char nul)}
}

# Event that marks an unmarked line as "a candidate is selected" without
# moving the cursor, so the completion (computed from the text before the
# cursor) does not change: it selects the grapheme before the cursor, or the
# one after it at the start of the line. Inapplicable on an empty line.
export def mark-event []: nothing -> record {
    {until: [
        [{edit: moveleft, select: true} {edit: swapcursorandanchor}]
        [{edit: moveright} {edit: moveleft, select: true}]
    ]}
}

# Reedline has no "run B only if A was handled" (see docs/evaluation.md), so
# the events below branch on the mark: `{until: [unmark X]}` runs X only on an
# unmarked line and drops the mark otherwise. An event that must act only on
# a line that was marked first sets the mark on the other branch, then tests
# again.
#
# Every cursor edit made while a menu is open makes the menu refilter and
# select its first entry, so a menu move is never followed by an edit.

# Event for a trigger key in a mark mode: insert the char once and show the
# unselected menu. On an unmarked line the char is inserted and the mark set
# and dropped again (the open `AUTO_MENU` refilters); on a marked line the
# mark is dropped and the selected candidate accepted (or, with no menu open,
# nothing done) before the insert. Either way `AUTO_MENU` then opens unless a
# menu is still open.
export def mark-trigger-event [char: string]: nothing -> record {
    let insert = {edit: insertchar, value: $char}
    let unmark = unmark-event
    {until: [
        [
            {until: [$unmark [$insert (mark-event)]]}
            {until: [$unmark [{until: [{send: menuaccept} {send: esc}]} $insert]]}
            {send: menu, name: $AUTO_MENU}
        ]
        $insert
    ]}
}

# Event for a key that moves through the menu in a mark mode (`nav` is
# `menunext` or `menuprevious`). On a marked line `MENU` is open: the swap
# keeps the mark (reversed), `menu` is Inapplicable, and the swap back runs
# before the move. On an unmarked line the open menu (if any) is closed, the
# line marked, and `MENU` opened on its first entry. A lone candidate that
# the move accepts closes `MENU`, so `AUTO_MENU` opens for the completed line.
# Opening `MENU` and moving back in the same event closes the menu again, so
# Shift+Tab also starts on the first entry. In history-search mode the
# `Multiple` is ignored and `previous` runs.
export def nav-event [nav: record, previous: any]: nothing -> record {
    let swap = {edit: swapcursorandanchor}
    {until: [
        [
            {until: [$swap [{send: esc} (mark-event)]]}
            {until: [{send: menu, name: $MENU} [$swap $nav]]}
            {send: menu, name: $AUTO_MENU}
        ]
        $previous
    ]}
}

# Event for Enter in a mark mode: on a marked line accept the selected
# candidate and show the unselected menu for the completed line; otherwise
# close the menu and do what Enter did before (normally: run the typed line).
#
# `menuaccept` drops the mark along with the replaced text. A marked line
# with no menu runs `previous` too.
export def enter-event [previous: any]: nothing -> record {
    {until: [
        [
            {until: [(unmark-event) [{send: esc} $previous]]}
            {until: [{send: menuaccept} $previous]}
            {send: menu, name: $AUTO_MENU}
        ]
        $previous
    ]}
}

# Event for an accept key in a mark mode: on a marked line accept the
# selected candidate and show the unselected menu for the completed line;
# otherwise do what the key did before.
#
# The first step flips the mark, so the accept runs only on a line that was
# marked; it marks the line again, so the last step runs `previous` only on a
# line that was not. The copy-until-NUL is an applied no-op edit: with
# `persistent_menus` off it closes a menu left open on an empty line. It also
# collapses a selection, so `--keep-selection` (for a `previous` that can
# select) leaves it out.
export def mark-accept-event [previous: any, --keep-selection]: nothing -> record {
    let unmark = unmark-event
    let steps = [
        {until: [$unmark (mark-event)]}
        {until: [$unmark [{send: menuaccept} {send: menu, name: $AUTO_MENU} (mark-event)]]}
        {until: [$unmark $previous]}
    ]
    {until: [(if $keep_selection { $steps } else { $steps | append {edit: copyrightuntil, value: (char nul)} }) $previous]}
}

# Event for Backspace in a mark mode: on an unmarked line do what Backspace
# did before (the open `AUTO_MENU` refilters); on a marked line close the
# selecting menu first and show the unselected one. `previous` runs once:
# the first step runs it only without a mark and marks the line afterwards,
# the second only on a line that was marked. The copy-until-NUL closes a
# menu left open on an empty line (see `mark-accept-event`).
export def backspace-event [previous: any]: nothing -> record {
    let unmark = unmark-event
    {until: [
        [
            {until: [$unmark [$previous (mark-event)]]}
            {until: [$unmark [{send: esc} $previous {send: menu, name: $AUTO_MENU}]]}
            {edit: copyrightuntil, value: (char nul)}
        ]
        $previous
    ]}
}

# Event for an accept key: accept the highlighted candidate and reopen the
# menu for the completed line, or do what the key did before.
#
# Reedline cannot run an event only if the previous one was handled, so the
# key marks the no-accept path in the editor instead: after `previous` it
# selects one grapheme next to the cursor. `swapcursorandanchor` is
# inapplicable without a selection, so `menu` only runs when `menuaccept`
# took the key. The copy-until-NUL never finds a char, so it copies nothing
# and only drops the selection, leaving the cursor where `previous` put it; on
# an empty line, where nothing can be selected, it also closes the menu that
# `menu` opened (with `persistent_menus` off, Reedline closes a menu when an
# edit leaves the line empty). In history-search mode the `Multiple` is
# ignored and the bare event runs.
export def accept-event [previous: any]: nothing -> record {
    let mark = {until: [{edit: moveright, select: true} {edit: moveleft, select: true}]}
    {until: [
        [
            {until: [{send: menuaccept} [$previous $mark]]}
            {until: [{edit: swapcursorandanchor} {send: menu, name: $MENU}]}
            {edit: copyrightuntil, value: (char nul)}
        ]
        $previous
    ]}
}

# Whether an event can leave a selection, which the mark in `accept-event`
# would collapse (e.g. Shift+Right's `moveright` with `select: true`).
def can-select []: any -> bool {
    let event = $in
    let type = $event | describe
    if ($type | str starts-with "record") {
        ($event.select? == true) or ($event.edit? in [selectall selectline swapcursorandanchor]) or ($event.until? != null and ($event.until | can-select))
    } else if ($type | str starts-with "list") or ($type | str starts-with "table") {
        $event | any {|e| $e | can-select }
    } else {
        false
    }
}

# Keybindings that make the auto-opened menu usable. Each one only changes
# behavior while a menu is open and otherwise falls back to the binding that
# was in effect before (a user binding, or the Reedline/Nushell default).
#
# `index` is the key-index of the existing bindings in `mode`; `accept` lists
# the parsed accept keys. In a mark mode (see `MARK_MODES`) see the `mark-*`
# events above; Enter always accepts a selected candidate there, so `enter`
# as an accept key changes nothing. Elsewhere each accept key accepts the
# highlighted candidate while a menu has candidates and then reopens the
# menu, except Enter (a reopened menu would make the next Enter accept again
# instead of running the line) and keys whose previous event can select.
def control-bindings [index: record, mode: string, accept: list]: nothing -> list<record> {
    let mark = $mode in $MARK_MODES
    let enter = existing-event $index none enter {send: enter}
    let tab = existing-event $index none tab {send: none}
    let left = existing-event $index none left {send: left}
    let menu = {send: menu, name: $MENU}
    # Closes the menu (dropping the mark in a mark mode), then runs `previous`.
    let close = {|previous| if $mark { [{send: esc} (unmark-event) $previous] } else { [{send: esc} $previous] } }
    let is_enter = {|k| (normalize-modifier $k.modifier) == none and (normalize-keycode $k.keycode) == enter }
    let is_accept = {|keycode| $accept | any {|k| (normalize-modifier $k.modifier) == none and (normalize-keycode $k.keycode) == $keycode } }
    let accepts = $accept | where {|k| not ($mark and (do $is_enter $k)) } | each {|k|
        let mod = normalize-modifier $k.modifier
        let id = if $mod == none { $k.keycode } else { $"($mod)_($k.keycode)" }
        let previous = previous-event $index $mode $k.modifier $k.keycode
        let event = if $mark {
            if ($previous | can-select) { mark-accept-event $previous --keep-selection } else { mark-accept-event $previous }
        } else if (do $is_enter $k) or ($previous | can-select) {
            {until: [{send: menuaccept} $previous]}
        } else {
            accept-event $previous
        }
        {id: $id, modifier: $k.modifier, keycode: $k.keycode, event: $event}
    }
    # Enter closes the menu without accepting the highlighted candidate and
    # then does what Enter did before (normally: run the typed line), unless
    # it is an accept key (outside a mark mode) or a candidate was selected
    # (in a mark mode). In history-search mode the `Multiple` is ignored and
    # the bare event runs.
    let enter_binding = if $mark {
        [{id: enter, modifier: none, keycode: enter, event: (enter-event $enter)}]
    } else if (do $is_accept enter) { [] } else {
        [{id: enter, modifier: none, keycode: enter, event: {until: [[{send: esc} $enter] $enter]}}]
    }
    # Unless Right is an accept key, Right closes the menu and does what it did
    # before, like Left: Reedline's default Right is swallowed by an open IDE
    # menu (`MenuRight`).
    let right_binding = if (do $is_accept right) { [] } else {
        let right = previous-event $index $mode none right
        [{id: right, modifier: none, keycode: right, event: {until: [(do $close $right) $right]}}]
    }
    # In a mark mode Tab, Shift+Tab, Ctrl+N and Ctrl+P select candidates, Esc
    # closes the menu and drops the mark, and Backspace shows the unselected
    # menu again. Up and Down keep their previous bindings: with no menu open
    # they walk the history, and the menu could only be told apart from no
    # menu by an event with side effects (Esc is Handled either way, and any
    # applied cursor edit ends Reedline's history traversal). They still move
    # through an open menu and keep an existing mark.
    let mark_bindings = if not $mark { [] } else {
        let backtab = previous-event $index $mode shift backtab
        let esc = previous-event $index $mode none esc
        let backspace = previous-event $index $mode none backspace
        let ctrl_nav = $NAV_CTRL_KEYS | items {|key, nav|
            let previous = previous-event $index $mode control $"char_($key)"
            {id: $"control_char_($key)", modifier: control, keycode: $"char_($key)", event: (nav-event {send: $nav} $previous)}
        }
        [
            {id: tab, modifier: none, keycode: tab, event: (nav-event {send: menunext} $tab)}
            {id: backtab, modifier: shift, keycode: backtab, event: (nav-event {send: menuprevious} $backtab)}
            {id: esc, modifier: none, keycode: esc, event: {until: [[$esc (unmark-event)] $esc]}}
            {id: backspace, modifier: none, keycode: backspace, event: (backspace-event $backspace)}
        ] ++ $ctrl_nav
    }
    # Outside a mark mode Tab moves to the next candidate while a menu is
    # open, otherwise does what it did before (Nushell's default opens
    # completion_menu). A lone candidate is accepted by `menunext`, which
    # closes the menu; the trailing `menu` then reopens it for the completed
    # line (e.g. a directory's contents). It is a no-op while any menu is
    # still open, including one the previous Tab binding opened. In
    # history-search mode the `Multiple` is ignored and the bare event runs.
    let tab_binding = if $mark { [] } else {
        [{id: tab, modifier: none, keycode: tab, event: {until: [[{until: [{send: menunext} $tab]} $menu] $tab]}}]
    }
    $enter_binding ++ $right_binding ++ $mark_bindings ++ $tab_binding ++ [
        # Left closes the menu and moves the cursor (an open IDE menu otherwise
        # swallows Left).
        {id: left, modifier: none, keycode: left, event: {until: [(do $close $left) $left]}}
    ] ++ $accepts
}

# All keybinding entries for a trigger set, given the current keybindings.
#
# Trigger keys that already have a (non nu-autocomplete) binding in a mode are
# left alone and reported in `skipped`, so user bindings keep working.
export def generate [trigger: string, existing: list, accept_keys: list<string> = $DEFAULT_ACCEPT_KEYS]: nothing -> record<bindings: list, skipped: list> {
    let accept = parse-accept-keys $accept_keys
    let keys = trigger-keys $trigger
    let per_mode = $MODES | each {|mode|
        let index = $existing | key-index $mode
        let triggers = $keys | each {|k| {key: $k, taken: ($k.key in $index)} }
        let bound = $triggers | where not taken | each {|t|
            {
                name: $"($NAME_PREFIX)($mode)_($t.key.id)"
                modifier: $t.key.modifier
                keycode: $t.key.keycode
                mode: $mode
                event: (if $mode in $MARK_MODES { mark-trigger-event $t.key.char } else { trigger-event $t.key.char })
            }
        }
        let controls = control-bindings $index $mode $accept | each {|c|
            {name: $"($NAME_PREFIX)($mode)_($c.id)", modifier: $c.modifier, keycode: $c.keycode, mode: $mode, event: $c.event}
        }
        let skipped = $triggers | where taken | each {|t| {mode: $mode, modifier: $t.key.modifier, keycode: $t.key.keycode} }
        {bindings: ($bound ++ $controls), skipped: $skipped}
    }
    {
        bindings: ($per_mode | get bindings | flatten)
        skipped: ($per_mode | get skipped | flatten)
    }
}
