# systemd-homed_ZFS
This repo contains scripts and systemd services that make it possible to use systemd-homed in "LUKS" mode to automatically decrypt and lock a home directory on an encrypted ZFS dataset


# How it works

This method sets up a "master" ZFS dataset called `<...>/HOMED` (not mounted) and, for each user, 3 additional zfs datasets:
* a standard ZFS dataset at `<...>/HOMED/$USER` (not mounted)
* a zfs volume (without reservation) at `<...>/HOMED/$USER/key` (backing block device for systemd-homed LUKS partition)
* an encrypted zfs dataset at `<...>/HOMED/$USER/data` using a keyfile (present on the LUKS partition at `<...>/HOMED/$USER/key`) (mounted to `/home/$USER`)

To set things up, you can run  `zfs-homed-adduser.sh $USER`. Here is a brief overview of the setup required to make everything work:

1. create the `<...>/HOMED/$USER` ZFS dataset and `<...>/HOMED/$USER/key` ZFS volume. 
2. run `homectl create --imagefile=/dev/zvol/<...>/HOMED/$USER/key <...> $USER`. This will set the ZFS volume as the backing block device for the systemd-homed LUKS volume and generate the systemd-homed btrfs-on-LUKS home directory.
3. mount the home directory (via `homectl activate $USER`), and create a keyfile on it (via `openssl rand -out /home/$USER/.zfs/key.zfs 32`)
4. create the encrypted zfs volume and set it to use the keyfile you just made as the encryptionm key (add `-o encryption=aes-256-gcm -o keyformat=raw -o keylocation="file:///home/$USER/.zfs/key.zfs` to the `zfs create` command)
5. install the 2 systemd helper services to `/usr/lib/systemd/system` and enable them. These help to automatically mount/umount and load/unload the keys for the encrypted ZFS dataset `<...>/HOMED/$USER/data`.

In particular, the 2 systemd helper services are triggered (via `dbus-monitor`) when the home directory is activated/deactivated by `homectl`. When activated, the systemd helper service umounts the systemd-homed btrfs-on-LUKS home directory and mounts the encrypted zfs dataset `<...>/HOMED/$USER/data` in its place. When deactivated, systemd-homed will natively umount `<...>/HOMED/$USER/data` and lock the btrfs-on-LUKS volume containing it's keyfile, and the systemd helper service will unload the key from the encrypted zfs dataset.
