#!/usr/bin/bash

zfs_homed_mount() {

	local username
	local tries
	local zfsHomedRoot

	# echo "running zfs_homed_mount" >&2

	zfsHomedRoot="$(zfs list -o name -H | grep -i -E 'HOMED$')"
	[[ -z ${zfsHomedRoot} ]] && return 0

	username="${1}"
	tries=50


	if [[ -z "${username}" ]]; then
		while (( ${tries} > 0 )); do
                	username="$(find /home/*/.zfs/key.zfs -type f 2>/dev/null)" && break
			((tries--))
			sleep 0.2s
			
		done
	        username="$(echo "${username}" | awk -F '/' '{print $3}')"
	else
		[[ "$(zfs get mounted "${zfsHomedRoot}/${username}/data" -H -o value)" == 'yes' ]] && zfs umount "${zfsHomedRoot}/${username}/data"
		while (( ${tries} > 0 )); do
			[[ "$(homectl inspect "${username}" | grep 'State' | sed -E s/'.*State\: '//)" == 'active' ]] && break
			# [[ -f "$(zfs get keylocation "${zfsHomedRoot}/${username}/data" -H -o value | sed -E s/'^file\:\/\/'//)" ]] && break
			sleep 0.2s
		done
	fi

	{ [[ -z "${username}" ]] || ! [[ -d "/home/${username}" ]]; } && return 1
	[[ "$(homectl inspect "${username}" | grep 'State' | sed -E s/'.*State\: '//)" == 'active' ]] || return 1

	[[ "$(zfs get keystatus "${zfsHomedRoot}/${username}/data" -H -o value)" == 'available' ]] || zfs load-key "${zfsHomedRoot}/${username}/data"
	
	mkdir -p "/tmp/zfs-homed-mount/home-${username}"
	
	# touch "/tmp/zfs-homed-mount/home-${username}/.identity"
	# mount -o bind,rw "/home/${username}" "/tmp/zfs-homed-mount/home-${username}"
	# umount "/dev/mapper/home-${username}"
	
	mount -o move "/home/${username}" "/tmp/zfs-homed-mount/home-${username}"
	
	cat /proc/mounts | grep -q -F "/dev/mapper/home-${username}" && umount -l "/dev/mapper/home-${username}"
	sleep 0.5s

	[[ "$(zfs get mounted "${zfsHomedRoot}/${username}/data" -H -o value)" == 'yes' ]] || zfs mount "${zfsHomedRoot}/${username}/data"
	
	[[ -f "/home/${username}/.identity" ]] || touch "/home/${username}/.identity"
	
	mount -o bind,rw "/tmp/zfs-homed-mount/home-${username}/.identity" "/home/${username}/.identity"
	umount "/tmp/zfs-homed-mount/home-${username}"

	chown "${username}":"${username}" "/home/${username}/.identity"

	# echo "mounted ZFS home directory to /home/${username}" >&2

	return 0
}

dbus-monitor --monitor --system "path='/org/freedesktop/home1',member='ActivateHome'" | while read -r dmsg; do 
	
	[[ -z $activateFlag ]] && activateFlag=false
	
	echo "${dmsg}" | grep -q "ActivateHome" && activateFlag=true && continue
	echo "${dmsg}" | grep -q -E '^string \"\{.*\}\"$' && dmsg="" && continue

	if ${activateFlag}; then
		if echo "${dmsg}" | grep -q -E '^string \".+\"$'; then
			zfs_homed_mount "$(echo "${dmsg}" | sed -E s/'^string \"(.+)\"$'/'\1'/)" 2>/dev/null &
		else
			zfs_homed_mount 2>/dev/null &
		fi
	fi
	activateFlag=false
done	

return 1
