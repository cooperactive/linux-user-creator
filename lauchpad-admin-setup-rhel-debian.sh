#!/bin/bash

# Function to clean up temporary files
cleanup() {
    rm -f "$PASSWORDS_FILE"
}
trap cleanup EXIT

# Display initial Gantt Chart status
echo "Progress: [ ] Prompt for Launchpad Users"
echo "Progress: [ ] Prompt for Group Name"
echo "Progress: [ ] Generate Random Passwords"
echo "Progress: [ ] Create Group if Necessary"
echo "Progress: [ ] Create User Accounts"
echo "Progress: [ ] Set User Passwords"
echo "Progress: [ ] Add Users to Groups"
echo "Progress: [ ] Change User Shell"
echo "Progress: [ ] Fetch and Configure SSH Keys"
echo "Progress: [ ] Cleanup Temporary Files"

# Prompt for Launchpad users
read -p "Enter Launchpad Users (space-separated): " USERS
echo "Progress: [X] Prompt for Launchpad Users"

# Prompt for the group name
read -p "Enter the group name (leave empty if no additional group): " GROUP_NAME
echo "Progress: [X] Prompt for Group Name"

# Define the file path to save the usernames and passwords
PASSWORDS_FILE=$(mktemp)

# Loop through the list of usernames
for user in $USERS; do
    # Generate a random password
    password=$(openssl rand -base64 12 | tr -d "=+/")

    # Append username and password to the file
    echo "$user $password" >> "$PASSWORDS_FILE"
done
echo "Progress: [X] Generate Random Passwords"

# Create group if it does not exist and GROUP_NAME is provided
if [ -n "$GROUP_NAME" ]; then
    if ! getent group "$GROUP_NAME" >/dev/null; then
        sudo groupadd "$GROUP_NAME"
    fi
fi
echo "Progress: [X] Create Group if Necessary"

# Read the created usernames and passwords
IFS=$'\n'
for line in $(cat "$PASSWORDS_FILE"); do
    username=$(echo "$line" | awk '{print $1}')
    password=$(echo "$line" | awk '{print $2}')

    # Create user if it does not exist
    if ! id -u "$username" >/dev/null 2>&1; then
        sudo useradd -m "$username"
    fi
done
echo "Progress: [X] Create User Accounts"

# Set user passwords
for line in $(cat "$PASSWORDS_FILE"); do
    username=$(echo "$line" | awk '{print $1}')
    password=$(echo "$line" | awk '{print $2}')

    echo -e "$password\n$password" | sudo passwd "$username"
done
echo "Progress: [X] Set User Passwords"

# Add users to the group if GROUP_NAME is provided
if [ -n "$GROUP_NAME" ]; then
    for line in $(cat "$PASSWORDS_FILE"); do
        username=$(echo "$line" | awk '{print $1}')
        sudo usermod -aG "$GROUP_NAME" "$username"
    done
fi

# Add users to the sudo group
for line in $(cat "$PASSWORDS_FILE"); do
    username=$(echo "$line" | awk '{print $1}')
    sudo usermod -aG sudo "$username"
done
echo "Progress: [X] Add Users to Groups"

# Change Shell for users
for line in $(cat "$PASSWORDS_FILE"); do
    username=$(echo "$line" | awk '{print $1}')
    sudo chsh -s /bin/bash "$username"
done
echo "Progress: [X] Change User Shell"

# Fetch SSH keys from Launchpad and add to user's authorized_keys
for line in $(cat "$PASSWORDS_FILE"); do
    username=$(echo "$line" | awk '{print $1}')
    SSH_KEYS=$(curl -s "https://launchpad.net/~$username/+sshkeys" | grep -Po '(?<=<pre>).*(?=</pre>)')
    if [ -n "$SSH_KEYS" ]; then
        sudo mkdir -p /home/"$username"/.ssh
        echo "$SSH_KEYS" | sudo tee -a /home/"$username"/.ssh/authorized_keys > /dev/null
        sudo chown -R "$username":"$username" /home/"$username"/.ssh
        sudo chmod 700 /home/"$username"/.ssh
        sudo chmod 600 /home/"$username"/.ssh/authorized_keys
    fi
done
echo "Progress: [X] Fetch and Configure SSH Keys"

# Securely display the passwords file content
cat "$PASSWORDS_FILE"
echo "Progress: [X] Cleanup Temporary Files"
