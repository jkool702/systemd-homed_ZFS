#!/bin/bash

zfs_setup_homed_datasets() {
# CREATES THE REQUIRED ZFS DATASETS AND VOLUMES FOR A GIVES USER
# $1 is user name. If missing you will be prompted for one
# $2 is the ZFS root for homed stuff. Must be called HOMED and given as <POOL>/<...>/HOMED. 
# 		If missing it will look for a pre-existing ZFS dataset called HOMED. 
# 		If found it will use it, otherwise you will be prompted for one.


	local username
	local zfsHomedRoot
	local tmpdirMnt
	local mvFiles
	
	username="${1}"
	echo "${2}" | grep -q -i -e 'HOMED$' && zfsHomedRoot="${2}"
	
	[[ -z ${username} ]] && read -p "Enter username to create: " username
	[[ -z ${zfsHomedRoot} ]] && zfs list -H -o name | grep -q -i -E 'HOMED$' && zfsHomedRoot="$(zfs list -H -o name | grep -i -E 'HOMED$')"
	while [[ -z ${zfsHomedRoot} ]] || ! echo "${zfsHomedRoot}" | grep -q -i -E 'HOMED$'; do
		read -p "Enter ZFS dataset name to use as root HOMED directory: " zfsHomedRoot
		echo "${zfsHomedRoot}" | grep -q -i -E 'HOMED$' || echo "invalid dataset name. Must be of the form <POOL>/<...>/HOMED" >&2
	done

	
	tmpdirMnt="$(mktmp -p "/tmp/homed_zfs_adduser" -b "home-${username}-" -D)" || tmpdirMnt="/tmp/homed_zfs_adduser/home-${username}"
	
	if zfs list -H -o name | grep -q -F "${zfsHomedRoot}/${username}"; then
		zfs set mountpoint=none "${zfsHomedRoot}/${username}"
	else
		zfs create -p -o mountpoint=none "${zfsHomedRoot}/${username}" 
	fi
	
	zpool get -H -o value altroot "${zfsHomedRoot%%/*}" | grep -q '-' || mount -o bind,rw "/home/${username}" "$(zpool get -H -o value altroot "${zfsHomedRoot%%/*}")/home/${username}"
	
	zfs create -s -V $(zpool get -H -o value -p size "${zfsHomedRoot%%/*}") "${zfsHomedRoot}/${username}/key" 
	
	systemctl enable systemd-homed.service
	systemctl mask systemd-homed-zfs-mount.service
	
	setenforce 0
	
	homectl create --home-dir="/home/${username}" --member-of=wheel --disk-size=1G --storage=luks --image-path="/dev/zvol/${zfsHomedRoot}/${username}/key" --fs-type=btrfs --auto-resize-mode="shrink-and-grow" --luks-cipher=aes --luks-cipher-mode=xts-plain64 --luks-volume-key-size=64 --luks-pbkdf-type=argon2id --kill-processes=true "${username}"
	
	homectl authenticate "${username}"
	homectl activate "${username}"
	
	mkdir -p "${tmpdirMnt}"
	
	mkdir -p "/home/${username}/.zfs"
	
	openssl rand -out "/home/${username}/.zfs/key.zfs" 32
	
	zfs create -o mountpoint=none -o encryption=aes-256-gcm -o keyformat=raw -o keylocation="file:///home/${username}/.zfs/key.zfs" "${zfsHomedRoot}/${username}/data" 
	
	zfs load-key "${zfsHomedRoot}/${username}/data" 
	
	mount -o bind,rw /home/${username}" "${tmpdirMnt}"
	
	umount "/home/${username}"
	cat /proc/mounts | grep -q -F "/home/${username}" && umount -l "/home/${username}"
	
	zfs set mountpoint="/home/${username}" "${zfsHomedRoot}/${username}/data" 
	zfs get -H -o value mounted "${zfsHomedRoot}/${username}/data" | grep -q 'yes' || zfs mount "${zfsHomedRoot}/${username}/data" 
	
	mapfile -t mvFiles < <(find "${tmpdirMnt}" -maxdepth 1 | grep -v '.zfs' | grep -v '.identity')
	
	\cp -af "${mvFiles[@]}" "/home/${username}"
	touch "/home/${username}/.identity'
	
	mount -o bind,rw "${tmpdirmnt}/.identity"  "/home/${username}/.identity'
	umount "${tmpdirmnt}"
	cat /proc/mounts | grep -q -F "${tmpdirmnt}" && umount -l "${tmpdirmnt}"
	
	homectl deactivate "${username}"
	
	
	systemctl unmask systemd-homed-zfs-mount.service
	systemctl enable systemd-homed-zfs-mount.service 2>/dev/null
	systemctl restart systemd-homed.service
	
}

zfs_setup_homed_datasets "${@}"
