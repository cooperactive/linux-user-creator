#!/usr/bin/env bash
set -Eeuo pipefail

# provision-local-users.sh
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
#   - Optional disabling of interactive shell access with /usr/sbin/nologin
#
# Example interactive use:
#   sudo ./provision-local-users.sh
#
# Example CSV use:
#   sudo ./provision-local-users.sh --file users.csv --yes
#
# CSV format:
#   local_user,ssh_source,remote_user,sudo,extra_groups,set_password,login_shell
#
# Examples:
#   alice,github,alice-gh,yes,developers;sshusers,yes,login
#   bob,none,,no,developers,no,nologin
#   test.user02,none,,no,grp-www2-sftp-staging,no,nologin
#
# Valid login_shell values:
#   login
#   nologin
#
# If login_shell is omitted from an older CSV, "login" is used.

PASSWORDS_FILE=""
YES="no"
INPUT_FILE=""

LOGIN_SHELL="/bin/bash"
NOLOGIN_SHELL=""
ADMIN_GROUP=""

cleanup() {
    if [[ -n "${PASSWORDS_FILE:-}" && -f "$PASSWORDS_FILE" ]]; then
        chmod 600 "$PASSWORDS_FILE" || true
    fi
}
trap cleanup EXIT

usage() {
    cat <<'EOF'
Usage:
    sudo ./provision-local-users.sh [--file users.csv] [--yes]

Options:
  --file FILE   Read users from CSV instead of interactive prompts.
  --yes         Do not ask for final confirmation.
  -h, --help    Show this help.

CSV columns:
  local_user,ssh_source,remote_user,sudo,extra_groups,set_password,login_shell

Valid ssh_source values:
  none
  github
  launchpad

Valid login_shell values:
  login
  nologin

Boolean values:
  yes/no, true/false, 1/0

extra_groups:
  Use semicolon-separated group names, for example:
  developers;sshusers

Examples:
  alice,github,alice-gh,yes,developers;sshusers,yes,login
  bob,none,,no,developers,no,nologin
  test.user02,none,,no,grp-www2-sftp-staging,no,nologin

Notes:
  - "login" uses /bin/bash.
  - "nologin" uses /usr/sbin/nologin.
  - Older CSV files without login_shell default to "login".
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

validate_shell_paths() {
    [[ -x "$LOGIN_SHELL" ]] ||
        die "Login shell does not exist or is not executable: $LOGIN_SHELL"

    [[ -x "$NOLOGIN_SHELL" ]] ||
        die "nologin shell does not exist or is not executable: $NOLOGIN_SHELL"
}

detect_nologin_shell() {
    local candidate

    if candidate="$(command -v nologin 2>/dev/null)" &&
       [[ -x "$candidate" ]]; then
        NOLOGIN_SHELL="$candidate"
        return 0
    fi

    for candidate in /usr/sbin/nologin /sbin/nologin /usr/bin/nologin; do
        if [[ -x "$candidate" ]]; then
            NOLOGIN_SHELL="$candidate"
            return 0
        fi
    done

    die "Could not find an executable nologin binary."
}

detect_admin_group() {
    local preferred=""
    local distro_hints=""

    if [[ -r /etc/os-release ]]; then
        distro_hints="$(
            # shellcheck disable=SC1091
            . /etc/os-release
            printf '%s %s' "${ID:-}" "${ID_LIKE:-}"
        )"
        distro_hints="${distro_hints,,}"
    fi

    case "$distro_hints" in
        *debian*|*ubuntu*)
            preferred="sudo"
            ;;
        *rhel*|*fedora*|*centos*|*rocky*|*almalinux*|*suse*)
            preferred="wheel"
            ;;
    esac

    if [[ -n "$preferred" ]] && getent group "$preferred" >/dev/null; then
        ADMIN_GROUP="$preferred"
        return 0
    fi

    if getent group sudo >/dev/null; then
        ADMIN_GROUP="sudo"
        return 0
    fi

    if getent group wheel >/dev/null; then
        ADMIN_GROUP="wheel"
        return 0
    fi

    ADMIN_GROUP="${preferred:-sudo}"
    info "Admin group '$ADMIN_GROUP' was not found; creating it."
    ensure_group_exists "$ADMIN_GROUP"
}

is_valid_linux_username() {
    local username="$1"

    # Allows conventional Linux usernames including periods, e.g. test.user02.
    # The first character must still be a lowercase letter or underscore.
    [[ "$username" =~ ^[a-z_][a-z0-9_.-]{0,31}$ ]]
}

