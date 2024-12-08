#!/bin/sh

set -eu

umask 077

if [ -z "${LDAP_URI:-}" ]; then
    LDAP_URI="ldaps://ldap$(echo "$LDAP_BASEDN" | sed -e 's/,\?[[:alpha:]]\+=/\./g')"
fi

_dbtlsopts=""
if [ -n "${IPSILON_DB_CA:-}" ]; then
    if [ ! -r "$IPSILON_DB_CA" ]; then
        echo "ERROR: Cannot read CA certificate '${IPSILON_DB_CA}'" 1>&2
        exit 1
    fi
    _dbtlsopts="&ssl=true&ssl_ca=${IPSILON_DB_CA}"
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
    _dbtlsopts="${_dbtlsopts}&ssl_key=/etc/ssl/private/ipsilon.key&ssl_cert=${IPSILON_DB_CERT}"
elif [ -n "${IPSILON_DB_KEY:-}" ]; then
    echo "ERROR: Client private key configured but no certificate" 1>&2
    exit 1
elif [ -n "${IPSILON_DB_CERT:-}" ]; then
    echo "ERROR: Client certificate configured but no private key" 1>&2
    exit 1
fi

if [ -n "$_dbtlsopts" ]; then
    _dbtlsopts="?$(echo "$_dbtlsopts" | cut -c 2-)"
fi

_dburi="mysql://${IPSILON_DB_USER:-ipsilon}:${IPSILON_DB_PASS}@${IPSILON_DB_HOST}"

if [ ! -r "/etc/ipsilon/openidc.key" ]; then
    echo "ERROR: Failed to read OpenID Connect private key '/etc/ipsilon/openidc.key'" 1>&2
    exit 1
fi

# run server install with minimal arguments to get files and dirs in place
ipsilon-server-install --hostname="$IPSILON_HOSTNAME" --root-instance --testauth=yes

# copy openidc key to final place to fix permissions
install -m 0640 -o root -g ipsilon /etc/ipsilon/openidc.key /etc/ipsilon/root/openidc.key

cat <<EOF > /etc/ipsilon/root/ipsilon.conf
[global]
debug = False
tools.log_request_response.on = False
template_dir = "templates"
cache_dir = "/var/cache/ipsilon"
cleanup_interval = 30
db.conn.log = False
db.echo = False

# base.mount = ""
base.dir = "/usr/share/ipsilon"
admin.config.db = "configfile:///etc/ipsilon/root/admin.conf"
user.prefs.db = "${_dburi}/${IPSILON_DB_USERPREFS:-ipsilon}${_dbtlsopts}"
transactions.db = "${_dburi}/${IPSILON_DB_TRANSACTIONS:-ipsilon}${_dbtlsopts}"

tools.sessions.on = True
tools.sessions.name = "root_ipsilon_session_id"
tools.sessions.storage_type = "file"
tools.sessions.storage_path = "/var/lib/ipsilon/root/sessions"
tools.sessions.path = ""
tools.sessions.timeout = 30
tools.sessions.httponly = True
tools.sessions.secure = True

tools.proxy.on = True
EOF
chmod 640 /etc/ipsilon/root/ipsilon.conf
chown root:ipsilon /etc/ipsilon/root/ipsilon.conf

cat <<EOF > /etc/ipsilon/root/admin.conf
[info_config]
ldap server url = ${LDAP_URI}
ldap user dn template = uid=%(username)s,ou=People,${LDAP_BASEDN}
ldap tls = Demand
ldap base dn = ${LDAP_BASEDN}
global enabled = ldap

[login_config]
ldap server url = ${LDAP_URI}
ldap bind dn template = uid=%(username)s,ou=People,${LDAP_BASEDN}
ldap tls = Demand
ldap base dn = ${LDAP_BASEDN}
global enabled = ldap

[provider_config]
openidc endpoint url = https://${IPSILON_HOSTNAME}/openidc/
openidc database url = ${_dburi}/${IPSILON_DB_OPENIDC:-ipsilon}${_dbtlsopts}
openidc static database url = ${_dburi}/${IPSILON_DB_OPENIDC_STATIC:-ipsilon}${_dbtlsopts}
openidc enabled extensions =
openidc idp key file = /etc/ipsilon/root/openidc.key
global enabled = openidc

[authz_config]
global enabled = allow
EOF
chmod 640 /etc/ipsilon/root/admin.conf
chown root:ipsilon /etc/ipsilon/root/admin.conf

# disable ssl redirection as we run behind proxy
sed -i -e 's/^\([[:space:]]*\)\(Rewrite.*\)$/\1#\2/' /etc/httpd/conf.d/ipsilon-root.conf

# send apache logs to stdout/stderr
sed -i \
    -e 's|^\(\s*CustomLog\s\+\).\+\(\s\+.*\)$|\1/proc/self/fd/1\2|' \
    -e 's|^\(\s*ErrorLog\s\+\).*|\1/proc/self/fd/2|' \
    /etc/httpd/conf/httpd.conf

unset LDAP_BASEDN LDAP_URI
unset _dbtlsopts _dburi
# shellcheck disable=SC2046
unset $(env | awk -F= '/^IPSILON_/ { print $1 }')

exec "$@"
