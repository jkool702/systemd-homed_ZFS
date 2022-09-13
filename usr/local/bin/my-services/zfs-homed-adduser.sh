#!/bin/bash

zfs_homed_adduser() {
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
	mkdir -p "${tmpdirMnt}"
	
	systemctl stop systemd-homed.service
	
	if [[ -d /etc/systemd/system/systemd-homed.service.d ]]; then
		mkdir -p "${tmpdirMnt}/systemd-homed.service.d"
		cp -a /etc/systemd/system/systemd-homed.service.d/*  "${tmpdirMnt}/systemd-homed.service.d"
		systemctl revert systemd-homed.service
	fi
	
	systemctl disable systemd-homed-zfs-mount.service
	systemctl disable systemd-homed-zfs-umount.service
	systemctl mask systemd-homed-zfs-mount.service
	systemctl mask systemd-homed-zfs-umount.service
	systemctl enable systemd-homed.service
	systemctl start systemd-homed.service
	
	if zfs list -H -o name | grep -q -F "${zfsHomedRoot}/${username}"; then
		zfs set mountpoint=none "${zfsHomedRoot}/${username}"
	else
		zfs create -p -o mountpoint=none "${zfsHomedRoot}/${username}" 
	fi
	
	if ! zpool get -H -o value altroot "${zfsHomedRoot%%/*}" | grep -q '-'; then
	       for nn in /home/*; do
			cat /proc/mounts | grep -q -F "/sysroot${nn}" || mount -o bind,rw "${nn}" "/sysroot${nn}"
			chown "${nn##*/}":"${nn##*/}" "/sysroot${nn}"
	       done
	       mount -o bind,rw  "$(zpool get -H -o value altroot "${zfsHomedRoot%%/*}")/home" /home
	fi

	zfs create -s -V $(zpool get -H -o value -p size "${zfsHomedRoot%%/*}") "${zfsHomedRoot}/${username}/key" 

	setenforce 0
	
	homectl create --home-dir="/home/${username}" --member-of=wheel --disk-size=1G --storage=luks --image-path="/dev/zvol/${zfsHomedRoot}/${username}/key" --fs-type=btrfs --auto-resize-mode="shrink-and-grow" --luks-cipher=aes --luks-cipher-mode=xts-plain64 --luks-volume-key-size=64 --luks-pbkdf-type=argon2id --kill-processes=true "${username}"
	
	homectl authenticate "${username}"
	homectl activate "${username}"
	
	mkdir -p "/home/${username}/.zfs"
	
	openssl rand -out "/home/${username}/.zfs/key.zfs" 32
	
	zfs create -o mountpoint=none -o encryption=aes-256-gcm -o keyformat=raw -o keylocation="file:///home/${username}/.zfs/key.zfs" "${zfsHomedRoot}/${username}/data" 
	
	zfs load-key "${zfsHomedRoot}/${username}/data" 
	
	#mount -o bind,rw "/home/${username}" "${tmpdirMnt}"
	
	umount "/dev/mapper/home-${username}"
	cat /proc/mounts | grep -q -F "/dev/mapper//home-${username}" && umount -l "/dev/mapper//home-${username}"
	
	zfs set mountpoint="/home/${username}" "${zfsHomedRoot}/${username}/data" 
	zfs get -H -o value mounted "${zfsHomedRoot}/${username}/data" | grep -q 'yes' || zfs mount "${zfsHomedRoot}/${username}/data" 
	
	mapfile -t mvFiles < <(find "${tmpdirMnt}" -maxdepth 1 | grep -v -F '.zfs' | grep -v -F '.identity')
	
	\cp -af "${mvFiles[@]}" "/home/${username}"
	
	ln -s "/var/lib/systemd/home/${username}.identity" "/home/${username}/.identity"
	#touch "/home/${username}/.identity"
	#mount -o bind,rw "${tmpdirMnt}/.identity"  "/home/${username}/.identity"
	umount "${tmpdirMnt}"
	cat /proc/mounts | grep -q -F "${tmpdirMnt}" && umount -l "${tmpdirMnt}"
	
	homectl deactivate "${username}"
	
	zfs unload-key "${zfsHomedRoot}/${username}/data" 
	
	[[ -d "${tmpdirMnt}/systemd-homed.service.d" ]] && mkdir -p /etc/systemd/system/systemd-homed.service.d/ && cp -a "${tmpdirMnt}/systemd-homed.service.d"/* "/etc/systemd/system/systemd-homed.service.d/"
	
	systemctl stop systemd-homed.service
	systemctl unmask systemd-homed-zfs-mount.service
	systemctl unmask systemd-homed-zfs-umount.service
	systemctl enable systemd-homed-zfs-mount.service 2>/dev/null
	systemctl enable systemd-homed-zfs-umount.service 2>/dev/null
	systemctl enable systemd-homed.service
	systemctl start systemd-homed.service
	
	
	homectl activate "${username}"
	
}

zfs_homed_adduser "${@}"