is_valid_group_name() {
    local group="$1"
    [[ "$group" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

normalize_bool() {
    local value="${1,,}"

    case "$value" in
        yes|y|true|1)
            echo "yes"
            ;;
        no|n|false|0|"")
            echo "no"
            ;;
        *)
            return 1
            ;;
    esac
}

normalize_login_shell() {
    local value="${1,,}"

    case "$value" in
        login|bash|"")
            echo "login"
            ;;
        nologin|no-login|none)
            echo "nologin"
            ;;
        *)
            return 1
            ;;
    esac
}

resolve_login_shell_path() {
    local shell_mode="$1"

    case "$shell_mode" in
        login)
            echo "$LOGIN_SHELL"
            ;;
        nologin)
            echo "$NOLOGIN_SHELL"
            ;;
        *)
            die "Invalid login shell mode: $shell_mode"
            ;;
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
        read -r -p \
            "SSH key source for this user (none/github/launchpad) [none]: " \
            value

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

prompt_login_shell() {
    local allow_shell

    allow_shell="$(
        prompt_bool \
            "Allow interactive shell login?" \
            "yes"
    )"

    if [[ "$allow_shell" == "yes" ]]; then
        echo "login"
    else
        echo "nologin"
    fi
}

ensure_group_exists() {
    local group="$1"

    [[ -z "$group" ]] && return 0

    is_valid_group_name "$group" ||
        die "Invalid group name: $group"

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

    [[ -n "$home_dir" ]] ||
        die "Could not determine home directory for $local_user."

    if [[ ! -d "$home_dir" ]]; then
        local primary_group
        primary_group="$(get_user_primary_group "$local_user")"

        info "Creating missing home directory '$home_dir' for user '$local_user'."

        install \
            -d \
            -m 700 \
            -o "$local_user" \
            -g "$primary_group" \
            "$home_dir"
    fi
}

generate_password() {
    local password=""

    # Generate exactly 24 characters from a shell-safe character set.
    while true; do
        password="$(
            openssl rand -base64 48 |
                tr -dc 'A-Za-z0-9' |
                head -c 24
        )"

        if [[ "${#password}" -eq 24 ]]; then
            printf '%s\n' "$password"
            return 0
        fi
    done
}

fetch_ssh_keys() {
    local ssh_source="$1"
    local remote_user="$2"

    case "$ssh_source" in
        github)
            curl \
                --fail \
                --silent \
                --show-error \
                --location \
                "https://github.com/${remote_user}.keys"
            ;;
        launchpad)
            curl \
                --fail \
                --silent \
                --show-error \
                --location \
                "https://launchpad.net/~${remote_user}/+sshkeys"
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

    # Accept common public key types.
    # This prevents writing HTML/error pages as authorized_keys.
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        [[ "$line" =~ ^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521|sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com)[[:space:]] ]] ||
            return 1
    done <<< "$keys"

    return 0
}

install_ssh_keys() {
    local local_user="$1"
    local ssh_source="$2"
    local remote_user="$3"

    [[ "$ssh_source" == "none" ]] && return 0

    [[ -n "$remote_user" ]] ||
        die "Remote username is required when ssh_source is $ssh_source."

    info \
        "Importing SSH keys for local user '$local_user' " \
        "from $ssh_source user '$remote_user'."

    local keys

    if ! keys="$(fetch_ssh_keys "$ssh_source" "$remote_user")"; then
        die \
            "Failed to fetch SSH keys from $ssh_source " \
            "for remote user: $remote_user"
    fi

    if ! validate_ssh_keys_content "$keys"; then
        die \
            "Fetched SSH key data for '$remote_user' " \
            "from '$ssh_source' was empty or invalid."
    fi

    ensure_user_home_dir "$local_user"

    local home_dir primary_group
    home_dir="$(get_user_home_dir "$local_user")"
    primary_group="$(get_user_primary_group "$local_user")"

    install \
        -d \
        -m 700 \
        -o "$local_user" \
        -g "$primary_group" \
        "$home_dir/.ssh"

    # Replace authorized_keys intentionally with the remote account's public keys.
    # Change this to >> if you want to append instead.
    printf '%s\n' "$keys" > "$home_dir/.ssh/authorized_keys"

    chown \
        "$local_user:$primary_group" \
        "$home_dir/.ssh/authorized_keys"

    chmod 600 "$home_dir/.ssh/authorized_keys"
}

