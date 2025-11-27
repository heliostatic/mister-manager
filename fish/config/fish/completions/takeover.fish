# Completions for dotfiles takeover script

# Options
complete -c takeover -s n -l dry-run -d 'Preview without making changes'
complete -c takeover -l config -d 'Place in topic/config/ (for ~/.config/* items)'
complete -c takeover -s h -l help -d 'Show help'

# Topic names (second argument)
# Only suggest topics when we already have a file path
complete -c takeover -n '__fish_is_token_n 2' -a 'editor fish git linux macos mail rust ssh system terminal tmux' -d 'Topic folder'
# Add more topics here as you create them
