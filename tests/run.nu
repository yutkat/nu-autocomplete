# Test entry point: `nu tests/run.nu`. Exits non-zero when a test fails.
#
# These tests exercise keybinding generation and enable/disable on
# `$env.config` in-process. Nushell only parses keybinding events when it
# builds the line editor, which does not happen here, so event validity needs
# an interactive session.

use std/assert

const ROOT = path self ..
use ($ROOT | path join nu-autocomplete)
use ($ROOT | path join nu-autocomplete keybindings.nu) *

def ours []: list -> list { where {|kb| $kb | is-ours } }

def kb-for [mode: string, modifier: string, keycode: string]: list -> list {
    where {|kb| $kb.mode == $mode and $kb.modifier == $modifier and $kb.keycode == $keycode }
}

def user-binding [name: string, modifier: string, keycode: string, mode: any, event: record]: nothing -> record {
    {name: $name, modifier: $modifier, keycode: $keycode, mode: $mode, event: $event}
}

# --- trigger keys -----------------------------------------------------------

def "test trigger keys cover printable ASCII" [] {
    let keys = trigger-keys all
    let chars = $keys | get char | uniq | sort
    let expected = 32..126 | each {|n| char --integer $n } | sort
    assert equal $chars $expected
    # 26 lower + 26 upper + 10 digits + 32 symbols * 2 + space * 2
    assert equal ($keys | length) 128
    assert equal ($keys | get id | uniq | length) ($keys | length) "ids are unique"
}

def "test uppercase letters are bound as shift plus lowercase keycode" [] {
    let keys = trigger-keys all
    let a = $keys | where char == "A"
    assert equal ($a | length) 1
    assert equal $a.0.modifier shift
    assert equal $a.0.keycode char_a
    # A plain `none` binding for an uppercase char would never match a keypress.
    assert equal ($keys | where modifier == none and char =~ '^[A-Z]$' | length) 0
}

def "test symbols are bound with and without shift" [] {
    let keys = trigger-keys all
    for c in ["!" "_" "~" "/" "-" "'" '"' "\\" "|"] {
        let mods = $keys | where char == $c | get modifier | sort
        assert equal $mods [none shift] $"modifiers for ($c)"
    }
}

def "test space trigger set only binds space" [] {
    let keys = trigger-keys space
    assert equal ($keys | get char | uniq) [" "]
    assert equal ($keys | get modifier | sort) [none shift]
}

def "test unknown trigger set is rejected" [] {
    assert error { trigger-keys nope }
}

def "test keycode normalization" [] {
    assert equal (normalize-keycode char_u21) (normalize-keycode "char_!")
    assert equal (normalize-keycode char_A) (normalize-keycode char_a)
    assert equal (normalize-keycode space) (normalize-keycode "char_ ")
    assert equal (normalize-keycode Enter) enter
    assert equal (normalize-modifier Shift_Control) (normalize-modifier control_shift)
    assert equal (normalize-modifier None) none
}

# --- generation -------------------------------------------------------------

def "test trigger event inserts once then opens the menu" [] {
    let event = trigger-event "x"
    let insert = {edit: insertchar, value: "x"}
    assert equal $event {until: [[$insert {send: menu, name: ide_completion_menu}] $insert]}
}

def "test accept event reopens the menu only after an accept" [] {
    let prev = {send: right}
    let mark = {until: [{edit: moveright, select: true} {edit: moveleft, select: true}]}
    assert equal (accept-event $prev) {until: [
        [
            {until: [{send: menuaccept} [$prev $mark]]}
            {until: [{edit: swapcursorandanchor} {send: menu, name: ide_completion_menu}]}
            {edit: copyrightuntil, value: (char nul)}
        ]
        $prev
    ]}
}

