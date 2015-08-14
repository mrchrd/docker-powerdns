#!/bin/sh
#
#  Copyright (C) 2015 Michael Richard <michael.richard@oriaks.com>
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

#set -x

_install () {
  [ -f /usr/sbin/pdns_server ] && return

  apt-get update -q
  apt-get install -y pdns-server vim-tiny

  sed -ri -f- /etc/powerdns/pdns.conf <<- EOF
	s|[# ]?slave=.*|slave=yes|;
EOF

  mv /etc/powerdns/bindbackend.conf /etc/powerdns/bindbackend.conf.orig
  ln -sf /var/named/named.conf /etc/powerdns/bindbackend.conf

  return 0
}

_init () {
  [ -d /var/named ]            || install -o root -g pdns -m 750 -d /var/named
  [ -d /var/named/master ]     || install -o root -g pdns -m 750 -d /var/named/master
  [ -d /var/named/slave ]      || install -o pdns -g pdns -m 750 -d /var/named/slave
  [ -f /var/named/named.conf ] || install -o root -g pdns -m 640 /dev/null /var/named/named.conf

  cat > /var/named/named.conf <<- EOF
	options {
	    directory "/var/named";
	};
EOF

  exec /usr/sbin/pdns_server --daemon=no

  return 0
}

_manage () {
  _CMD="$1"
  [ -n "${_CMD}" ] && shift

  case "${_CMD}" in
    "domain")
      _manage_domain $*
      ;;
    "service")
      _manage_service $*
      ;;
    *)
      _usage
      ;;
  esac

  return 0
}

_manage_domain () {
  _CMD="$1"
  [ -n "${_CMD}" ] && shift

  case "${_CMD}" in
    "create")
      _manage_domain_create $*
      ;;
    "edit")
      _manage_domain_edit $*
      ;;
    *)
      _usage
      ;;
  esac

  return 0
}

_manage_domain_create () {
  _DOMAIN="$1"
  [ -z "${_DOMAIN}" ] && return 1 || shift

  grep -q "^zone \"${_DOMAIN}\" {" /var/named/named.conf && return 1
  [ -f "/var/named/master/${_DOMAIN}" ] && return 1

  cat >> /var/named/named.conf <<- EOF

	zone "${_DOMAIN}" {
	    type master;
	    file "master/${_DOMAIN}";
	};
EOF

  install -o root -g pdns -m 640 /dev/null "/var/named/master/${_DOMAIN}"
  cat >> /var/named/master/${_DOMAIN} <<- EOF
	\$ORIGIN       ${_DOMAIN}.
	\$TTL          600
	@                               IN  SOA  ns1.oriaks.com. domainmaster.oriaks.com. (
	                                         `date +%Y%m%d`01 ; Serial
	                                         3600       ; Refresh : 1 hour
	                                         600        ; Retry : 10 minutes
	                                         86400      ; Expires : 1 day
	                                         600        ; TTL : 1 hour
	                                         )
	                                IN  NS   ns1.oriaks.com.
	                                IN  NS   ns2.oriaks.com.
EOF

  _manage_service_reload

  return 0
}

_manage_domain_edit () {
  _DOMAIN="$1"
  [ -z "${_DOMAIN}" ] && return 1 || shift

  grep -q "^zone \"${_DOMAIN}\" {" /var/named/named.conf || return 1
  [ -f "/var/named/master/${_DOMAIN}" ] || return 1

  vi /var/named/master/${_DOMAIN}

  _manage_service_reload

  return 0
}

_manage_service () {
  _CMD="$1"
  [ -n "${_CMD}" ] && shift

  case "${_CMD}" in
    "reload")
      _manage_service_reload $*
      ;;
    *)
      _usage
      ;;
  esac

  return 0
}

_manage_service_reload () {
  pdns_control cycle

  return 0
}

_shell () {
  exec /bin/bash

  return
}

_usage () {
  cat <<- EOF
	Usage: $0 install
	       $0 init
	       $0 manage domain create <domain_name>
	       $0 manage domain edit <domain_name>
	       $0 manage service reload
	       $0 shell
EOF

  return
}

_CMD="$1"
[ -n "${_CMD}" ] && shift

case "${_CMD}" in
  "install")
    _install $*
    ;;
  "init")
    _init $*
    ;;
  "manage")
    _manage $*
    ;;
  "shell")
    _shell $*
    ;;
  *)
    _usage
    ;;
esac
