#!/bin/bash

# New public key to add
NEW_PUBLIC_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAr..."

# User to update
TARGET_USER="Username"

# List of servers
SERVERS=("server1" "server2" "server3")

# Loop through the servers and update authorized_keys
for SERVER in "${SERVERS[@]}"; do
    echo "Updating key on $SERVER for user $TARGET_USER..."
    
    ssh -o StrictHostKeyChecking=no $SERVER "sudo mkdir -p /home/$TARGET_USER/.ssh && \
        sudo touch /home/$TARGET_USER/.ssh/authorized_keys && \
        sudo chmod 700 /home/$TARGET_USER/.ssh && \
        sudo chmod 600 /home/$TARGET_USER/.ssh/authorized_keys && \
        grep -q \"$NEW_PUBLIC_KEY\" /home/$TARGET_USER/.ssh/authorized_keys || \
        echo \"$NEW_PUBLIC_KEY\" | sudo tee -a /home/$TARGET_USER/.ssh/authorized_keys > /dev/null && \
        sudo chown -R $TARGET_USER:$TARGET_USER /home/$TARGET_USER/.ssh"
    
    if [ $? -eq 0 ]; then
        echo "Key updated successfully on $SERVER."
    else
        echo "Failed to update key on $SERVER."
    fi
done
