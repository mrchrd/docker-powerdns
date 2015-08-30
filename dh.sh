#!/bin/sh

_REPO='oriaks'
_SERVICES='server'

_usage () {
  cat <<- EOF
	Usage: $0 build                        Build images
	       $0 start                        Start services
	       $0 stop                         Stop services
	       $0 restart                      Restart services
	       $0 manage SERVICE [ARG...]      Manage the running service

EOF
}

_DIR=`cd "$( dirname "$0" )" && pwd`
_PROJECT=`basename "${_DIR}"`
_CMD="$1"
_SERVICE="$2"

[ -n "${_CMD}" ] && shift
[ -n "${_SERVICE}" ] && shift

case "${_CMD}" in
  "build")
    for _SERVICE in ${_SERVICES}; do
      docker build --force-rm=true -t "${_REPO}/${_PROJECT}_${_SERVICE}:latest" ${_SERVICE}
    done
    ;;
  "manage")
    [ -z "${_PROJECT}" -o -z "${_SERVICE}" ] && _usage || docker exec -it "${_PROJECT}_${_SERVICE}" /entrypoint.sh $*
    ;;
  "restart")
    docker-compose restart
    ;;
  "start")
    docker-compose up -d
    ;;
  "stop")
    docker-compose stop
    ;;
  *)
    _usage
    ;;
esac
