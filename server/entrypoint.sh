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

if [ -n "${DEBUG}" ]; then
  set -x
fi

export DEBIAN_FRONTEND='noninteractive'
export TERM='linux'

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

_domain_create () {
  local _DOMAIN="$1"
  [ -z "${_DOMAIN}" ] && return 1 || shift

  grep -q "^zone \"${_DOMAIN}\" {" /var/named/named.conf && return 1
  _domain_exists "${_DOMAIN}" && return 1

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

  _service_reload

  return 0
}

_domain_edit () {
  local _DOMAIN="$1"
  [ -z "${_DOMAIN}" ] && return 1 || shift

  grep -q "^zone \"${_DOMAIN}\" {" /var/named/named.conf || return 1
  _domain_exists "${_DOMAIN}" || return 1

  vi /var/named/master/${_DOMAIN}

  _service_reload

  return 0
}

_domain_exists () {
  local _DOMAIN="$1"
  [ -z "${_DOMAIN}" ] && return 1 || shift
  [ -f "/var/named/master/${_DOMAIN}" ] || return 1

  return 0
}

_domain_list () {
  local _DOMAIN

  for _DOMAIN in `ls /var/named/master/* | sed 's|/var/named/master/||' | sort`; do
    printf "${_DOMAIN}\n"
  done
}

_service_reload () {
  pdns_control cycle

  return 0
}

case "$1" in
  "install")
    _$*
    ;;
  "init")
    _$*
    ;;
  "")
    /usr/bin/clish
    ;;
  _*)
    $*
    ;;
  *)
    /usr/bin/clish -c "$*"
    ;;
esac
