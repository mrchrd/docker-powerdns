#!/bin/sh

_REPO='oriaks'
_DIR=`cd "$( dirname "$0" )" && pwd`
_PROJECT=`basename "${_DIR}"`

if [ -n "$*" ]; then
  _SERVICES="$*"
else
  _SERVICES="`ls -d */ | sed 's|/$||'`"
fi

for _SERVICE in ${_SERVICES}; do
  docker build --force-rm=true -t "${_REPO}/${_PROJECT}_${_SERVICE}:latest" ${_SERVICE}
done