create_or_update_user() {
    local local_user="$1"
    local ssh_source="$2"
    local remote_user="$3"
    local add_sudo="$4"
    local extra_groups="$5"
    local set_password="$6"
    local login_shell_mode="$7"

    is_valid_linux_username "$local_user" ||
        die "Invalid local username: $local_user"

    if [[ "$ssh_source" != "none" && -z "$remote_user" ]]; then
        die \
            "Remote username is required for local user '$local_user' " \
            "when ssh_source is '$ssh_source'."
    fi

    local shell_path
    shell_path="$(resolve_login_shell_path "$login_shell_mode")"

    local user_exists="no"

    if id "$local_user" >/dev/null 2>&1; then
        user_exists="yes"
        info "User already exists: $local_user"

        local current_shell
        current_shell="$(getent passwd "$local_user" | cut -d: -f7)"

        if [[ "$current_shell" != "$shell_path" ]]; then
            info \
                "Changing shell for '$local_user' " \
                "from '$current_shell' to '$shell_path'."

            usermod --shell "$shell_path" "$local_user"
        fi
    else
        info \
            "Creating local user: $local_user " \
            "(shell: $shell_path)"

        useradd \
            --create-home \
            --shell "$shell_path" \
            "$local_user"
    fi

    ensure_user_home_dir "$local_user"

    if [[ "$set_password" == "yes" ]]; then
        local password
        password="$(generate_password)"

        printf '%s:%s\n' \
            "$local_user" \
            "$password" |
            chpasswd

        printf '%s,%s\n' \
            "$local_user" \
            "$password" >> "$PASSWORDS_FILE"
    else
        info "No local password generated for: $local_user"

        if [[ "$user_exists" == "yes" ]]; then
            info "Keeping existing password state for: $local_user"
        else
            passwd \
                --lock \
                "$local_user" \
                >/dev/null 2>&1 || true
        fi
    fi

    if [[ "$add_sudo" == "yes" ]]; then
        usermod -aG "$ADMIN_GROUP" "$local_user"

        info "Added '$local_user' to $ADMIN_GROUP."
    fi

    if [[ -n "$extra_groups" ]]; then
        IFS=';' read -r -a groups <<< "$extra_groups"

        for group in "${groups[@]}"; do
            group="$(trim_whitespace "$group")"

            [[ -z "$group" ]] && continue

            ensure_group_exists "$group"

            usermod -aG "$group" "$local_user"

            info "Added '$local_user' to group '$group'."
        done
    fi

    install_ssh_keys \
        "$local_user" \
        "$ssh_source" \
        "$remote_user"
}

print_summary() {
    # shellcheck disable=SC2178
    local -n users_ref=$1

    echo
    echo "Planned user provisioning:"

    printf '%-18s %-12s %-22s %-7s %-25s %-10s %-10s\n' \
        "LOCAL_USER" \
        "SSH_SOURCE" \
        "REMOTE_USER" \
        "SUDO" \
        "EXTRA_GROUPS" \
        "PASSWORD" \
        "SHELL"

    printf '%0.s-' {1..115}
    echo

    local row

    for row in "${users_ref[@]}"; do
        IFS=',' read -r \
            local_user \
            ssh_source \
            remote_user \
            add_sudo \
            extra_groups \
            set_password \
            login_shell_mode <<< "$row"

        printf '%-18s %-12s %-22s %-7s %-25s %-10s %-10s\n' \
            "$local_user" \
            "$ssh_source" \
            "${remote_user:-"-"}" \
            "$add_sudo" \
            "${extra_groups:-"-"}" \
            "$set_password" \
            "$login_shell_mode"
    done

    echo
}

read_interactive_users() {
    # shellcheck disable=SC2178
    local -n users_ref=$1

    local count
    local local_user
    local ssh_source
    local remote_user
    local add_sudo
    local extra_groups
    local set_password
    local login_shell_mode

    while true; do
        read -r -p \
            "How many users should be created/updated?: " \
            count

        [[ "$count" =~ ^[0-9]+$ && "$count" -gt 0 ]] &&
            break

        echo "Please enter a positive number."
    done

    for (( i=1; i<=count; i++ )); do
        echo
        echo "User $i of $count"

        local_user="$(
            prompt_nonempty \
                "Local Linux username"
        )"

        is_valid_linux_username "$local_user" ||
            die "Invalid local username: $local_user"

        ssh_source="$(prompt_ssh_source)"

        remote_user=""

        if [[ "$ssh_source" != "none" ]]; then
            read -r -p \
                "Remote $ssh_source username to import SSH keys from [$local_user]: " \
                remote_user

            remote_user="${remote_user:-$local_user}"
        fi

        add_sudo="$(
            prompt_bool \
                "Add this user to sudo?" \
                "no"
        )"

        read -r -p \
            "Extra groups, semicolon-separated, or blank for none: " \
            extra_groups

        set_password="$(
            prompt_bool \
                "Generate and set a local password?" \
                "yes"
        )"

        login_shell_mode="$(prompt_login_shell)"

        users_ref+=(
            "${local_user},${ssh_source},${remote_user},${add_sudo},${extra_groups},${set_password},${login_shell_mode}"
        )
    done
}

