#!/bin/bash

# Function to clean up temporary files
cleanup() {
    rm -f "$PASSWORDS_FILE"
}
trap cleanup EXIT

# Prompt for users
read -p "Enter the usernames (space-separated): " USERS

# Prompt for the user platform (Launchpad or GitHub) using a read-based choice
while true; do
    read -p "Enter the platform for the usernames (launchpad/github): " PLATFORM
    if [[ "$PLATFORM" == "launchpad" || "$PLATFORM" == "github" ]]; then
        break
    else
        echo "Invalid option. Please enter either 'launchpad' or 'github'."
    fi
done

# Prompt for the group name with the option to skip
read -p "Enter the group name (or press Enter to skip creating an additional group): " GROUP_NAME

# Define the file path to save the usernames and passwords
PASSWORDS_FILE=$(mktemp)

# Function to check if a Launchpad user exists
check_launchpad_user() {
    local username=$1
    local status_code
    status_code=$(curl -o /dev/null -s -w "%{http_code}" "https://launchpad.net/~$username/+sshkeys")
    if [ "$status_code" -ne 200 ]; then
        echo "Launchpad user $username does not exist."
        return 1
    fi
    return 0
}

# Function to check if a GitHub user exists
check_github_user() {
    local username=$1
    local status_code
    status_code=$(curl -o /dev/null -s -w "%{http_code}" "https://github.com/$username.keys")
    if [ "$status_code" -ne 200 ]; then
        echo "GitHub user $username does not exist."
        return 1
    fi
    return 0
}

# Loop through the list of usernames
for user in $USERS; do
    # Validate the existence of the user depending on the platform
    if [ "$PLATFORM" == "launchpad" ]; then
        if ! check_launchpad_user "$user"; then
            echo "Skipping user $user."
            continue
        fi
    elif [ "$PLATFORM" == "github" ]; then
        if ! check_github_user "$user"; then
            echo "Skipping user $user."
            continue
        fi
    else
        echo "Invalid platform specified. Please enter either 'launchpad' or 'github'."
        exit 1
    fi
    
    # Generate a random password
    password=$(openssl rand -base64 12 | tr -d "=+/")
    
    # Append username and password to the file
    echo "$user $password" >> "$PASSWORDS_FILE"
done

# Create group if a group name is provided
if [[ -n "$GROUP_NAME" ]]; then
    if ! getent group "$GROUP_NAME" >/dev/null; then
        sudo groupadd "$GROUP_NAME"
    fi
fi

# Function to import SSH keys from the appropriate platform
import_ssh_keys() {
    local username=$1
    sudo -u "$username" mkdir -p "/home/$username/.ssh"
    local ssh_keys_url

    if [ "$PLATFORM" == "launchpad" ]; then
        ssh_keys_url="https://launchpad.net/~$username/+sshkeys"
    elif [ "$PLATFORM" == "github" ]; then
        ssh_keys_url="https://github.com/$username.keys"
    else
        echo "Invalid platform specified for SSH key import."
        return 1
    fi

    sudo -u "$username" curl -s "$ssh_keys_url" -o "/home/$username/.ssh/authorized_keys"
    sudo chown -R "$username:$username" "/home/$username/.ssh"
    sudo chmod 700 "/home/$username/.ssh"
    sudo chmod 600 "/home/$username/.ssh/authorized_keys"
}

# Read the created usernames and passwords
IFS=$'\n'
for line in $(cat "$PASSWORDS_FILE"); do
    username=$(echo "$line" | awk '{print $1}')
    password=$(echo "$line" | awk '{print $2}')
    
    # Create user if it does not exist
    if ! id -u "$username" >/dev/null 2>&1; then
        sudo useradd -m "$username"
    fi
    
    # Set user password
    echo -e "$password\n$password" | sudo passwd "$username"
    
    # Add users to the group if a group name was provided
    if [[ -n "$GROUP_NAME" ]]; then
        sudo usermod -aG "$GROUP_NAME" "$username"
    fi
    
    # Add users to the sudo group
    sudo usermod -aG sudo "$username"
    
    # Change Shell for users
    sudo chsh -s /bin/bash "$username"
    
    # Import SSH keys from the appropriate platform
    import_ssh_keys "$username"
done

# Function to display the passwords in an easily readable format
display_passwords() {
    local line
    echo "---------------------------------------------"
    echo "|   Username   |         Password           |"
    echo "---------------------------------------------"
    while IFS= read -r line; do
        username=$(echo "$line" | awk '{print $1}')
        password=$(echo "$line" | awk '{print $2}')
        printf "| %-12s | %-24s |\n" "$username" "$password"
    done < "$PASSWORDS_FILE"
    echo "---------------------------------------------"
}

# Securely display the password file content
display_passwords
