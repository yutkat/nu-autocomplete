# Minimal config to try nu-autocomplete without any other customization:
#
#   nu --config examples/minimal-config.nu
#
# In your own config.nu, replace the path below with where you cloned the repo,
# or put the clone's parent directory in $env.NU_LIB_DIRS and `use nu-autocomplete`.

$env.config.show_banner = false

use ../nu-autocomplete
# Opens the menu after letters, digits, ASCII symbols and Space (`--trigger all`).
# Use `nu-autocomplete enable --trigger space` to open it only after Space.
nu-autocomplete enable
