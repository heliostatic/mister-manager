# Completions for dotfiles bootstrap script

# Disable file completions
complete -c bootstrap -f

# Commands (mutually exclusive modes)
complete -c bootstrap -l unlink -d 'Remove symlinks and restore backups'
complete -c bootstrap -l track -d 'Track symlinks (scan all or specific path)'
complete -c bootstrap -l doctor -d 'Comprehensive system health check'
complete -c bootstrap -l status -d 'Alias for --doctor'

# Options
complete -c bootstrap -s n -l dry-run -d 'Preview without making changes'
complete -c bootstrap -s v -l verbose -d 'Show verbose output'
complete -c bootstrap -l no-install -d 'Skip running install.sh scripts'
complete -c bootstrap -l symlinks-only -d 'Only create symlinks, skip installers'
complete -c bootstrap -l with-packages -d 'Install packages (Brewfile, distro, Rust)'
complete -c bootstrap -l with-keys -d 'Copy SSH keys from 1Password'
complete -c bootstrap -l full -d 'Complete install: symlinks + packages + keys + secrets'
complete -c bootstrap -s h -l help -d 'Show help'
