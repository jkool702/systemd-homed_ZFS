#!/usr/bin/bash

zfs_homed_umount() {

	local username
	local tries
	local nn	
	local zfsHomedRoot
	local -a zfsMounts

	# echo "running zfs_homed_umount" >&2

	zfsHomedRoot="$(zfs list -o name -H | grep -i -E 'HOMED$')"
	[[ -z "${zfsHomedRoot}" ]] && return 0

	username="${1}"
	tries=0

	if [[ -z "${username}" ]]; then
		mapfile -t zfsMounts < <( zfs get mounted -H -r ${zfsHomedRoot} | sed -E s/'mounted'//  | grep 'yes' | awk '{print $1}')
		
		while (( ${tries} < 200 )); do
			for nn in "${zfsMounts[@]}"; do
				[[ "$(zfs get -H -o value mounted "${nn}")" == 'no' ]] && username="${nn}" && break 
			done
			
			((tries++))
			[[ "$(zfs get -H -o value mounted "${username}")" == 'no' ]] && break 
			sleep 0.2s						
		done
	        username="$(echo "${username}" | awk -F '/' '{print $2}')"
	else
		while (( ${tries} < 500 )); do
			{ [[ "$(homectl inspect "${username}" | grep 'State' | sed -E s/'.*State\: '//)" == 'inactive' ]] && ! { dmsetup ls | grep -q -F "home-${username}" || cat /proc/mounts | grep -q -F "/dev/mapper/home-${username}"; } && ! zfs get mounted "${zfsHomedRoot}/${username}/data" -H -o value | grep -q 'yes'; } && break
			#[[ "$(zfs get -H -o value mounted "${username}")" == 'no' ]] && break 
			((tries++))
			sleep 0.2s
		done
	fi


	[[ "$(zfs get mounted "${zfsHomedRoot}/${username}/data" -H -o value)" == 'yes' ]] && zfs umount "${zfsHomedRoot}/${username}/data"
	[[ "$(zfs get mounted "${zfsHomedRoot}/${username}/data" -H -o value)" == 'yes' ]] &&  umount -l "$(zfs get -H -o value mountpoint "${zfsHomedRoot}/${username}/data")"

	[[ "$(zfs get keystatus "${zfsHomedRoot}/${username}/data" -H -o value)" == 'available' ]] && zfs unload-key "${zfsHomedRoot}/${username}/data"
	
	[[ "$(homectl inspect "${username}" | grep 'State' | sed -E s/'.*State\: '//)" == 'inactive' ]] || return 1
	
	cat /proc/mounts | grep -q -F "/dev/mapper/home-${username}" && umount "/dev/mapper/home-${username}"	
	cat /proc/mounts | grep -q -F "/dev/mapper/home-${username}" && umount -l "/dev/mapper/home-${username}"
	
	find /dev/mapper -mindepth 1 -maxdepth 1  | grep -q -F "home-${username}" && cryptsetup close "home-${username}"
	
	return 0
}


tmpfile_wrapper() {

	local tmpfile
	local pid_cur
	local -a tmpfile_waitlist
	local kk
	
	# make a tmpfile at /tmp/zfs-homed-umount/.tmpfiles/$USER-<...> and write pid to it
	
	pid_cur="$(echo $$)"
	
	tmpfile="$(mktmp --tmp-dir="/tmp/zfs-homed-umount/.tmpfiles" --base="${*// /}-")" || tmpfile="/tmp/zfs-homed-umount/.tmpfiles/${*// /}-x"
	
	echo "${pid_cur}" > "${tmpfile}"
	
	# JOB CONTROL - make sure only one instance of zfs_homed_mount runs at a time for a given user
	# gather all tmpfiles with the name $USER-<...> and sort oldest to youngest
	# If the oldest one holds this process' PID, continue. f not, find where this process is in the waitlist and wait for the process just before it in the waitlist to finish
	
	mapfile -t tmpfile_waitlist < <(find "${tmpfile%/*}" -type f -name "${*// /}"'*' -printf '%Cs %p\n' | sort | awk '{printf $1}')

	if [[ "$(cat "${tmpfile_waitlist[0]}")" != "${pid_cur}" ]]; then
		for kk in "${!tmpfile_waitlist[@]}"; do
			[[ "$(cat "${tmpfile_waitlist[${kk}]}")" == "${pid_cur}" ]] && wait -p "$(cat "${tmpfile_waitlist[$((( ${kk} - 1 )))]}")" && break
		done
	fi

	zfs_homed_umount "${@}" || echo "Home area for user ${*} either could not be accessed or could not be activated" >&2
	
	\rm -f "${tmpfile}"	
	
	return 0
}

dbus-monitor --monitor --system "path='/org/freedesktop/home1',member='DeactivateHome'" | while read -r dmsg; do 
	
	[[ -z $activateFlag ]] && activateFlag=false
	
	echo "${dmsg}" | grep -q "DeactivateHome" && activateFlag=true && continue
	echo "${dmsg}" | grep -q -E '^string \"\{.*\}\"$' && dmsg="" && continue

	if ${activateFlag}; then
		if echo "${dmsg}" | grep -q -E '^string \".+\"$'; then
			tmpfile_wrapper "$(echo "${dmsg}" | sed -E s/'^string \"(.+)\"$'/'\1'/)" 2>/dev/null &
		else
			tmpfile_wrapper 2>/dev/null &
		fi
	fi
	activateFlag=false
done	

return 1
