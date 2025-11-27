#!/usr/bin/env bash
#
# linux/install.sh
#
# Linux-specific setup: detects distro and installs packages from packages.txt
# Supports --dry-run mode via DRY_RUN environment variable.
#
# Packages are only installed when WITH_PACKAGES=true (via --with-packages or --full)

set -e

DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DOTFILES_ROOT/script/lib.sh"

PACKAGES_FILE="$DOTFILES_ROOT/linux/packages.txt"

# Parse packages.txt and return package names for current distro
# Handles both simple names and distro-specific mappings
get_packages_for_distro() {
    local distro="$1"
    local packages=()

    # Map distro variants to base names used in packages.txt
    local distro_key
    case "$distro" in
        debian|ubuntu|pop) distro_key="debian" ;;
        fedora|rhel|centos) distro_key="fedora" ;;
        arch|manjaro) distro_key="arch" ;;
        *) distro_key="$distro" ;;
    esac

    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        # Trim whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        if [[ "$line" == *":"* ]]; then
            # Distro-specific mapping: debian:name,fedora:name,arch:name
            local pkg=""
            IFS=',' read -ra mappings <<< "$line"
            for mapping in "${mappings[@]}"; do
                local key="${mapping%%:*}"
                local val="${mapping#*:}"
                if [[ "$key" == "$distro_key" ]]; then
                    pkg="$val"
                    break
                fi
            done
            [[ -n "$pkg" ]] && packages+=("$pkg")
        else
            # Simple package name - same on all distros
            packages+=("$line")
        fi
    done < "$PACKAGES_FILE"

    echo "${packages[@]}"
}

install_debian() {
    local packages
    read -ra packages <<< "$(get_packages_for_distro debian)"

    if [[ ${#packages[@]} -eq 0 ]]; then
        warn "No packages found in packages.txt"
        return 0
    fi

    info "Installing ${#packages[@]} packages via apt..."
    verbose "Packages: ${packages[*]}"

    run sudo apt update
    run sudo apt install -y "${packages[@]}"

    [[ "$DRY_RUN" == true ]] || success "Debian packages installed"
}

install_fedora() {
    local packages
    read -ra packages <<< "$(get_packages_for_distro fedora)"

    if [[ ${#packages[@]} -eq 0 ]]; then
        warn "No packages found in packages.txt"
        return 0
    fi

    info "Installing ${#packages[@]} packages via dnf..."
    verbose "Packages: ${packages[*]}"

    # Separate group installs (start with @) from regular packages
    local regular=()
    local groups=()
    for pkg in "${packages[@]}"; do
        if [[ "$pkg" == @* ]]; then
            groups+=("$pkg")
        else
            regular+=("$pkg")
        fi
    done

    [[ ${#groups[@]} -gt 0 ]] && run sudo dnf group install -y "${groups[@]}"
    [[ ${#regular[@]} -gt 0 ]] && run sudo dnf install -y "${regular[@]}"

    [[ "$DRY_RUN" == true ]] || success "Fedora packages installed"
}

install_arch() {
    local packages
    read -ra packages <<< "$(get_packages_for_distro arch)"

    if [[ ${#packages[@]} -eq 0 ]]; then
        warn "No packages found in packages.txt"
        return 0
    fi

    info "Installing ${#packages[@]} packages via pacman..."
    verbose "Packages: ${packages[*]}"

    run sudo pacman -Syu --noconfirm --needed "${packages[@]}"

    [[ "$DRY_RUN" == true ]] || success "Arch packages installed"
}

main() {
    if [[ "$(get_os)" != "linux" ]]; then
        verbose "Not on Linux, skipping linux installer"
        return 0
    fi

    if [[ "$WITH_PACKAGES" != true ]]; then
        verbose "Skipping Linux packages (use --with-packages or --full)"
        return 0
    fi

    if [[ ! -f "$PACKAGES_FILE" ]]; then
        warn "No packages.txt found at $PACKAGES_FILE"
        return 0
    fi

    local distro
    distro="$(get_distro)"

    case "$distro" in
        debian|ubuntu|pop)
            install_debian
            ;;
        fedora|rhel|centos)
            install_fedora
            ;;
        arch|manjaro)
            install_arch
            ;;
        *)
            warn "Unknown distro: $distro"
            warn "Please install packages manually from $PACKAGES_FILE"
            ;;
    esac
}

main "$@"
