#!/usr/bin/bash

zfs_homed_mount() {

	local username
	local tries
	local zfsHomedRoot
	local tmpdir
	#local mntOpts
	
	# echo "running zfs_homed_mount" >&2

	# if no zfs dataset named HOMED exists then exit
	zfsHomedRoot="$(zfs list -o name -H | grep -i -E 'HOMED$')"
	[[ -z ${zfsHomedRoot} ]] && return 0

	username="${1}"
	tries=0

	# wait for systemd-homed to finish activating the users home
	# if given user name wait up to 100 sec. If not given user name, wait up to 10 sec
	if [[ -z "${username}" ]]; then
	
		# If username not given, monitor /home for the appearance of a keyfile. This should only be present after systemd-homed has finished activating but before the ZFS home dir is mounted. It appearing probably means that is the user whose home area was just activated.
		while (( ${tries} < 50 )); do
			username="$(find /home/*/.zfs/key.zfs -type f 2>/dev/null)" && break
			
			((tries++))
			sleep 0.2s
		done
		username="$(echo "${username}" | awk -F '/' '{print $3}')"
		
		# if ZFS homedir is already mounted and the identity file already bind-mounted then this is a unneeded duplicate call, so return
		{ [[ "$(zfs get mounted "${zfsHomedRoot}/${username}/data" -H -o value)" == 'yes' ]] && cat /proc/mounts | greq -q -F "/home/${username}/.identity"; } && return 0
		
	else
		# if ZFS homedir is already mounted and the identity file already bind-mounted then this is a unneeded duplicate call, so return
		{ [[ "$(zfs get mounted "${zfsHomedRoot}/${username}/data" -H -o value)" == 'yes' ]] && cat /proc/mounts | greq -q -F "/home/${username}/.identity"; }  && return 0
		while (( ${tries} < 500 )); do
		
			# wait until homed considers the home area active and/or the /dev/mapper/home-$username device appears and is mounted to /home/$username or the zfs keyfile appears
			{ [[ "$(homectl inspect "${username}" | grep 'State' | sed -E s/'.*State\: '//)" == 'active' ]] || { dmsetup ls | grep -q -F "home-${username}" && cat /proc/mount | grep -F "/dev/mapper/home-${username}" | grep -q -F "/home/${username}"; } || [[ -f "$(zfs get keylocation "${zfsHomedRoot}/${username}/data" -H -o value | sed -E s/'^file\:\/\/'//)" ]]; } && break

				((tries++))
			sleep 0.2s
		done
	fi

	# if we couldnt get a username, or have a username no /home/$username exists, or systemd-homed couldnt activate it, then return with error exit status
	{ [[ -z "${username}" ]] || ! [[ -d "/home/${username}" ]]; } && return 1
	{ [[ "$(homectl inspect "${username}" | grep 'State' | sed -E s/'.*State\: '//)" == 'active' ]] || dmsetup ls | grep -q -F "home-${username}"; } || return 1
	
	# if ZFS homedir is already mounted and the identity file already bind-mounted then this is a unneeded duplicate call, so return
	{ [[ "$(zfs get mounted "${zfsHomedRoot}/${username}/data" -H -o value)" == 'yes' ]] && cat /proc/mounts | greq -q -F "/home/${username}/.identity"; }  && return 0
	
	# make tmpdir
	mkdir -p "/tmp/zfs-homed-mount/home-${username}"
	tmpdir="$(mktmp -p "/tmp/zfs-homed-mount/home-${username}" -d)" || tmpdir="/tmp/zfs-homed-mount/home-${username}/tmp.x" 
	mkdir -p "${tmpdir}"; 
	
	# umount systemd-mounted home dir then remolunt it to $tmpdir 

	mntOpts="$(cat /proc/mounts | grep -F "/dev/mapper/home-${username}" | grep -F "/home/${USERNAME}" | awk '{print $4}')"
	
	#umount "/dev/mapper/home-${username}" 
	#sleep 0.2s
	
	#cat /proc/mounts | grep -q -F "/dev/mapper/home-${username}" && umount -l "/dev/mapper/home-${username}"
	#sleep 0.2s

	#mount "/dev/mapper/home-${username}" "${tmpdir}" -o "${mntOpts}"
	#sleep 0.2s
	
	mount "/home/${username}" "${tmpdir}" -o bind,rw""
	sleep 0.2s

	umount "/home/${username}"
	sleep 0.2s

	cat /proc/mounts | grep -q -F "/home/${username}" && umount -l "/home/${username}"
        sleep 0.2s

	# load zfs key if not already loaded
	[[ "$(zfs get keystatus "${zfsHomedRoot}/${username}/data" -H -o value)" == 'available' ]] || zfs load-key "${zfsHomedRoot}/${username}/data"
	sleep 0.2s
	
	# mount zfs dataset to /home/$username
	[[ "$(zfs get mounted "${zfsHomedRoot}/${username}/data" -H -o value)" == 'yes' ]] || zfs mount "${zfsHomedRoot}/${username}/data" 2>/dev/null
	sleep 0.2s
	
	# bind mount identity file back onto /home/$username/.identity if it isnt already there
	[[ -f "/home/${username}/.identity" ]] || touch "/home/${username}/.identity"
	cat /proc/mounts | grep -q -F "/home/${username}/.identity" || mount -o bind,rw "${tmpdir}/.identity" "/home/${username}/.identity"
	#cat /proc/mounts | grep -q -F "/home/${username}/.identity" || mount -o bind,rw "${tmpdir}/${username}/.identity" "/home/${username}/.identity"
	#mount -o bind,rw "${tmpdir}/${username}/.identity" "/home/${username}/.identity"
	sleep 0.2s
	
	# umount the systemd-homed home dir mounted at $tmpdir
	umount "${tmpdir}"
	sleep 0.2s
	cat /proc/mounts | grep -q -F  "${tmpdir}" && umount -l "${tmpdir}"
	sleep 0.2s

	# ensure $username own the identity file
	chown "${username}":"${username}" "/home/${username}/.identity"

	# echo "mounted ZFS home directory to /home/${username}" >&2

	return 0
}

