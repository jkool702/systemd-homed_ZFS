#!/usr/bin/bash

zfs_homed_umount() {

	local username
	local tries
	local nn	local zfsHomedRoot

	# echo "running zfs_homed_umount" >&2

	zfsHomedRoot="$(zfs list -o name -H | grep -i -E 'HOMED$')"
	[[ -z ${zfsHomedRoot} ]] && return 0

	username="${1}"
	tries=50

	[[ "$(zfs get mounted "${zfsHomedRoot}/${username}/data" -H -o value)" == 'yes' ]] && zfs umount "${zfsHomedRoot}/${username}/data"

	if [[ -z "${username}" ]]; then
		mapfile -t zfsMounts < <( zfs get mounted -H -r ${zfsHomedRoot} | sed -E s/'mounted'//  | grep 'yes' | awk '{print $1}')
		while (( ${tries} > 0 )); do
			for nn in "${zfsMounts[@]}"; do
				[[ "$(zfs get -H -o value mounted "${nn}")" == 'no' ]] && username="${nn}" && break 
				((tries--))
				sleep 0.2s
			done			
			[[ "$(zfs get -H -o value mounted "${username}")" == 'no' ]] && break 
		done
	        username="$(echo "${username}" | awk -F '/' '{print $2}')"
	else
		while (( ${tries} > 0 )); do
			[[ "$(homectl inspect "${username}" | grep 'State' | sed -E s/'.*State\: '//)" == 'inactive' ]] && break
			#[[ "$(zfs get -H -o value mounted "${username}")" == 'no' ]] && break 
			sleep 0.2s
		done
	fi

	[[ "$(homectl inspect "${username}" | grep 'State' | sed -E s/'.*State\: '//)" == 'inactive' ]] || return 1

	[[ "$(zfs get mounted "${zfsHomedRoot}/${username}/data" -H -o value)" == 'yes' ]] && zfs umount "${zfsHomedRoot}/${username}/data"

	[[ "$(zfs get keystatus "${zfsHomedRoot}/${username}/data" -H -o value)" == 'available' ]] && zfs unload-key "${zfsHomedRoot}/${username}/data"

	return 0
}

dbus-monitor --monitor --system "path='/org/freedesktop/home1',member='DeactivateHome'" | while read -r dmsg; do 
	
	[[ -z $activateFlag ]] && activateFlag=false
	
	echo "${dmsg}" | grep -q "DeactivateHome" && activateFlag=true && continue
	echo "${dmsg}" | grep -q -E '^string \"\{.*\}\"$' && dmsg="" && continue

	if ${activateFlag}; then
		if echo "${dmsg}" | grep -q -E '^string \".+\"$'; then
			zfs_homed_umount "$(echo "${dmsg}" | sed -E s/'^string \"(.+)\"$'/'\1'/)" 2>/dev/null &
		else
			zfs_homed_umount 2>/dev/null &
		fi
	fi
	activateFlag=false
done	
