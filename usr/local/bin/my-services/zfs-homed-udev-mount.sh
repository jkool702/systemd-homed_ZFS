#!/usr/bin/bash

zfs_homed_mount() {

	local username
	local zfsHomedRoot

	
	# echo "running zfs_homed_mount" >&2

	# if no zfs dataset named HOMED exists then exit
	zfsHomedRoot="$(zfs list -o name -H | grep -i -E 'HOMED$')"
	[[ -z ${zfsHomedRoot} ]] && return 0

	#username="$(udevadm info -p "${*}" | grep 'DM_NAME=home-' | sed -E s/'^E\: DM_NAME\=home-'//)"
	username="${1}"
	[[ -z ${username}} ]] && return 0

	# if ZFS homedir is already mounted and the identity file already bind-mounted then this is a unneeded duplicate call, so return
	{ [[ "$(zfs get mounted "${zfsHomedRoot}/${username}/data" -H -o value)" == 'yes' ]] && cat /proc/mounts | grep -q -F "/home/${username}/.identity"; }  && return 0
	
	{ [[ "$(homectl inspect "${username}" | grep 'State' | sed -E s/'.*State\: '//)" == 'active' ]] || dmsetup ls | grep -q -F "home-${username}"; } || return 1
	
	
	if [[ "$(zfs get keystatus "${zfsHomedRoot}/${username}/data" -H -o value)" != 'available' ]]; then
       ! { [[ -f $(zfs get -H -o value keylocation "${zfsHomedRoot}/${username}/data") ]] || cat /proc/mounts | grep -q -F '/dev/mapper/home-'"${username}"; } && mount "/dev/mapper/home-${username}" "/home/${username}" -o subvol="/${username}"
            
        zfs load-key "${zfsHomedRoot}/${username}/data"
    fi
    
    cat /proc/mounts | grep -q -F "/dev/mapper/home-${username}" && umount "/dev/mapper/home-${username}" 
	sleep 0.2s
	
	cat /proc/mounts | grep -q -F "/dev/mapper/home-${username}" && umount -l "/dev/mapper/home-${username}"
	sleep 0.2s

	cat /proc/mounts | grep -q -F "/home/${username}" && umount "/home/${username}"
	sleep 0.2s

	cat /proc/mounts | grep -q -F "/home/${username}" && umount -l "/home/${username}"
    sleep 0.2s
	
	# mount zfs dataset to /home/$username
	[[ "$(zfs get mounted "${zfsHomedRoot}/${username}/data" -H -o value)" == 'yes' ]] || zfs mount "${zfsHomedRoot}/${username}/data" 2>/dev/null
	sleep 0.2s
	
	# echo "mounted ZFS home directory to /home/${username}" >&2

	return 0
}

zfs_homed_mount "${*}"
