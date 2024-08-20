
### Description of Functions

**launchpad_admin_import.sh**
- **check_launchpad_user**: Validates if the Launchpad user exists.
- **import_ssh_keys**: Imports SSH keys from Launchpad.
- **Prompt for users and group**: Collects Launchpad usernames and group names from the user.
- **Generate passwords**: Creates random passwords for the users.
- **Create group**: Adds the group if it does not already exist.
- **Create users**: Adds users if they do not already exist.
- **Set passwords**: Assigns the generated passwords to the users.
- **Add to groups**: Adds users to the specified group and `sudo` group.
- **Change shell**: Sets the default shell to Bash.
- **Import SSH keys**: Imports SSH keys for each user from Launchpad.
- **Display passwords**: Outputs usernames and passwords in a formatted table.
- **cleanup**: Removes temporary password file upon script exit.

**secure-user-setup-rhel-debian.sh**
- **Prompt for users and group**: Collects usernames and group names from the user.
- **Generate passwords**: Creates random passwords for the users.
- **Create group**: Adds the group if it does not already exist.
- **Create users**: Adds users if they do not already exist.
- **Set passwords**: Assign the generated passwords to the users.
- **Add to groups**: Adds users to the specified group and `sudo` group.
- **Change shell**: Sets the default shell to Bash.
- **Display passwords**: Outputs usernames and passwords in a formatted table.
- **cleanup**: Removes temporary password file upon script exit.

# Part 1: Creating SSH Keys on Windows

## 1. Open PowerShell:
- Press `Win + X`, then press `A` to open PowerShell as an administrator.
- Type the following command and press `Enter`:
  ```bash
  ssh-keygen -t rsa -b 4096 -C "your_email@example.com"

## 2.  Save the SSH Key Pair:
- You will be prompted to "Enter file in which to save the key."
- Press Enter to accept the default location (C:\Users\YourUsername\.ssh\id_rsa).
- It is recommended that the default location be used to avoid potential issues with access permissions.
- It is recommended to protect the private key with a passphrase. Ensure it is strong but memorable, and consider backing it up securely (e.g., in Zoho) for your protection.

## 3. Copy the Public Key to Your Clipboard:
- Run the following command in PowerShell:
  ```bash
  Get-Content -Path "$env:USERPROFILE\.ssh\id_rsa.pub" | Set-Clipboard

This will copy the contents of your public key (id_rsa.pub) to the clipboard.

# Part 2: Uploading SSH Key to Launchpad or GitHub

## For GitHub:

1. **Log in to GitHub:**
   - Go to [GitHub](https://github.com) and log in with your account.

2. **Navigate to SSH and GPG Keys:**
   - In the upper-right corner, click on your profile picture, then click `Settings`.
   - In the left-hand menu, select `SSH and GPG keys`.

3. **Add New SSH Key:**
   - Click the `New SSH key` button.
   - In the "Title" field, add a descriptive name for the key (e.g., "My Laptop").
   - Paste the SSH public key (copied earlier) into the "Key" field.
   - Click `Add SSH key` to save.

## For Launchpad:

1. **Log in to Launchpad:**
   - Go to [Launchpad](https://launchpad.net/) and log in with your account.

2. **Navigate to SSH Keys:**
   - Click on your profile picture in the top right corner and select `Account details`.
   - In the account settings, find and click on `SSH Keys`.

3. **Add a New SSH Key:**
   - Click `Add an SSH key`.
   - Paste the SSH public key (copied earlier) into the text box.
   - Click `Import Public Key` to save.

# Part 3: Deploy Users and Their Associated Public Keys to a Linux Host

### Usage Instructions

**launchpad_admin_import.sh**

```bash
git clone https://github.com/cooperactive/linux-user-creator.git
cd linux-user-creator/
chmod +x *.sh
sudo ./launchpad_admin_import.sh

***Follow the Interactive Instructions***

