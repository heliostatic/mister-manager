# Completions for dotfiles secrets script

# Disable file completions
complete -c secrets -f

# Commands
complete -c secrets -n '__fish_use_subcommand' -a 'get' -d 'Get a secret (tries Keychain cache, then backend)'
complete -c secrets -n '__fish_use_subcommand' -a 'validate' -d 'Validate all secrets are accessible'
complete -c secrets -n '__fish_use_subcommand' -a 'cache-all' -d 'Cache all secrets to Keychain (macOS)'
complete -c secrets -n '__fish_use_subcommand' -a 'list' -d 'List available secrets'
complete -c secrets -n '__fish_use_subcommand' -a 'backends' -d 'Show supported backends and status'
complete -c secrets -n '__fish_use_subcommand' -a 'help' -d 'Show help'

# Options
complete -c secrets -s n -l dry-run -d 'Preview without making changes (for cache-all)'
complete -c secrets -l skip-validate -d 'Skip item validation before caching'
complete -c secrets -s h -l help -d 'Show help'

# Secret name completion for 'get' subcommand
# Dynamically list secrets from the secrets script (requires secrets in PATH via ~/.bin)
complete -c secrets -n '__fish_seen_subcommand_from get' -a '(secrets list 2>/dev/null | grep "^  " | string trim | cut -d" " -f1)' -d 'Secret name'
