#!/bin/bash

zfs_setup_homed_datasets() {
# CREATES THE REQUIRED ZFS DATASETS AND VOLUMES FOR A GIVES USER
# $1 is user name. If missing you will be prompted for one
# $2 is the ZFS root for homed stuff. Must be called HOMED and given as <POOL>/<...>/HOMED. 
# 		If missing it will look for a pre-existing ZFS dataset called HOMED. 
# 		If found it will use it, otherwise you will be prompted for one.


	local username
	local zfsHomedRoot
	
	
	username="${1}"
	echo "${2}" | grep -q -i -e 'HOMED$' && zfsHomedRoot="${2}"
	
	[[ -z ${username} ]] && read -p "Enter username to create: " username
	[[ -z ${zfsHomedRoot} ]] && zfs list -H -o value name -a | grep -q -i -E 'HOMED$' && zfsHomedRoot="$(zfs list -H -o value name -a | grep -i -E 'HOMED$')"
	while [[ -z ${zfsHomedRoot} ]] || ! echo "${zfsHomedRoot}" | grep -q -i -E 'HOMED$'; do
		read -p "Enter ZFS dataset name to use as root HOMED directory: " zfsHomedRoot
		echo "${zfsHomedRoot}" | grep -q -i -E 'HOMED$' || echo "invalid dataset name. Must be of the form <POOL>/<...>/HOMED" >&2
	done
		
	if zfs list -H -o value name -a | grep -q -F "${zfsHomedRoot}/${username}"; then
		zfs set mountpoint=none "${zfsHomedRoot}/${username}"
	else
		zfs create -p -o mountpoint=none "${zfsHomedRoot}/${username}" 
	fi
	
	zfs create -s -V "${zfsHomedRoot}/${username}/key" $(zfs get -H -o value -p size "${zfsHomedRoot%%/*}")
	
	systemctl enable systemd-homed.service
	
	setenforce 0
	
	homectl create --home-dir="/home/${username}" --member-of=wheel --disk-size=1G --storage=luks --image-path="/dev/zvol/${zfsHomedRoot}/${username}/key" --fs-type=btrfs --auto-resize-mode="shrink-and-grow" --luks-cipher=aes --luks-cipher-mode=xts-plain64 --luks-volume-key-size=64 --luks-pbkdf-type=argon2id --kill-processes=true "${username}"
	
	homectl activate "${username}"
	
	mkdir "/home/${username}/.zfs"
	
	openssl rand -out "/home/${username}/.zfs/key.zfs" 32
	
	zfs create -n -o mountpoint="/home/${username}" -o encryption=aes-256-gcm -o keyformat=raw -o keylocation="file:///home/${username}/.zfs/key.zfs" "${zfsHomedRoot}/${username}/data" 
	
	zfs load-key "${zfsHomedRoot}/${username}/data" 
	
	mkdir "/tmp/home-${username}"
	
	cp -a "/home/${username}"/* "/home/${username}"/.*  "/tmp/home-${username}"
	
	umount "/dev/mapper/home-${username}"
	cat /proc/mounts | grep -q -F "/dev/mapper/home-${username}" && umount -l "/dev/mapper/home-${username}"
	
	zfs mount "${zfsHomedRoot}/${username}/data" 
	
	cp -a "/tmp/home-${username}"/* "/tmp/home-${username}"/.* "/home/${username}"
	
	rm -rf "/tmp/home-${username}"
	
	homectl deactivate "${username}"
	
}

zfs_setup_homed_datasets "${@}"