def "test generated bindings are named, scoped to emacs and vi insert" [] {
    let gen = generate all []
    let b = $gen.bindings
    assert ($b | all {|kb| $kb | is-ours })
    assert equal ($b | get mode | uniq | sort) [emacs vi_insert]
    assert equal ($b | get name | uniq | length) ($b | length) "names are unique"
    # 128 trigger keys + enter/tab/right/ctrl_y/left, per mode
    assert equal ($b | length) (2 * (128 + 5))
    assert equal $gen.skipped []
}

def "test generated uppercase binding inserts the uppercase char" [] {
    let b = generate all [] | get bindings | kb-for emacs shift char_a
    assert equal ($b | length) 1
    assert equal $b.0.event (trigger-event "A")
}

def "test trigger keys already bound by the user are skipped" [] {
    let user = [(user-binding my_bang none "char_!" emacs {edit: insertstring, value: "!!"})]
    let gen = generate all $user
    assert equal ($gen.bindings | kb-for emacs none "char_u21" | length) 0
    assert equal ($gen.bindings | kb-for vi_insert none "char_u21" | length) 1
    assert equal $gen.skipped [{mode: emacs, modifier: none, keycode: "char_u21"}]
}

def "test control keys chain to the existing binding" [] {
    let my_enter = {send: submitornewline}
    let user = [(user-binding my_enter none enter [emacs vi_insert] $my_enter)]
    let gen = generate all $user
    let enter = $gen.bindings | kb-for emacs none enter
    assert equal $enter.0.event {until: [[{send: esc} $my_enter] $my_enter]}
    # Tab falls back to Nushell's default Tab binding when the menu is closed,
    # then reopens the IDE menu (after a lone candidate was accepted).
    let default_tab = $env.config.keybindings | where name == completion_menu | get 0.event
    let tab = generate all $env.config.keybindings | get bindings | kb-for emacs none tab
    let reopen = {send: menu, name: ide_completion_menu}
    assert equal $tab.0.event {until: [[{until: [{send: menunext} $default_tab]} $reopen] $default_tab]}
}

def "test control keys fall back to reedline defaults" [] {
    let b = generate space [] | get bindings
    assert equal ($b | kb-for emacs none enter | get 0.event) {until: [[{send: esc} {send: enter}] {send: enter}]}
    assert equal ($b | kb-for emacs none tab | get 0.event) {until: [[{until: [{send: menunext} {send: none}]} {send: menu, name: ide_completion_menu}] {send: none}]}
    assert equal ($b | kb-for emacs none right | get 0.event) (accept-event {until: [{send: historyhintcomplete} {send: right}]})
    assert equal ($b | kb-for emacs none left | get 0.event) {until: [[{send: esc} {send: left}] {send: left}]}
    assert equal ($b | kb-for emacs control char_y | get 0.event) (accept-event {edit: pastecutbufferbefore})
    assert equal ($b | kb-for vi_insert control char_y | get 0.event) (accept-event {send: none})
}

def "test trigger key lookup keys are normalized" [] {
    for k in (trigger-keys all) {
        assert equal $k.key $"(normalize-modifier $k.modifier) (normalize-keycode $k.keycode)" $k.id
    }
}

def "test the last matching existing binding wins" [] {
    let user = [
        (user-binding first Control char_A emacs {send: up})
        (user-binding last control_none char_u61 [emacs vi_insert] {send: down})
        (user-binding normal control char_a vi_normal {send: left})
        (user-binding nu_autocomplete_emacs_control_a control char_a emacs {send: right})
    ]
    assert equal ($user | find-existing emacs control char_a | get name) last
    assert equal ($user | find-existing vi_insert Control char_A | get name) last
    assert equal ($user | first 1 | find-existing vi_insert control char_a) null
    assert equal ($user | find-existing emacs none char_a) null
}

