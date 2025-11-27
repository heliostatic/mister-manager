function mkcd
    # Create the directory and immediately cd into it if successful.
    mkdir -p "$argv" && cd "$argv"
end
