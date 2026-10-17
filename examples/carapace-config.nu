# Optional Carapace integration for nu-autocomplete.
#
# Try it without touching your config:
#   nu --config examples/carapace-config.nu
# Or copy the parts you need into your own config.nu.
#
# Requires the `carapace` binary on PATH (https://carapace.sh). Without it this
# file only enables nu-autocomplete and leaves completions unchanged.
# Bridging to other shells' completers (e.g. `$env.CARAPACE_BRIDGES = 'zsh,fish,bash'`)
# is a Carapace setting; see its documentation.

# Based on https://www.nushell.sh/cookbook/external_completers.html
let carapace_completer = {|place|
    # CARAPACE_LENIENT avoids "ERR unknown shorthand flag" for unusual flags.
    let candidates = try {
        CARAPACE_LENIENT=1 carapace $place.command.0 nushell ...$place.command | from json
    } catch {
        null
    }
    # `null` falls back to Nushell's file completion; `[]` would show nothing.
    if ($candidates | is-empty) { null } else { $candidates }
}

# Opt-in and non-destructive: never replace an external completer that is
# already configured. To combine Carapace with your own completer, dispatch
# by `$place.command.0` as shown in the cookbook's "multiple completer" section.
if (which carapace | is-not-empty) and ($env.config.completions.external.completer == null) {
    $env.config.completions.external.enable = true
    $env.config.completions.external.completer = $carapace_completer
}

# Path is relative to this file; adjust it to where you cloned the repository,
# or put the clone's parent directory in $env.NU_LIB_DIRS and `use nu-autocomplete`.
# With auto-opening menus the completer runs on most keystrokes; Nushell runs it
# in a background worker, so a slow Carapace call does not block typing.
use ../nu-autocomplete
nu-autocomplete enable
