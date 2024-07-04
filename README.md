
### Description of Functions

**secure-user-setup-rhel-debian.sh**
- **cleanup**: Removes temporary password file upon script exit.
- **Prompt for users and group**: Collects usernames and group name from the user.
- **Generate passwords**: Creates random passwords for the users.
- **Create group**: Adds the group if it does not already exist.
- **Create users**: Adds users if they do not already exist.
- **Set passwords**: Assigns the generated passwords to the users.
- **Add to groups**: Adds users to the specified group and `sudo` group.
- **Change shell**: Sets the default shell to Bash.
- **Display passwords**: Outputs usernames and passwords in a formatted table.

**launchpad_admin_import.sh**
- **cleanup**: Removes temporary password file upon script exit.
- **check_launchpad_user**: Validates if the Launchpad user exists.
- **import_ssh_keys**: Imports SSH keys from Launchpad.
- **Prompt for users and group**: Collects Launchpad usernames and group name from the user.
- **Generate passwords**: Creates random passwords for the users.
- **Create group**: Adds the group if it does not already exist.
- **Create users**: Adds users if they do not already exist.
- **Set passwords**: Assigns the generated passwords to the users.
- **Add to groups**: Adds users to the specified group and `sudo` group.
- **Change shell**: Sets the default shell to Bash.
- **Import SSH keys**: Imports SSH keys for each user from Launchpad.
- **Display passwords**: Outputs usernames and passwords in a formatted table.

### Usage Instructions

Ensure both scripts are executable:

```bash
chmod +x secure-user-setup-rhel-debian.sh
chmod +x secure-launchpad-user-setup.sh
