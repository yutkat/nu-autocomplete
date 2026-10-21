# nu-autocomplete

IDE-style automatic completion menus for Nushell.

nu-autocomplete opens Nushell's IDE completion menu (`ide_completion_menu`)
while you type, similar to zsh-autocomplete. It is a plain Nushell module that
only installs keybindings and adjusts a few completion settings; fetching
candidates, background completion and drawing are left to Nushell and
Reedline.

Command completion:

<img width="565" height="205" alt="Command completion menu opening while typing" src="https://github.com/user-attachments/assets/d46ca685-62bd-4842-a22e-66e909f60b48" />

Argument completion with [Carapace](examples/carapace-config.nu):

<img width="447" height="244" alt="Argument completion menu from Carapace" src="https://github.com/user-attachments/assets/f9a4ff6c-4a90-4018-a05d-8a573db0e815" />

## Requirements

- The latest Nushell release (0.116.0 or newer is required for background
  completion)
- Linux; tested in WezTerm

## Install

Clone the repository:

```sh
git clone https://github.com/yutkat/nu-autocomplete.git /path/to/nu-autocomplete
```

then add to your `config.nu`:

```nu
use /path/to/nu-autocomplete/nu-autocomplete
nu-autocomplete enable
```

Or install it with [nupm](https://github.com/nushell/nupm) from the clone
(`$env.NUPM_HOME/modules` must be in `$env.NU_LIB_DIRS`):

```nu
nupm install /path/to/nu-autocomplete --path
```

and add to your `config.nu`:

```nu
use nu-autocomplete
nu-autocomplete enable
```

`use` alone changes nothing. To try it without your own configuration:

```sh
XDG_CONFIG_HOME=$(mktemp -d) nu --config examples/minimal-config.nu
```

## Usage

```nu
nu-autocomplete enable                               # letters, digits, ASCII symbols and Space open the menu
nu-autocomplete enable --trigger space               # only Space opens the menu
nu-autocomplete enable --accept-keys [enter ctrl+y]  # choose the keys that accept a candidate
nu-autocomplete status                               # current state, accept keys, skipped keys
nu-autocomplete disable                              # remove the keybindings and restore settings
```

Running `enable` again replaces the previous installation without duplicates.
`enable` sets `completions.quick`, `completions.partial` and
`completions.persistent_menus` to `false` and `color_config.selection` to
`{attr: n}`; `disable` restores them unless you changed them in the meantime.

To keep shell startup fast, `enable` caches the keybindings it generates in
`$nu.cache-dir/nu-autocomplete`. The cache is rebuilt automatically when its
inputs change (nu-autocomplete or Nushell version, `enable` options, your other
keybindings), and `enable` works without it if it cannot be read or written.
Deleting the directory is always safe.

## Keys

| Key                | Menu open, nothing selected                  | Candidate selected                                 | Menu closed                          |
| ------------------ | -------------------------------------------- | -------------------------------------------------- | ------------------------------------ |
| Typing             | edit and refilter                            | accept the candidate, then type; nothing selected  | typing opens the menu                |
| Backspace          | edit and refilter                            | edit; back to nothing selected                     | your previous binding                |
| Tab / Ctrl+N       | select the first candidate                   | select the next one (a lone candidate is accepted) | open the menu on the first candidate |
| Shift+Tab / Ctrl+P | select the first candidate                   | select the previous one                            | open the menu on the first candidate |
| **Enter**          | **close the menu and run the line as typed** | **accept the candidate**                           | run the line                         |
| **Ctrl+Y**         | your previous binding (Emacs: paste)         | **accept the candidate**                           | your previous binding                |
| Esc                | close the menu, keep the input               | close the menu, keep the input                     | unchanged                            |

This is Emacs mode; see [Vi insert mode](#vi-insert-mode) for the
differences there. After a candidate is accepted, the menu reopens for the
completed line with nothing selected, so `nvim nu` + Tab + Enter gives
`nvim nu-autocomplete/` and lists that directory; another Enter runs the line.
Keybindings you already have on trigger keys are kept and listed in
`status | get skipped_keys`; the other keys above fall back to your own
binding whenever no menu is open. Left / Right close the menu and move the
cursor.

### How "nothing selected" works

Reedline's IDE menu always highlights its first entry and has no unselected
state. `enable` therefore defines a second menu, `nu_autocomplete_menu`: a
copy of your `ide_completion_menu` whose selected entry is styled like the
others. Typing opens that menu, so nothing looks selected. Tab, Shift+Tab,
Ctrl+N and Ctrl+P switch to `ide_completion_menu`, which shows the selection.

Keybindings cannot ask which menu is open, so the selecting keys also mark
the line with the line editor's selection, and Enter and Ctrl+Y accept only on
a marked line. The mark covers the character before the cursor (after it, at
the start of the line) and is drawn with `color_config.selection`, which
`enable` sets to `{attr: n}` so the mark is invisible. This also hides other
selections in the line editor, such as Shift+Left/Right. To see them again,
set the style after `enable`; the mark then shows too:

```nu
nu-autocomplete enable
$env.config.color_config.selection = {attr: r}
```

Changes to `ide_completion_menu` made after `enable` reach
`nu_autocomplete_menu` only when `enable` runs again. Nushell cannot remove a
menu, so `disable` leaves `nu_autocomplete_menu` defined but unused.

### Vi insert mode

Vi's Esc switches to normal mode without going through keybindings, so it
could not drop the mark, and a leftover selection would change what
normal-mode commands act on. Vi insert mode therefore keeps the plain IDE
menu: its first entry is highlighted, Tab / Shift+Tab move, Ctrl+Y accepts the
highlighted candidate, Enter runs the line as typed, and Ctrl+N / Ctrl+P /
Backspace keep their previous bindings.

### Accept keys

`--accept-keys` replaces the default `[ctrl+y]`. Enter always accepts a
selected candidate in Emacs mode; the accept keys work the same way.

```nu
nu-autocomplete enable --accept-keys [enter ctrl+y]  # Vi insert: Enter accepts the highlighted candidate too
nu-autocomplete enable --accept-keys [alt+l]         # Ctrl+Y keeps its usual job (paste)
```

Keys are written as `[modifier+]key` (`ctrl`, `alt`, `shift`, `super`; e.g.
`ctrl+y`, `alt+l`, `f5`, `enter`). Keys the menu already uses (`tab`, `esc`,
`left`, `up`, `ctrl+n`, ...) and plain characters are rejected. An accept key
only accepts a selected candidate; otherwise it keeps its previous behavior.

## Known issues

- Nushell does not complete arguments of external commands by itself.
  [examples/carapace-config.nu](examples/carapace-config.nu) sets up
  [Carapace](https://carapace.sh) for that (`git switch`, `git --`,
  `nvim --`, ...) without replacing an external completer you already have.
  Verified with Carapace 1.8.0.
- `@interactive` completers (for example fzf pickers) take over the terminal;
  combining them with auto-triggering is not supported.
- If your prompt keeps its line break in `PROMPT_INDICATOR`, the prompt
  collapses to one line while the menu is open, because Reedline draws the
  menu's `marker` in its place. Give the menu a marker with the same line
  break, before `nu-autocomplete enable` (which copies it):

  ```nu
  $env.config.menus = $env.config.menus | each {|m|
      if $m.name == "ide_completion_menu" { $m | upsert marker "\n❯ " } else { $m }
  }
  ```

- When the typed word stops matching, the menu stays open showing
  `NO RECORDS FOUND`.
- While a menu is open, Up/Down move in the menu instead of browsing history.
  With nothing selected that move is invisible and Enter still runs the line;
  use Tab or Ctrl+N to select.
- In Emacs mode, Ctrl+N and Ctrl+P select candidates instead of browsing
  history, also on an empty line (use Up/Down for history). Tab, Ctrl+N and
  friends on an empty line show the command list but cannot select in it
  (there is nothing to mark); type a character first.
- In the Ctrl+R history menu, Enter runs the current line instead of picking
  the entry, and Tab switches to the completion menu. Right picks the entry.
  To keep Enter, bind Ctrl+R to a history picker instead of the menu; Enter
  then inserts the chosen line without running it (this reads a plaintext
  history file):

  ```nu
  $env.config.keybindings ++= [{
      name: history_pick
      modifier: control
      keycode: char_r
      mode: [emacs vi_insert]
      event: {
          send: executehostcommand
          cmd: "commandline edit --replace (open $nu.history-path | lines | reverse | uniq | input list --fuzzy)"
      }
  }]
  ```

- While a slow completer runs, the previous candidates stay visible until the
  new ones arrive (they cannot be accepted).
- Typing while a candidate is selected accepts it as Nushell completes it,
  so a candidate that already ends in a space or `/` gets a second one when
  that char is typed: `le` Tab Space gives `length  `, and `ls fo` Tab `/`
  gives `ls foo//`. Type the next word directly instead (`le` Tab `x` gives
  `length x`).
- In Emacs mode, while a candidate is selected, keys that nu-autocomplete does
  not bind act on the editor selection (for example Delete or a cut binding of
  yours acts on the marked character), and keys that only move the cursor
  (Home, End, Ctrl+A, ...) drop the mark but leave the selecting menu open, so
  its first entry looks selected while Enter runs the line. Press Esc to
  close it.

## Development

```sh
nu tests/run.nu
```
