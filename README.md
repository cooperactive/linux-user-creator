
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


### Usage Instructions

Ensure both scripts are executable:

```bash
git clone https://github.com/cooperactive/linux-user-creator.git
cd linux-user-creator/
chmod +x *.sh
sudo ./launchpad_admin_import.sh

