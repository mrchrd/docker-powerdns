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
  apt-get install -y --no-install-recommends dnsutils pdns-server vim-tiny

  sed -i -f- /etc/powerdns/pdns.conf <<- EOF
	s|[# ]*master=.*|master=yes|;
	s|[# ]*slave=.*|slave=yes|;
EOF

  cat >> /etc/powerdns/pdns.d/pdns.simplebind.conf <<- EOF
	bind-dnssec-db=/var/named/dnssec/dnssec.db
EOF

  mv /etc/powerdns/bindbackend.conf /etc/powerdns/bindbackend.conf.orig
  ln -sf /var/named/named.conf /etc/powerdns/bindbackend.conf

  return 0
}

_init () {
  [ -d /var/named ]                   || install -o root -g pdns -m 750 -d /var/named
  [ -d /var/named/dnssec ]            || install -o pdns -g pdns -m 750 -d /var/named/dnssec
  [ -d /var/named/dnssec/dnssec.db ]  || pdnssec create-bind-db /var/named/dnssec/dnssec.db && chown pdns:pdns /var/named/dnssec/dnssec.db && chmod 640 /var/named/dnssec/dnssec.db
  [ -d /var/named/master ]            || install -o root -g pdns -m 750 -d /var/named/master
  [ -d /var/named/slave ]             || install -o pdns -g pdns -m 750 -d /var/named/slave
  [ -f /var/named/named.conf ]        || install -o root -g pdns -m 640 /dev/stdin /var/named/named.conf <<- EOF
	options {
	    directory "/var/named";
	};
EOF

  exec /usr/sbin/pdns_server --daemon=no

  return 0
}

_domain_create_master () {
  local _DOMAIN="$1"
  [ -z "${_DOMAIN}" ] && return 1 || shift

  _domain_exists "${_DOMAIN}" && return 1

  cat >> /var/named/named.conf <<- EOF

	zone "${_DOMAIN}" {
	    type master;
	    file "master/${_DOMAIN}";
	    notify yes;
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

  #pdnssec secure-zone "${_DOMAIN}"
  #pdnssec rectify-zone "${_DOMAIN}"
  #pdnssec show-zone "${_DOMAIN}"

  pdnssec generate-tsig-key "${_DOMAIN}" hmac-sha256
  pdnssec activate-tsig-key "${_DOMAIN}" "${_DOMAIN}" master
  local _TSIG_KEY="`pdnssec list-tsig-keys | awk "/^${_DOMAIN} / {print \\$3}"`"

  pdns_control rediscover
  pdns_control notify "${_DOMAIN}"

  echo "tsig: ${_TSIG_KEY}"

  return 0
}

_domain_create_slave () {
  local _DOMAIN="$1"
  [ -z "${_DOMAIN}" ] && return 1 || shift
  _domain_exists "${_DOMAIN}" && return 1

  local _MASTER_IP="$1"
  [ -z "${_MASTER_IP}" ] && return 1 || shift

  local _TSIG_KEY="$1"
  [ -z "${_TSIG_KEY}" ] && return 1 || shift

  cat >> /var/named/named.conf <<- EOF

	zone "${_DOMAIN}" {
	    type slave;
	    file "slave/${_DOMAIN}";
	    masters { ${_MASTER_IP}; };
	};
EOF

  pdnssec import-tsig-key "${_DOMAIN}" hmac-sha256 "${_TSIG_KEY}"
  pdnssec activate-tsig-key "${_DOMAIN}" "${_DOMAIN}" slave

  pdns_control rediscover
  pdns_control retrieve "${_DOMAIN}"

  return 0
}

_domain_drop () {
  local _DOMAIN="$1"
  [ -z "${_DOMAIN}" ] && return 1 || shift

  _domain_exists "${_DOMAIN}" || return 1

  sed -ri -f- /var/named/named.conf <<- EOF
	/^zone "${_DOMAIN}"/,/^}/d;
EOF

  rm -f "/var/named/master/${_DOMAIN}"
  rm -f "/var/named/slave/${_DOMAIN}"

  pdns_control rediscover

  return 0
}

_domain_edit () {
  local _DOMAIN="$1"
  [ -z "${_DOMAIN}" ] && return 1 || shift

  _domain_exists "${_DOMAIN}" || return 1
  _domain_is_master "${_DOMAIN}" || return 1

  vi /var/named/master/${_DOMAIN}

  pdns_control reload

  return 0
}

_domain_exists () {
  local _DOMAIN="$1"
  [ -z "${_DOMAIN}" ] && return 1 || shift
  pdns_control list-zones | grep -q "^${_DOMAIN}$" || return 1

  return 0
}

_domain_is_master () {
  local _DOMAIN="$1"
  [ -z "${_DOMAIN}" ] && return 1 || shift
  pdns_control list-zones master | grep -q "^${_DOMAIN}$" || return 1

  return 0
}

_domain_list () {
  local _DOMAIN

  for _DOMAIN in `pdns_control list-zones | head -n -1 | sort`; do
    printf "${_DOMAIN}\n"
  done
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
