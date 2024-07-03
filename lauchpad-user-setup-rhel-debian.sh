#!/bin/bash

# Function to clean up temporary files
cleanup() {
    rm -f "$PASSWORDS_FILE"
}
trap cleanup EXIT

# Prompt for Lauchpad users
read -p "Enter Launchpad Users (space-separated): " USERS

# Prompt for the group name
read -p "Enter the group name (leave empty if no additional group): " GROUP_NAME

# Define the file path to save the usernames and passwords
PASSWORDS_FILE=$(mktemp)

# Loop through the list of usernames
for user in $USERS; do
    # Generate a random password
    password=$(openssl rand -base64 12 | tr -d "=+/")

    # Append username and password to the file
    echo "$user $password" >> "$PASSWORDS_FILE"
done

# Create group if it does not exist and GROUP_NAME is provided
if [ -n "$GROUP_NAME" ]; then
    if ! getent group "$GROUP_NAME" >/dev/null; then
        sudo groupadd "$GROUP_NAME"
    fi
fi

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
    
    # Add users to the group if GROUP_NAME is provided
    if [ -n "$GROUP_NAME" ]; then
        sudo usermod -aG "$GROUP_NAME" "$username"
    fi
    
    # Add users to the sudo group
    sudo usermod -aG sudo "$username"

    # Change Shell for users
    sudo chsh -s /bin/bash "$username"

    # Fetch SSH keys from Launchpad and add to user's authorized_keys
    SSH_KEYS=$(curl -s "https://launchpad.net/~$username/+sshkeys" | grep -Po '(?<=<pre>).*(?=</pre>)')
    if [ -n "$SSH_KEYS" ]; then
        sudo mkdir -p /home/"$username"/.ssh
        echo "$SSH_KEYS" | sudo tee -a /home/"$username"/.ssh/authorized_keys > /dev/null
        sudo chown -R "$username":"$username" /home/"$username"/.ssh
        sudo chmod 700 /home/"$username"/.ssh
        sudo chmod 600 /home/"$username"/.ssh/authorized_keys
    fi
done

# Securely display the passwords file content
cat "$PASSWORDS_FILE"