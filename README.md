# Incremental backup from remote
## Introduction
A script running allowing to do backup from a remote device (server) to a local device (client). The script is run on device B.
The script uses `rsync` for the backup and connects using `ssh` with public/private identity keys.

I created this script because I needed a way to backup my NAS and my Raspberry to an external device - located at my parents' - if anything would happen (fire, burglary, disk corruption, ...). 

## Features
- Multiple folders
- Exclude files/folders
- Incremental backup
- Sends email report (requires email account)
- Sends email alert on low space on backup drive

## Installation
### Setup identity keys
On the machine doing the backup (local device), create the identity files
```
ssh-keygen -t ed25519 -C "<your email>"
```
1. Choose path and name of the identity files (or just press enter: the files will be written as `~/.ssh/id_ed25519`)
2. Choose password: leave blank (press enter)

Copy the content of the file `~/.ssh/id_ed25519.pub` (public key).

On the remote device, login as a user having at least read access to the files/folders you want to backup. Paste the public key at the end of the file `~/.ssh/authorized_keys` (create file if it doesn't exist).

To check if the connection works, login to local device and type the command below.
```
ssh -i ~/.ssh/id_ed25519 <username on remote>@<ip or domain>
```
If the connection fails or if you are asked for a password, make sure that the following lines aren't commented in `/etc/ssh/sshd_config` on distant device:
```
PubkeyAuthentication yes
AuthorizedKeysFile  .ssh/authorized_keys
```
If your changed the file, reload the daemon:
```
sudo systemctl restart sshd
```
If you still cannot connect or are prompted for a password, try the set the privileges on the following folders and files to 700 :
- /var/services/home/<username>
- /var/services/home/<username>/.ssh
- /var/services/home/<username>/.ssh/authorized_keys
- /volume1/homes/<username>
```
USERNAME=<username>
cd /var/services/home
chmod 700 "${USERNAME}" "${USERNAME}/.ssh" "${USERNAME}/.ssh/authorized_keys" "/volume1/homes/${USERNAME}"
```
> On a synology NAS, _root_ is not allowed running rsync over ssh so make sure you are using another user in _admin_ group


### Setup script on local device
1. Copy the script rsync_ to optional folder on the device where the backup is going (local device).
2. Set the file executable: `chmod +x rsync.sh`
3. Modify the script to fit your needs, i.e. change de constants in the first part using vi/vim/nano/... The script is well commented, you wouldn't have any difficulties doing this.

> If you want to backup multiple devices, copy the script multiple time (i.e. rsync_backup_device_A.sh,  rsync_backup_device_B, ...).

Try running the script:
```
/bin/bash <path to script>
```
The script creates a log-file in the same folder as the script (`script_file_name.log`)..

### Schedule periodic backup
On the local device, edit the crontab:
```
sudo crontab -e
```
Add this line:
```
0 1 * * 3,6 /bin/bash <path to script> # Will run at 1 am twice a week (wednesday and saturday). Search the internet for crontab syntax
```
Save and exit

> _crontab_ is running as root, make sure the path to the file is valid as the user `root`.