def "test ctrl y chains to the existing binding" [] {
    let my_y = {edit: insertstring, value: "yy"}
    let user = [(user-binding my_y Control char_Y vi_insert $my_y)]
    let b = generate space $user | get bindings
    assert equal ($b | kb-for vi_insert control char_y | get 0.event) (accept-event $my_y)
    assert equal ($b | kb-for emacs control char_y | get 0.event) (accept-event {edit: pastecutbufferbefore})
}

def "test accept key specs parse to modifier and keycode" [] {
    assert equal (parse-key-spec right) {modifier: none, keycode: right}
    assert equal (parse-key-spec ctrl+y) {modifier: control, keycode: char_y}
    assert equal (parse-key-spec CONTROL+Y) {modifier: control, keycode: char_y}
    assert equal (parse-key-spec alt+l) {modifier: alt, keycode: char_l}
    assert equal (parse-key-spec shift+ctrl+right) {modifier: control_shift, keycode: right}
    assert equal (parse-key-spec "ctrl+,") {modifier: control, keycode: char_u2c}
    assert equal (parse-key-spec ctrl++) {modifier: control, keycode: char_u2b}
    assert equal (parse-key-spec enter) {modifier: none, keycode: enter}
    assert equal (parse-key-spec F5) {modifier: none, keycode: f5}
    assert equal (parse-key-spec ctrl+tab) {modifier: control, keycode: tab}
}

def "test invalid accept key specs are rejected" [] {
    for spec in [tab backtab esc backspace left up down a A shift+a "1" "/" space shift+space ctrl+alt+x hyper+x ctrl+foo f36 ""] {
        let msg = try { parse-key-spec $spec; null } catch {|e| $e.msg }
        assert ($msg != null) $"accepted invalid spec '($spec)'"
        assert ($msg | str starts-with "invalid accept key") $msg
    }
}

def "test duplicate accept keys are dropped" [] {
    assert equal (parse-accept-keys [ctrl+y control+Y right]) [{modifier: control, keycode: char_y} {modifier: none, keycode: right}]
}

def "test default accept keys are right and ctrl y" [] {
    assert equal $DEFAULT_ACCEPT_KEYS [right ctrl+y]
    let b = generate space [] | get bindings
    let right = {until: [{send: historyhintcomplete} {send: right}]}
    assert equal ($b | kb-for emacs none right | get 0.event) (accept-event $right)
    assert equal ($b | kb-for emacs control char_y | get 0.event) (accept-event {edit: pastecutbufferbefore})
}

def "test enter as accept key accepts instead of closing" [] {
    let b = generate space [] [enter] | get bindings
    assert equal ($b | kb-for emacs none enter | get 0.event) {until: [{send: menuaccept} {send: enter}]}
    # Vi insert has no Enter entry in Reedline's table but submits on Enter.
    assert equal ($b | kb-for vi_insert none enter | get 0.event) {until: [{send: menuaccept} {send: enter}]}
    assert equal ($b | kb-for emacs control char_y | length) 0
    # space trigger (2) + tab, left, right, enter
    assert equal ($b | where mode == emacs | length) 6
}

def "test right that is not an accept key closes the menu and moves" [] {
    let b = generate space [] [ctrl+y] | get bindings
    let right = {until: [{send: historyhintcomplete} {send: right}]}
    assert equal ($b | kb-for emacs none right | get 0.event) {until: [[{send: esc} $right] $right]}
    assert equal ($b | kb-for emacs none enter | get 0.event) {until: [[{send: esc} {send: enter}] {send: enter}]}
    let my_right = {send: right}
    let user = [(user-binding my_right none right emacs $my_right)]
    let b = generate space $user [ctrl+y] | get bindings
    assert equal ($b | kb-for emacs none right | get 0.event) {until: [[{send: esc} $my_right] $my_right]}
}

def "test accept keys chain to reedline defaults of any key" [] {
    let b = generate space [] [alt+enter ctrl+right f5] | get bindings
    assert equal ($b | kb-for emacs alt enter | get 0.event) (accept-event {edit: insertnewline})
    let word = {until: [{send: historyhintwordcomplete} {edit: movewordright, select: false}]}
    assert equal ($b | kb-for emacs control right | get 0.event) (accept-event $word)
    assert equal ($b | kb-for vi_insert none f5 | get 0.event) (accept-event {send: none})
}

