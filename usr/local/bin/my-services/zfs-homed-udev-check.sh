#!/usr/bin/bash

username="$(udevadm info -p "${*}" | grep 'DM_NAME=home-' | sed -E s/'^E\: DM_NAME\=home-'//)"
[[ -n ${username}} ]] && echo "${username}" &&  return 0 || return 1
