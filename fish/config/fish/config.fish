if status is-interactive
    # Commands to run in interactive sessions can go here
    set -gx SHELL $(which fish)
    zoxide init fish | source
end

export PATH="$PATH:$HOME/.local/bin"

# Secrets are loaded via conf.d/secrets.fish using 1Password/Keychain
# To cache secrets for offline use: ~/.dotfiles/script/secrets cache-all

# Set your preferred editor (uncomment and customize)
# set -x EDITOR hx      # Helix
# set -x EDITOR nvim    # Neovim
# set -x EDITOR vim     # Vim

# Add additional tool-specific configuration below
# Examples:
#   set --export BUN_INSTALL "$HOME/.bun"
#   set --export PATH $BUN_INSTALL/bin $PATH
#   fish_add_path $HOME/.cargo/bin
