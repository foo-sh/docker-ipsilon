#!/bin/sh

set -eu

umask 077

if [ -z "${LDAP_URI:-}" ]; then
    LDAP_URI="ldaps://ldap$(echo "$LDAP_BASEDN" | sed -e 's/,\?[[:alpha:]]\+=/\./g')"
fi

[ "${IPSILON_DB_USER:-}" = "" ] && IPSILON_DB_USER="ipsilon"

TLSOPTS=""
if [ -n "${IPSILON_DB_CA:-}" ]; then
    if [ ! -r "$IPSILON_DB_CA" ]; then
        echo "ERROR: Cannot read CA certificate '${IPSILON_DB_CA}'" 1>&2
        exit 1
    fi
    TLSOPTS="&ssl=true&ssl_ca=${IPSILON_DB_CA}"
fi

if [ -n "${IPSILON_DB_KEY:-}" ] && [ -n "${IPSILON_DB_CERT:-}" ]; then
    if ! openssl rsa -check -noout -in "$IPSILON_DB_KEY" > /dev/null 2>&1; then
        echo "ERROR: Failed to read client private key '${IPSILON_DB_KEY}'" 1>&2
        exit 1
    fi
    if ! openssl x509 -in "$IPSILON_DB_CERT" -noout > /dev/null 2>&1; then
        echo "ERROR: Failed to read client certificate '${IPSILON_DB_CERT}'" 1>&2
        exit 1
    fi
    install -m 0640 --owner root --group ipsilon "$IPSILON_DB_KEY" "/etc/ssl/private/ipsilon.key"
    TLSOPTS="${TLSOPTS}&ssl_key=/etc/ssl/private/ipsilon.key&ssl_cert=${IPSILON_DB_CERT}"
elif [ -n "${IPSILON_DB_KEY:-}" ]; then
    echo "ERROR: Client private key configured but no certificate" 1>&2
    exit 1
elif [ -n "${IPSILON_DB_CERT:-}" ]; then
    echo "ERROR: Client certificate configured but no private key" 1>&2
    exit 1
fi

if [ -n "$TLSOPTS" ]; then
    TLSOPTS="$(echo "$TLSOPTS" | cut -c 2-)"
fi

_dburi="mysql://${IPSILON_DB_USER}:${IPSILON_DB_PASS}@${IPSILON_DB_HOST}"

ipsilon-server-install \
    --root-instance \
    --hostname="idp.foo.sh" \
    --ldap=yes \
    --ldap-server-url="${LDAP_URI}" \
    --ldap-tls-level=Demand \
    --ldap-bind-dn-template="uid=%(username)s,ou=People,${LDAP_BASEDN}" \
    --ldap-base-dn="${LDAP_BASEDN}" \
    --info-ldap=yes \
    --info-ldap-server-url="${LDAP_URI}" \
    --info-ldap-user-dn-template="uid=%(username)s,ou=People,${LDAP_BASEDN}" \
    --users-dburi="${_dburi}/${IPSILON_DB_USERPREFS:-ipsilon}?${TLSOPTS}" \
    --transaction-dburi="${_dburi}/${IPSILON_DB_TRANSACTIONS:-ipsilon}?${TLSOPTS}" \
    --openidc=yes \
    --openidc-dburi="${_dburi}/${IPSILON_DB_OPENIDC:-ipsilon}?${TLSOPTS}" \
    --openidc-static-dburi="${_dburi}/${IPSILON_DB_OPENIDC_STATIC:-ipsilon}?${TLSOPTS}"

# enable proxy support manually
{
    echo ""
    echo "tools.proxy.on = True"
} >> /etc/ipsilon/root/ipsilon.conf

# disable ssl redirection as we run behind proxy
sed -i -e 's/^\([[:space:]]*\)\(Rewrite.*\)$/\1#\2/' /etc/httpd/conf.d/ipsilon-root.conf

# send apache logs to stdout/stderr
sed -i \
    -e 's|^\(\s*CustomLog\s\+\).\+\(\s\+.*\)$|\1/proc/self/fd/1\2|' \
    -e 's|^\(\s*ErrorLog\s\+\).*|\1/proc/self/fd/2|' \
    /etc/httpd/conf/httpd.conf

unset LDAP_BASEDN LDAP_URI
unset _dburi
# shellcheck disable=SC2046
unset $(env | awk -F= '/^IPSILON_/ { print $1 }')

exec "$@"
