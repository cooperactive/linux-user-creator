#!/usr/bin/env bash
set -Eeuo pipefail

# create-users-granular.sh
#
# Granular local user provisioning helper.
#
# Supports:
#   - Local-only users without SSH key import
#   - Importing public SSH keys from GitHub or Launchpad
#   - Different local username and remote GitHub/Launchpad username
#   - Optional sudo membership
#   - Optional extra group membership
#   - Optional password generation
#   - Optional passwordless SSH-only accounts
#
# Example interactive use:
#   sudo ./create-users-granular.sh
#
# Example CSV use:
#   sudo ./create-users-granular.sh --file users.csv --yes
#
# CSV format:
#   local_user,ssh_source,remote_user,sudo,extra_groups,set_password
#   alice,github,alice-gh,yes,developers;sshusers,yes
#   bob,none,,no,developers,no
#   carl,launchpad,carl-lp,no,,yes

PASSWORDS_FILE=""
YES="no"
INPUT_FILE=""

cleanup() {
    if [[ -n "${PASSWORDS_FILE:-}" && -f "$PASSWORDS_FILE" ]]; then
        chmod 600 "$PASSWORDS_FILE" || true
    fi
}
trap cleanup EXIT

usage() {
    cat <<'EOF'
Usage:
    sudo ./create-users-granular.sh [--file users.csv] [--yes]

Options:
  --file FILE   Read users from CSV instead of interactive prompts.
  --yes         Do not ask for final confirmation.
  -h, --help    Show this help.

CSV columns:
  local_user,ssh_source,remote_user,sudo,extra_groups,set_password

Valid ssh_source values:
  none
  github
  launchpad

Boolean values:
  yes/no, true/false, 1/0

extra_groups:
  Use semicolon-separated group names, for example:
  developers;sshusers
EOF
}

trim_whitespace() {
    local value="${1-}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

die() {
    echo "Error: $*" >&2
    exit 1
}

info() {
    echo "[INFO] $*"
}

warn() {
    echo "[WARN] $*" >&2
}

require_root() {
    [[ "${EUID}" -eq 0 ]] || die "Run this script as root or with sudo."
}

require_commands() {
    local missing=()
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done

    if (( ${#missing[@]} > 0 )); then
        die "Missing required command(s): ${missing[*]}"
    fi
}

is_valid_linux_username() {
    local username="$1"
    [[ "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

is_valid_group_name() {
    local group="$1"
    [[ "$group" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

normalize_bool() {
    local value="${1,,}"
    case "$value" in
        yes|y|true|1) echo "yes" ;;
        no|n|false|0|"") echo "no" ;;
        *) return 1 ;;
    esac
}

prompt_bool() {
    local prompt="$1"
    local default="$2"
    local answer normalized

    while true; do
        read -r -p "$prompt [$default]: " answer
        answer="${answer:-$default}"

        if normalized=$(normalize_bool "$answer"); then
            echo "$normalized"
            return 0
        fi

        echo "Please answer yes or no."
    done
}

prompt_nonempty() {
    local prompt="$1"
    local value

    while true; do
        read -r -p "$prompt: " value
        if [[ -n "$value" ]]; then
            echo "$value"
            return 0
        fi
        echo "Value cannot be empty."
    done
}

prompt_ssh_source() {
    local value

    while true; do
        read -r -p "SSH key source for this user (none/github/launchpad) [none]: " value
        value="${value:-none}"
        value="${value,,}"
        case "$value" in
            none|github|launchpad)
                echo "$value"
                return 0
                ;;
            *)
                echo "Please enter none, github, or launchpad."
                ;;
        esac
    done
}

ensure_group_exists() {
    local group="$1"

    [[ -z "$group" ]] && return 0

    is_valid_group_name "$group" || die "Invalid group name: $group"

    if ! getent group "$group" >/dev/null; then
        info "Creating group: $group"
        groupadd "$group"
    fi
}

get_user_home_dir() {
    local local_user="$1"
    getent passwd "$local_user" | cut -d: -f6
}

get_user_primary_group() {
    local local_user="$1"
    id -gn "$local_user"
}

ensure_user_home_dir() {
    local local_user="$1"

    local home_dir
    home_dir="$(get_user_home_dir "$local_user")"
    [[ -n "$home_dir" ]] || die "Could not determine home directory for $local_user."

    if [[ ! -d "$home_dir" ]]; then
        local primary_group
        primary_group="$(get_user_primary_group "$local_user")"
        info "Creating missing home directory '$home_dir' for user '$local_user'."
        install -d -m 700 -o "$local_user" -g "$primary_group" "$home_dir"
    fi
}

generate_password() {
    # Avoid characters that are awkward to copy/paste while keeping strong entropy.
    openssl rand -base64 24 | tr -d '\n' | tr -d '/+=' | cut -c1-24
}

fetch_ssh_keys() {
    local ssh_source="$1"
    local remote_user="$2"

    case "$ssh_source" in
        github)
            curl --fail --silent --show-error --location "https://github.com/${remote_user}.keys"
            ;;
        launchpad)
            curl --fail --silent --show-error --location "https://launchpad.net/~${remote_user}/+sshkeys"
            ;;
        none)
            return 0
            ;;
        *)
            die "Invalid SSH source: $ssh_source"
            ;;
    esac
}

validate_ssh_keys_content() {
    local keys="$1"

    if [[ -z "$keys" ]]; then
        return 1
    fi

    # Accept common public key types. This prevents writing HTML/error pages as authorized_keys.
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521|sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com)[[:space:]] ]] || return 1
    done <<< "$keys"

    return 0
}