read_csv_users() {
    # shellcheck disable=SC2178
    local -n users_ref=$1
    local file="$2"
    local line
    local line_no=0

    [[ -f "$file" ]] ||
        die "CSV file not found: $file"

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

        IFS=',' read -r \
            local_user \
            ssh_source \
            remote_user \
            add_sudo \
            extra_groups \
            set_password \
            login_shell_mode <<< "$line"

        local_user="$(trim_whitespace "${local_user:-}")"
        ssh_source="$(trim_whitespace "${ssh_source:-none}")"
        remote_user="$(trim_whitespace "${remote_user:-}")"
        add_sudo="$(trim_whitespace "${add_sudo:-no}")"
        extra_groups="$(trim_whitespace "${extra_groups:-}")"
        set_password="$(trim_whitespace "${set_password:-yes}")"

        # Backwards compatibility:
        # older CSV files without login_shell default to normal login.
        login_shell_mode="$(
            trim_whitespace "${login_shell_mode:-login}"
        )"

        ssh_source="${ssh_source,,}"
        login_shell_mode="${login_shell_mode,,}"

        if [[ "$ssh_source" != "none" && -z "$remote_user" ]]; then
            remote_user="$local_user"
        fi

        [[ "$ssh_source" =~ ^(none|github|launchpad)$ ]] ||
            die \
                "Invalid ssh_source on CSV line $line_no: $ssh_source"

        add_sudo="$(normalize_bool "$add_sudo")" ||
            die \
                "Invalid sudo boolean on CSV line $line_no."

        set_password="$(normalize_bool "$set_password")" ||
            die \
                "Invalid set_password boolean on CSV line $line_no."

        login_shell_mode="$(
            normalize_login_shell "$login_shell_mode"
        )" ||
            die \
                "Invalid login_shell on CSV line $line_no. " \
                "Use 'login' or 'nologin'."

        users_ref+=(
            "${local_user},${ssh_source},${remote_user},${add_sudo},${extra_groups},${set_password},${login_shell_mode}"
        )
    done < "$file"
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --file)
                INPUT_FILE="${2:-}"

                [[ -n "$INPUT_FILE" ]] ||
                    die "--file requires a value."

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

    require_commands \
        curl \
        openssl \
        useradd \
        usermod \
        groupadd \
        chpasswd \
        passwd \
        mktemp \
        wc \
        rm \
        chmod \
        chown \
        id \
        getent \
        install \
        head \
        tr \
        cut

    detect_nologin_shell

    validate_shell_paths
    detect_admin_group

    PASSWORDS_FILE="$(
        mktemp /root/created-users-passwords.XXXXXX.csv
    )"

    chmod 600 "$PASSWORDS_FILE"

    echo "local_user,password" > "$PASSWORDS_FILE"

    local users=()

    if [[ -n "$INPUT_FILE" ]]; then
        read_csv_users users "$INPUT_FILE"
    else
        read_interactive_users users
    fi

    (( ${#users[@]} > 0 )) ||
        die "No users provided."

    print_summary users

    if [[ "$YES" != "yes" ]]; then
        local confirm

        confirm="$(
            prompt_bool \
                "Proceed with these changes?" \
                "no"
        )"

        [[ "$confirm" == "yes" ]] ||
            die "Aborted."
    fi

    local row

    for row in "${users[@]}"; do
        IFS=',' read -r \
            local_user \
            ssh_source \
            remote_user \
            add_sudo \
            extra_groups \
            set_password \
            login_shell_mode <<< "$row"

        create_or_update_user \
            "$local_user" \
            "$ssh_source" \
            "$remote_user" \
            "$add_sudo" \
            "$extra_groups" \
            "$set_password" \
            "$login_shell_mode"
    done

    echo
    echo "Done."

    if [[ -s "$PASSWORDS_FILE" ]] &&
       [[ "$(wc -l < "$PASSWORDS_FILE")" -gt 1 ]]; then

        echo "Generated passwords were saved to:"
        echo "  $PASSWORDS_FILE"
        echo
        echo \
            "Keep this file secure and remove it after storing the passwords safely."
    else
        rm -f "$PASSWORDS_FILE"
        PASSWORDS_FILE=""
    fi
}

main "$@"