def "test accept keys that select do not reopen the menu" [] {
    let b = generate space [] [shift+right] | get bindings
    assert equal ($b | kb-for emacs control_shift right | length) 0
    assert equal ($b | kb-for emacs shift right | get 0.event) {until: [{send: menuaccept} {edit: moveright, select: true}]}
    let my_y = [{edit: movewordleft, select: true} {send: repaint}]
    let user = [(user-binding my_y control char_y emacs {until: $my_y})]
    let b = generate space $user | get bindings
    assert equal ($b | kb-for emacs control char_y | get 0.event) {until: [{send: menuaccept} {until: $my_y}]}
}

def "test vi normal mode is never bound" [] {
    let b = generate all $env.config.keybindings | get bindings
    assert equal ($b | where mode != emacs and mode != vi_insert | length) 0
}

# --- enable / disable -------------------------------------------------------

def --env "test use alone does not change config" [] {
    # The module is already imported at the top of this file.
    assert equal ($env.config.keybindings | ours | length) 0
    assert equal (nu-autocomplete status | get enabled) false
}

def --env "test enable installs bindings and completion settings" [] {
    $env.config.completions.quick = true
    $env.config.completions.partial = true
    nu-autocomplete enable
    assert equal ($env.config.keybindings | ours | length) 266
    assert equal ($env.config.completions | select quick partial persistent_menus) {quick: false, partial: false, persistent_menus: false}
    let st = nu-autocomplete status
    assert equal $st.enabled true
    assert equal $st.trigger all
    assert equal $st.keybindings_by_mode {emacs: 133, vi_insert: 133}
}

def --env "test enable is idempotent" [] {
    nu-autocomplete enable
    let first = $env.config.keybindings
    nu-autocomplete enable
    assert equal $env.config.keybindings $first
    assert equal ($env.config.keybindings | ours | get name | uniq | length) ($env.config.keybindings | ours | length)
}

def --env "test enable with another trigger set replaces bindings" [] {
    nu-autocomplete enable
    nu-autocomplete enable --trigger space
    assert equal ($env.config.keybindings | ours | length) 14
    assert equal (nu-autocomplete status | get trigger) space
}

def --env "test enable with other accept keys replaces bindings" [] {
    nu-autocomplete enable --accept-keys [enter]
    assert equal (nu-autocomplete status | get accept_keys) [enter]
    assert equal (nu-autocomplete status | get keybindings_by_mode) {emacs: 132, vi_insert: 132}
    assert equal ($env.config.keybindings | ours | kb-for emacs none enter | get 0.event) {until: [{send: menuaccept} {send: enter}]}
    nu-autocomplete enable
    assert equal (nu-autocomplete status | get accept_keys) [right ctrl+y]
    assert equal ($env.config.keybindings | ours | length) 266
    assert equal ($env.config.keybindings | ours | get name | uniq | length) 266
    assert equal ($env.config.keybindings | ours | kb-for emacs none enter | get 0.event) {until: [[{send: esc} {send: enter}] {send: enter}]}
}

def --env "test enable rejects an invalid accept key without changes" [] {
    nu-autocomplete enable --accept-keys [enter]
    let before = $env.config
    let before_state = $env.__NU_AUTOCOMPLETE
    assert error { nu-autocomplete enable --accept-keys [right tab] }
    assert equal $env.config $before
    assert equal $env.__NU_AUTOCOMPLETE $before_state
}

def --env "test disable after custom accept keys restores keybindings" [] {
    $env.config.keybindings ++= [(user-binding my_y control char_y emacs {edit: insertstring, value: "y"})]
    let before = $env.config.keybindings
    nu-autocomplete enable --accept-keys [ctrl+y enter]
    nu-autocomplete enable --accept-keys [alt+l]
    nu-autocomplete disable
    assert equal $env.config.keybindings $before
}

