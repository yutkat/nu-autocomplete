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

Clone the repository, then add to your `config.nu`:

```nu
use /path/to/nu-autocomplete/nu-autocomplete
nu-autocomplete enable
```

`use` alone changes nothing. To try it without your own configuration:

```sh
nu --config examples/minimal-config.nu
```

## Usage

```nu
nu-autocomplete enable                               # letters, digits, ASCII symbols and Space open the menu
nu-autocomplete enable --trigger space               # only Space opens the menu
nu-autocomplete enable --accept-keys [right ctrl+y]  # choose the keys that accept a candidate
nu-autocomplete status                               # current state, accept keys, skipped keys
nu-autocomplete disable                              # remove the keybindings and restore settings
```

Running `enable` again replaces the previous installation without duplicates.
`enable` sets `completions.quick`, `completions.partial` and
`completions.persistent_menus` to `false`; `disable` restores them unless you
changed them in the meantime.

## Keys

| Key                      | Menu open                                                | Menu closed              |
| ------------------------ | -------------------------------------------------------- | ------------------------ |
| Letters, digits, symbols | insert and refilter                                      | insert and open the menu |
| Tab / Shift+Tab          | next / previous candidate (a lone candidate is accepted) | your previous binding    |
| **Ctrl+Y**               | **accept the highlighted candidate**                     | your previous binding    |
| **Enter**                | **close the menu and run the line as typed**             | run the line             |
| Esc                      | close the menu, keep the input                           | unchanged                |
| Backspace                | delete and refilter; closes on an empty line             | unchanged                |
| Left / Right             | close the menu and move left / right                     | unchanged                |
| Up / Down                | move in the menu                                         | unchanged (history)      |

After a candidate is accepted, the menu reopens for the completed line, so
`nvim nu` + Tab gives `nvim nu-autocomplete/` and lists that directory.
Keybindings you already have on trigger keys are kept and listed in
`status | get skipped_keys`; the other keys above fall back to your own
binding whenever no menu is open.

### Why Enter does not accept

The IDE menu always highlights its first entry, and a keybinding cannot tell
whether you moved the selection. If Enter accepted, `l` + Enter would turn into
`last`. So Enter always runs what you typed; use Ctrl+Y to accept.
This also applies to the Ctrl+R history menu.

### Accept keys

`--accept-keys` replaces the default `[ctrl+y]`:

```nu
nu-autocomplete enable --accept-keys [right ctrl+y]  # Right accepts too (instead of moving)
nu-autocomplete enable --accept-keys [alt+l]         # Ctrl+Y keeps its usual job (paste)
nu-autocomplete enable --accept-keys [enter]         # IDE-like Enter: press Esc first to run as typed
```

Keys are written as `[modifier+]key` (`ctrl`, `alt`, `shift`, `super`; e.g.
`ctrl+y`, `alt+l`, `f5`, `enter`). Keys the menu already uses (`tab`, `esc`,
`left`, `up`, ...) and plain characters are rejected. An accept key only
accepts while a menu is open; otherwise it keeps its previous behavior.

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
  break:

  ```nu
  $env.config.menus = $env.config.menus | each {|m|
      if $m.name == "ide_completion_menu" { $m | upsert marker "\n❯ " } else { $m }
  }
  ```

- When the typed word stops matching, the menu stays open showing
  `NO RECORDS FOUND`.
- While a menu is open, Up/Down move in the menu instead of browsing history.
- While a slow completer runs, the previous candidates stay visible until the
  new ones arrive (they cannot be accepted).
- In Emacs mode, Ctrl+Y accepts instead of pasting while the menu is open;
  press Esc first.

## Development

```sh
nu tests/run.nu
```
