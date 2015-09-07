#!/bin/sh

_DIR=`cd "$( dirname "$0" )" && pwd`
_PROJECT=`basename "${_DIR}"`

_SERVICES="`ls -d */ | sed 's|/$||'`"

if `echo "${_SERVICES}" | grep -q '\t'`; then
  [ -n "$1" ] || return 1
  _SERVICE="$1"
  shift
else
  _SERVICE="${_SERVICES}"
fi

echo docker exec -it "${_PROJECT}_${_SERVICE}" /entrypoint.sh $*