def --env "test enable rejects an unknown trigger set" [] {
    let before = $env.config.keybindings
    assert error { nu-autocomplete enable --trigger letters }
    assert equal $env.config.keybindings $before
}

def --env "test disable restores keybindings and settings" [] {
    $env.config.keybindings ++= [(user-binding my_bang none "char_!" emacs {edit: insertstring, value: "!!"})]
    $env.config.completions.quick = true
    $env.config.completions.partial = false
    $env.config.completions.persistent_menus = true
    let before_kb = $env.config.keybindings
    let before_comp = $env.config.completions
    nu-autocomplete enable
    nu-autocomplete enable
    nu-autocomplete disable
    assert equal $env.config.keybindings $before_kb
    assert equal $env.config.completions $before_comp
    assert equal (nu-autocomplete status | get enabled) false
}

def --env "test disable keeps settings the user changed after enable" [] {
    $env.config.completions.quick = true
    $env.config.completions.partial = true
    nu-autocomplete enable
    # The user changes one setting we manage, and an unrelated one.
    $env.config.completions.partial = true
    $env.config.completions.case_sensitive = true
    nu-autocomplete disable
    assert equal $env.config.completions.quick true "restored: still had our value"
    assert equal $env.config.completions.partial true "kept: user changed it"
    assert equal $env.config.completions.case_sensitive true "unrelated setting untouched"
}

def --env "test disable keeps keybindings the user added after enable" [] {
    nu-autocomplete enable
    $env.config.keybindings ++= [(user-binding later none f5 emacs {send: clearscreen})]
    nu-autocomplete disable
    assert equal ($env.config.keybindings | ours | length) 0
    assert equal ($env.config.keybindings | where name == later | length) 1
}

def --env "test disable without enable is a no-op" [] {
    let before = $env.config
    nu-autocomplete disable
    assert equal $env.config $before
}

# --- runner -----------------------------------------------------------------

# Each test runs in its own closure, so `$env.config` changes do not leak
# between tests.
const TESTS = [
    "test trigger keys cover printable ASCII"
    "test uppercase letters are bound as shift plus lowercase keycode"
    "test symbols are bound with and without shift"
    "test space trigger set only binds space"
    "test unknown trigger set is rejected"
    "test keycode normalization"
    "test trigger event inserts once then opens the menu"
    "test accept event reopens the menu only after an accept"
    "test generated bindings are named, scoped to emacs and vi insert"
    "test generated uppercase binding inserts the uppercase char"
    "test trigger keys already bound by the user are skipped"
    "test control keys chain to the existing binding"
    "test control keys fall back to reedline defaults"
    "test trigger key lookup keys are normalized"
    "test the last matching existing binding wins"
    "test ctrl y chains to the existing binding"
    "test accept key specs parse to modifier and keycode"
    "test invalid accept key specs are rejected"
    "test duplicate accept keys are dropped"
    "test default accept keys are right and ctrl y"
    "test enter as accept key accepts instead of closing"
    "test right that is not an accept key closes the menu and moves"
    "test accept keys chain to reedline defaults of any key"
    "test accept keys that select do not reopen the menu"
    "test vi normal mode is never bound"
    "test use alone does not change config"
    "test enable installs bindings and completion settings"
    "test enable is idempotent"
    "test enable with another trigger set replaces bindings"
    "test enable with other accept keys replaces bindings"
    "test enable rejects an invalid accept key without changes"
    "test disable after custom accept keys restores keybindings"
    "test enable rejects an unknown trigger set"
    "test disable restores keybindings and settings"
    "test disable keeps settings the user changed after enable"
    "test disable keeps keybindings the user added after enable"
    "test disable without enable is a no-op"
]

