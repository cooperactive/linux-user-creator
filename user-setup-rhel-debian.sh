#!/bin/bash

# Prompt for users
read -p "Enter the usernames (space-separated): " USERS

# Prompt for the group name
read -p "Enter the group name: " GROUP_NAME

# Define the file path to save the usernames and passwords
PASSWORDS_FILE="created.txt"

# Create a file to store usernames and passwords
touch "$PASSWORDS_FILE"

# Loop through the list of usernames
for user in $USERS; do
    # Generate a random password
    password=$(openssl rand -base64 10 | tr -d "=+/")
    
    # Append username and password to the file
    echo "$user $password" >> "$PASSWORDS_FILE"
done

# Create group
sudo groupadd "$GROUP_NAME"

IFS=$'\n'
lst1=$(cat "$PASSWORDS_FILE")
for i in $lst1; do
    a1=$(echo "$i" | awk '{print $1}')
    sudo useradd -m "$a1"
    a2=$(echo "$i" | awk '{print $2}')
    echo -e "$a2\n$a2" | sudo passwd "$a1"

    # Add users to respective groups
    sudo usermod -aG "$GROUP_NAME",sudo "$a1"
done

# Change Shell for users
for user in $USERS; do
    sudo chsh -s /bin/bash "$user"
done