tmpfile_wrapper() {

	local tmpfile
	local pid_cur
	local -a tmpfile_waitlist
	local kk
	
	# make a tmpfile at /tmp/zfs-homed-mount/.tmpfiles/$USER-<...> and write pid to it
	
	pid_cur="$(echo $$)"
	
	tmpfile="$(mktmp --tmp-dir="/tmp/zfs-homed-mount/.tmpfiles" --base="${*// /}-")" || tmpfile="/tmp/zfs-homed-mount/.tmpfiles/${*// /}-x"
	
	echo "${pid_cur}" > "${tmpfile}"
	
	# JOB CONTROL - make sure only one instance of zfs_homed_mount runs at a time for a given user
	# gather all tmpfiles with the name $USER-<...> and sort oldest to youngest
	# If the oldest one holds this process' PID, continue. f not, find where this process is in the waitlist and wait for the process just before it in the waitlist to finish
	
	mapfile -t tmpfile_waitlist < <(find "/tmp/zfs-homed-mount/.tmpfiles" -type f -name "${*// /}"'*' -printf '%Cs %p\n' | sort | awk '{printf $1}')

	if [[ "$(cat "${tmpfile_waitlist[0]}")" != "${pid_cur}" ]]; then
		for kk in "${!tmpfile_waitlist[@]}"; do
			[[ "$(cat "${tmpfile_waitlist[${kk}]}")" == "${pid_cur}" ]] && wait -p "$(cat "${tmpfile_waitlist[$((( ${kk} - 1 )))]}")" && break
		done
	fi

	zfs_homed_mount "${@}" || echo "Home area for user ${*// /} either could not be accessed or could not be activated" >&2
	
	\rm -f "${tmpfile}"	
	
	return 0
}

mkdir -p /tmp/zfs-homed-mount/.tmpfiles

dbus-monitor --monitor --system "path='/org/freedesktop/home1',member='ActivateHome'" | while read -r dmsg; do 
	
	[[ -z $activateFlag ]] && activateFlag=false
	
	echo "${dmsg}" | grep -q "ActivateHome" && activateFlag=true && continue
	echo "${dmsg}" | grep -q -E '^string \"\{.*\}\"$' && dmsg="" && continue

	if ${activateFlag}; then
		if echo "${dmsg}" | grep -q -E '^string \".+\"$'; then
			homed_zfs_username="$(echo "${dmsg}" | sed -E s/'^string \"(.+)\"$'/'\1'/)"
			tmpfile_wrapper "${homed_zfs_username}" 2>/dev/null &
			unset homed_zfs_username
		else
			tmpfile_wrapper 2>/dev/null &
		fi
	fi
	activateFlag=false
done	

return 1
