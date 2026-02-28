#!/bin/bash

#
# Net Installer, used with curl
#

atlasstGithubRepo="StateDev08/atlas-server-tools"

steamcmd_user="$1"
shift

args=()
output=/dev/null
unstable=
userinstall=

for arg in "$@"; do
  case "$arg" in
    --verbose) output=/dev/fd/1; ;;
    --output=*) output="${1#--output=}"; ;;
    --unstable) unstable=1; ;;
    --perform-user-install) userinstall=yes; ;;
    *)
      if [ -n "$channel" ]; then
        args+="$arg"
      else
        channel="$arg"
      fi
    ;;
  esac
done

if [ -z "$channel" ]; then
  channel="master"
fi

if [[ "$steamcmd_user" == "--me" && -z "$userinstall" ]]; then
  echo "You have requested a user-install.  You probably don't want this."
  echo "A user-install will create ~/.config/atlasmanager/instances/main.cfg"
  echo "This config file will override /etc/atlasmanager/instances/main.cfg"
  echo "Add --perform-user-install if you really want this."
  exit 1
fi

function doInstallFromCommit(){
  local commit="$1"
  tmpdir="$(mktemp -t -d "atlas-server-tools-XXXXXXXX")"
  if [ -z "$tmpdir" ]; then echo "Unable to create temporary directory"; exit 1; fi
  cd "$tmpdir"
  echo "Downloading installer"
  curl -s -L "https://github.com/${atlasstGithubRepo}/archive/${commit}.tar.gz" | tar -xz
  cd "atlas-server-tools-${commit}/tools"
  if [ ! -f "install.sh" ]; then echo "install.sh not found in $PWD"; exit 1; fi
  sed -i -e "s|^atlasstCommit='.*'|atlasstCommit='${commit}'|" \
         -e "s|^atlasstTag='.*'|atlasstTag='${tagname}'|" \
         atlasmanager
  echo "Running install.sh"
  bash install.sh "$steamcmd_user" "${reinstall_args[@]}"
  result=$?
  cd /
  rm -rf "$tmpdir"

  if [ "$result" = 0 ] || [ "$result" = 2 ]; then
    echo "ATLAS Server Tools successfully installed"
  else
    echo "ATLAS Server Tools install failed"
  fi
  return $result
}

function doInstallFromRelease(){
  local tagname=
  local desc=

  echo "Getting latest release..."
  # Read the variables from github
  while IFS=$'\t' read n v; do
    case "${n}" in
      tag_name) tagname="${v}"; ;;
      body) desc="${v}"
    esac
  done < <(curl -s "https://api.github.com/repos/${atlasstGithubRepo}/releases/latest" | sed -n 's/^  "\([^"]*\)": "*\([^"]*\)"*,*/\1\t\2/p')

  if [ -n "$tagname" ]; then
    echo "Latest release is ${tagname}"
    echo "Getting commit for latest release..."
    local commit="$(curl -s "https://api.github.com/repos/${atlasstGithubRepo}/git/refs/tags/${tagname}" | sed -n 's/^ *"sha": "\(.*\)",.*/\1/p')"
    doInstallFromCommit "$commit"
  else
    echo "Unable to get latest release"
    return 1
  fi
}

function doInstallFromBranch(){
  channel="$1"
  commit="`curl -s "https://api.github.com/repos/${atlasstGithubRepo}/git/refs/heads/${channel}" | sed -n 's/^ *"sha": "\(.*\)",.*/\1/p'`"
  
  if [ -z "$commit" ]; then
    if [ -n "$unstable" ]; then
      echo "Channel ${channel} not found - trying master"
      doInstallFromBranch master
    else
      doInstallFromRelease
    fi
  else
    doInstallFromCommit "$commit"
  fi
}

# Download and untar installation files
cd "$TEMP"

if [ "$channel" = "master" ] && [ -z "$unstable" ]; then
  doInstallFromRelease
else
  doInstallFromBranch "$channel"
fi