def run-test [name: string]: nothing -> any {
    try {
        match $name {
            "test trigger keys cover printable ASCII" => { test trigger keys cover printable ASCII }
            "test uppercase letters are bound as shift plus lowercase keycode" => { test uppercase letters are bound as shift plus lowercase keycode }
            "test symbols are bound with and without shift" => { test symbols are bound with and without shift }
            "test space trigger set only binds space" => { test space trigger set only binds space }
            "test unknown trigger set is rejected" => { test unknown trigger set is rejected }
            "test keycode normalization" => { test keycode normalization }
            "test trigger event inserts once then opens the menu" => { test trigger event inserts once then opens the menu }
            "test accept event reopens the menu only after an accept" => { test accept event reopens the menu only after an accept }
            "test generated bindings are named, scoped to emacs and vi insert" => { test generated bindings are named, scoped to emacs and vi insert }
            "test generated uppercase binding inserts the uppercase char" => { test generated uppercase binding inserts the uppercase char }
            "test trigger keys already bound by the user are skipped" => { test trigger keys already bound by the user are skipped }
            "test control keys chain to the existing binding" => { test control keys chain to the existing binding }
            "test control keys fall back to reedline defaults" => { test control keys fall back to reedline defaults }
            "test trigger key lookup keys are normalized" => { test trigger key lookup keys are normalized }
            "test the last matching existing binding wins" => { test the last matching existing binding wins }
            "test ctrl y chains to the existing binding" => { test ctrl y chains to the existing binding }
            "test accept key specs parse to modifier and keycode" => { test accept key specs parse to modifier and keycode }
            "test invalid accept key specs are rejected" => { test invalid accept key specs are rejected }
            "test duplicate accept keys are dropped" => { test duplicate accept keys are dropped }
            "test default accept keys are right and ctrl y" => { test default accept keys are right and ctrl y }
            "test enter as accept key accepts instead of closing" => { test enter as accept key accepts instead of closing }
            "test right that is not an accept key closes the menu and moves" => { test right that is not an accept key closes the menu and moves }
            "test accept keys chain to reedline defaults of any key" => { test accept keys chain to reedline defaults of any key }
            "test accept keys that select do not reopen the menu" => { test accept keys that select do not reopen the menu }
            "test vi normal mode is never bound" => { test vi normal mode is never bound }
            "test use alone does not change config" => { test use alone does not change config }
            "test enable installs bindings and completion settings" => { test enable installs bindings and completion settings }
            "test enable is idempotent" => { test enable is idempotent }
            "test enable with another trigger set replaces bindings" => { test enable with another trigger set replaces bindings }
            "test enable with other accept keys replaces bindings" => { test enable with other accept keys replaces bindings }
            "test enable rejects an invalid accept key without changes" => { test enable rejects an invalid accept key without changes }
            "test disable after custom accept keys restores keybindings" => { test disable after custom accept keys restores keybindings }
            "test enable rejects an unknown trigger set" => { test enable rejects an unknown trigger set }
            "test disable restores keybindings and settings" => { test disable restores keybindings and settings }
            "test disable keeps settings the user changed after enable" => { test disable keeps settings the user changed after enable }
            "test disable keeps keybindings the user added after enable" => { test disable keeps keybindings the user added after enable }
            "test disable without enable is a no-op" => { test disable without enable is a no-op }
            _ => (error make {msg: $"no such test: ($name)"})
        }
        null
    } catch {|err| $err.msg }
}

def main [] {
    let results = $TESTS | each {|name| {name: $name, error: (do { run-test $name })} }
    for r in $results {
        if $r.error == null {
            print $"ok    ($r.name)"
        } else {
            print $"FAIL  ($r.name): ($r.error)"
        }
    }
    let failed = $results | where error != null | length
    print $"\n($results | length) tests, ($failed) failed"
    if $failed > 0 { exit 1 }
}