install_ssh_keys() {
    local local_user="$1"
    local ssh_source="$2"
    local remote_user="$3"

    [[ "$ssh_source" == "none" ]] && return 0

    [[ -n "$remote_user" ]] || die "Remote username is required when ssh_source is $ssh_source."

    info "Importing SSH keys for local user '$local_user' from $ssh_source user '$remote_user'."

    local keys
    if ! keys="$(fetch_ssh_keys "$ssh_source" "$remote_user")"; then
        die "Failed to fetch SSH keys from $ssh_source for remote user: $remote_user"
    fi

    if ! validate_ssh_keys_content "$keys"; then
        die "Fetched SSH key data for '$remote_user' from '$ssh_source' was empty or invalid."
    fi

    ensure_user_home_dir "$local_user"

    local home_dir primary_group
    home_dir="$(get_user_home_dir "$local_user")"
    primary_group="$(get_user_primary_group "$local_user")"

    install -d -m 700 -o "$local_user" -g "$primary_group" "$home_dir/.ssh"

    # Replace authorized_keys intentionally with the remote account's public keys.
    # Change this to >> if you want to append instead.
    printf '%s\n' "$keys" > "$home_dir/.ssh/authorized_keys"

    chown "$local_user:$primary_group" "$home_dir/.ssh/authorized_keys"
    chmod 600 "$home_dir/.ssh/authorized_keys"
}

create_or_update_user() {
    local local_user="$1"
    local ssh_source="$2"
    local remote_user="$3"
    local add_sudo="$4"
    local extra_groups="$5"
    local set_password="$6"

    is_valid_linux_username "$local_user" || die "Invalid local username: $local_user"

    if [[ "$ssh_source" != "none" && -z "$remote_user" ]]; then
        die "Remote username is required for local user '$local_user' when ssh_source is '$ssh_source'."
    fi

    if id "$local_user" >/dev/null 2>&1; then
        info "User already exists: $local_user"
    else
        info "Creating local user: $local_user"
        useradd --create-home --shell /bin/bash "$local_user"
    fi

    ensure_user_home_dir "$local_user"

    if [[ "$set_password" == "yes" ]]; then
        local password
        password="$(generate_password)"
        printf '%s:%s\n' "$local_user" "$password" | chpasswd
        printf '%s,%s\n' "$local_user" "$password" >> "$PASSWORDS_FILE"
    else
        info "No local password generated for: $local_user"
        passwd --lock "$local_user" >/dev/null 2>&1 || true
    fi

    if [[ "$add_sudo" == "yes" ]]; then
        ensure_group_exists "sudo"
        usermod -aG sudo "$local_user"
        info "Added '$local_user' to sudo."
    fi

    if [[ -n "$extra_groups" ]]; then
        IFS=';' read -r -a groups <<< "$extra_groups"
        for group in "${groups[@]}"; do
            group="$(echo "$group" | xargs)"
            [[ -z "$group" ]] && continue
            ensure_group_exists "$group"
            usermod -aG "$group" "$local_user"
            info "Added '$local_user' to group '$group'."
        done
    fi

    install_ssh_keys "$local_user" "$ssh_source" "$remote_user"
}

print_summary() {
    local -n users_ref=$1

    echo
    echo "Planned user provisioning:"
    printf '%-18s %-12s %-24s %-8s %-25s %-12s\n' \
        "LOCAL_USER" "SSH_SOURCE" "REMOTE_USER" "SUDO" "EXTRA_GROUPS" "PASSWORD"
    printf '%0.s-' {1..105}
    echo

    local row
    for row in "${users_ref[@]}"; do
        IFS=',' read -r local_user ssh_source remote_user add_sudo extra_groups set_password <<< "$row"
        printf '%-18s %-12s %-24s %-8s %-25s %-12s\n' \
            "$local_user" "$ssh_source" "${remote_user:-"-"}" "$add_sudo" "${extra_groups:-"-"}" "$set_password"
    done
    echo
}

