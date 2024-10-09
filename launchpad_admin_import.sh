#!/bin/bash

# Function to clean up temporary files
cleanup() {
    rm -f "$PASSWORDS_FILE"
}
trap cleanup EXIT

# Prompt for users // Prompt Launchpad usernames instead? So that SSH keys may be imported too.
read -p "Enter the Launchpad usernames (space-separated): " USERS

# Prompt for the group name
read -p "Enter the group name: " GROUP_NAME

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

# Loop through the list of usernames
for user in $USERS; do
    # Validate the existence of the Launchpad user
    if ! check_launchpad_user "$user"; then
        echo "Skipping user $user."
        continue
    fi
    
    # Generate a random password
    password=$(openssl rand -base64 12 | tr -d "=+/")
    
    # Append username and password to the file
    echo "$user $password" >> "$PASSWORDS_FILE"
done

# Create group if it does not exist
if ! getent group "$GROUP_NAME" >/dev/null; then
    sudo groupadd "$GROUP_NAME"
fi

# Function to import SSH keys from Launchpad
import_ssh_keys() {
    local username=$1
    sudo -u "$username" mkdir -p "/home/$username/.ssh"
    sudo -u "$username" curl -s "https://launchpad.net/~$username/+sshkeys" -o "/home/$username/.ssh/authorized_keys"
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
    
    # Add users to the group and sudo group
    sudo usermod -aG "$GROUP_NAME" "$username"
    sudo usermod -aG sudo "$username"
    
    # Change Shell for users
    sudo chsh -s /bin/bash "$username"
    
    # Import SSH keys from Launchpad
    import_ssh_keys "$username"
done

# Function to display the passwords in a professional framed format
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