read_interactive_users() {
    local -n users_ref=$1
    local count local_user ssh_source remote_user add_sudo extra_groups set_password

    while true; do
        read -r -p "How many users should be created/updated?: " count
        [[ "$count" =~ ^[0-9]+$ && "$count" -gt 0 ]] && break
        echo "Please enter a positive number."
    done

    for (( i=1; i<=count; i++ )); do
        echo
        echo "User $i of $count"

        local_user="$(prompt_nonempty "Local Linux username")"
        is_valid_linux_username "$local_user" || die "Invalid local username: $local_user"

        ssh_source="$(prompt_ssh_source)"

        remote_user=""
        if [[ "$ssh_source" != "none" ]]; then
            read -r -p "Remote $ssh_source username to import SSH keys from [$local_user]: " remote_user
            remote_user="${remote_user:-$local_user}"
        fi

        add_sudo="$(prompt_bool "Add this user to sudo?" "no")"

        read -r -p "Extra groups, semicolon-separated, or blank for none: " extra_groups

        set_password="$(prompt_bool "Generate and set a local password?" "yes")"

        users_ref+=("${local_user},${ssh_source},${remote_user},${add_sudo},${extra_groups},${set_password}")
    done
}

read_csv_users() {
    local -n users_ref=$1
    local file="$2"
    local line line_no=0

    [[ -f "$file" ]] || die "CSV file not found: $file"

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_no++))

        # Handle Windows CSV files and editors that include UTF-8 BOM.
        line="${line%$'\r'}"
        if [[ "$line_no" -eq 1 ]]; then
            line="${line#$'\ufeff'}"
        fi

        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Skip header if present.
        if [[ "$line_no" -eq 1 && "$line" == local_user,* ]]; then
            continue
        fi

        IFS=',' read -r local_user ssh_source remote_user add_sudo extra_groups set_password <<< "$line"

        local_user="$(trim_whitespace "${local_user:-}")"
        ssh_source="$(trim_whitespace "${ssh_source:-none}")"
        remote_user="$(trim_whitespace "${remote_user:-}")"
        add_sudo="$(trim_whitespace "${add_sudo:-no}")"
        extra_groups="$(trim_whitespace "${extra_groups:-}")"
        set_password="$(trim_whitespace "${set_password:-yes}")"

        ssh_source="${ssh_source,,}"

        if [[ "$ssh_source" != "none" && -z "$remote_user" ]]; then
            remote_user="$local_user"
        fi

        [[ "$ssh_source" =~ ^(none|github|launchpad)$ ]] || die "Invalid ssh_source on CSV line $line_no: $ssh_source"

        add_sudo="$(normalize_bool "$add_sudo")" || die "Invalid sudo boolean on CSV line $line_no."
        set_password="$(normalize_bool "$set_password")" || die "Invalid set_password boolean on CSV line $line_no."

        users_ref+=("${local_user},${ssh_source},${remote_user},${add_sudo},${extra_groups},${set_password}")
    done < "$file"
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --file)
                INPUT_FILE="${2:-}"
                [[ -n "$INPUT_FILE" ]] || die "--file requires a value."
                shift 2
                ;;
            --yes)
                YES="yes"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "Unknown argument: $1"
                ;;
        esac
    done

    require_root
    require_commands curl openssl useradd usermod chpasswd passwd getent install

    PASSWORDS_FILE="$(mktemp /root/created-users-passwords.XXXXXX.csv)"
    chmod 600 "$PASSWORDS_FILE"
    echo "local_user,password" > "$PASSWORDS_FILE"

    local users=()

    if [[ -n "$INPUT_FILE" ]]; then
        read_csv_users users "$INPUT_FILE"
    else
        read_interactive_users users
    fi

    (( ${#users[@]} > 0 )) || die "No users provided."

    print_summary users

    if [[ "$YES" != "yes" ]]; then
        local confirm
        confirm="$(prompt_bool "Proceed with these changes?" "no")"
        [[ "$confirm" == "yes" ]] || die "Aborted."
    fi

    local row
    for row in "${users[@]}"; do
        IFS=',' read -r local_user ssh_source remote_user add_sudo extra_groups set_password <<< "$row"
        create_or_update_user "$local_user" "$ssh_source" "$remote_user" "$add_sudo" "$extra_groups" "$set_password"
    done

    echo
    echo "Done."

    if [[ -s "$PASSWORDS_FILE" ]] && [[ "$(wc -l < "$PASSWORDS_FILE")" -gt 1 ]]; then
        echo "Generated passwords were saved to:"
        echo "  $PASSWORDS_FILE"
        echo
        echo "Keep this file secure and remove it after storing the passwords safely."
    else
        rm -f "$PASSWORDS_FILE"
        PASSWORDS_FILE=""
    fi
}

main "$@"
