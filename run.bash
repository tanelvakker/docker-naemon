#!/bin/bash

#
# Naemon container bootstrap. See the readme for usage.
#
source /data_dirs.env
FIRST_TIME_INSTALLATION=false
DATA_PATH=/data

for datadir in "${DATA_DIRS[@]}"; do
  if [ ! -e "${DATA_PATH}/${datadir#/*}" ]
  then
    echo "Installing ${datadir}"
    mkdir -p ${DATA_PATH}/${datadir#/*}
    chown naemon:naemon ${DATA_PATH}/${datadir#/*}
    cp -pr ${datadir}-template/* ${DATA_PATH}/${datadir#/*}/
    FIRST_TIME_INSTALLATION=true
  fi
done

SSL_SITE_CONF_TEMPLATE='<VirtualHost _default_:443>
  DocumentRoot /var/www/
  SSLCertificateFile    $WEB_SSL_CERT
  SSLCertificateKeyFile $WEB_SSL_KEY
  $CHAIN_FILE_ENTRY
  Include /usr/share/naemon/thruk_cookie_auth.include
</VirtualHost>'

LDAP_CONF_TEMPLATE='LDAPCacheEntries 0
<Location /naemon/>
  AuthName \"Thruk LDAP Auth\"
  AuthType Basic
  AuthBasicProvider file ldap
  AuthUserFile /etc/naemon/htpasswd
  AuthLDAPURL $WEB_LDAP_URL
  AuthLDAPBindDN $WEB_LDAP_BIND_DN
  AuthLDAPBindPassword $WEB_LDAP_BIND_PASS
  Require valid-user
</Location>'

if [ ! -e /._container_setup ]
then
  #
  # SMTP configuration
  # Varaibles:
  # - SMTP_HOST
  # - SMTP_PORT
  # - SMTP_LOGIN
  # - SMTP_PASS
  # - SMTP_USE_TLS
  # - NOTIFICATION_FROM
  if [ -z "$SMTP_HOST" ]
  then
    echo "!! SMTP not configured, email cannot be sent !!"
  else
    SMTP_PORT=${SMTP_PORT:-25}
    SMTP_USE_TLS=${SMTP_USE_TLS:-true}
    echo "Configuring SMTP"
    # Setup the per-instance hostname in NAEMON
    sed -i "s/^hostname=.*/hostname=${HOSTNAME}/" /etc/ssmtp/ssmtp.conf
    sed -i "s/^mailhub=.*/mailhub=${SMTP_HOST}:${SMTP_PORT}/" /etc/ssmtp/ssmtp.conf
    if [[ -n "$SMTP_LOGIN" && -n "$SMTP_PASS" ]]
    then
      echo "AuthUser=${SMTP_LOGIN}" >> /etc/ssmtp/ssmtp.conf
      echo "AuthPass=${SMTP_PASS}" >> /etc/ssmtp/ssmtp.conf
    fi

    if [ $SMTP_USE_TLS == true ]
    then
      echo "UseTLS=Yes" >> /etc/ssmtp/ssmtp.conf
      echo "UseSTARTTLS=Yes" >> /etc/ssmtp/ssmtp.conf
    fi
  fi
  
  #
  # Thruk SSL configuration (optional, see readme)
  #
  # Varaibles:
  # - WEB_SSL_ENABLED
  # - WEB_SSL_CERT
  # - WEB_SSL_KEY
  # - WEB_SSL_CA
  DEFAULT_WEB_SSL_ENABLED=false
  if [[ -n "$WEB_SSL_CERT" || -n "$WEB_SSL_KEY" ]]
  then
    DEFAULT_WEB_SSL_ENABLED=true
  fi
  WEB_SSL_CERT=${WEB_SSL_CERT:-/data/crt.pem}
  WEB_SSL_KEY=${WEB_SSL_KEY:-/data/key.pem}
  WEB_SSL_ENABLED=${WEB_SSL_ENABLED:-$DEFAULT_WEB_SSL_ENABLED}
  if [ $WEB_SSL_ENABLED == true ]
  then
    echo "Enabling SSL for Thruk"
    # Enable the required modules
    cd /etc/apache2/mods-enabled
    for apache_mod in ssl.conf ssl.load socache_shmcb.load
    do
      if [ ! -e $apache_mod ]
      then
        ln -s ../mods-available/${apache_mod} $apache_mod
      fi
    done

    if [ -n "$WEB_SSL_CA" ]
    then
      CHAIN_FILE_ENTRY="SSLCertificateChainFile $WEB_SSL_CA"
    fi
    eval SSL_SITE_CONF_TEMPLATE=\""$SSL_SITE_CONF_TEMPLATE"\"
    echo "$SSL_SITE_CONF_TEMPLATE" > /etc/apache2/sites-enabled/default_ssl.conf
    chown www-data:www-data /etc/apache2/sites-enabled/default_ssl.conf
  fi
 
  #
  # Thruk LDAP authentication (optional, see readme)
  #
  # Varaibles
  # - WEB_LDAP_AUTH_ENABLED
  # - WEB_LDAP_SSL
  # - WEB_LDAP_SSL_VERIFY
  # - WEB_LDAP_SSL_CA
  # - WEB_LDAP_HOST
  # - WEB_LDAP_PORT
  # - WEB_LDAP_BIND_DN
  # - WEB_LDAP_BIND_PASS
  # - WEB_LDAP_BASE_DN
  # - WEB_LDAP_UID
  # - WEB_LDAP_FILTER
  DEFAULT_WEB_LDAP_AUTH_ENABLED=false
  if [ -n "$WEB_LDAP_HOST" ]
  then
   DEFAULT_WEB_LDAP_AUTH_ENABLED=true
  fi

  WEB_LDAP_SSL=${WEB_LDAP_SSL:-false}
  DEFAULT_WEB_LDAP_PORT="389"
  if [ $WEB_LDAP_SSL == true ]
  then
   DEFAULT_WEB_LDAP_PORT="636"
  fi

  WEB_LDAP_PORT="${WEB_LDAP_PORT:-$DEFAULT_WEB_LDAP_PORT}"
  DEFAULT_WEB_LDAP_SSL_VERIFY=false
  if [ -n "$WEB_LDAP_SSL_CA" ]
  then
   DEFAULT_WEB_LDAP_SSL_VERIFY=true
  fi
  WEB_LDAP_SSL_VERIFY=${WEB_LDAP_SSL_VERIFY:-$DEFAULT_WEB_LDAP_SSL_VERIFY}
  WEB_LDAP_UID=${WEB_LDAP_UID:-uid}

  if [ $WEB_LDAP_AUTH_ENABLED = true ]
  then
   echo "Configuring LDAP web authentication"
   cd /etc/apache2/mods-enabled
   for apache_mod in authnz_ldap.load ldap.conf ldap.load
   do
     if [ ! -e $apache_mod ]
     then
       ln -s ../mods-available/${apache_mod} $apache_mod
     fi
   done

   # Setup the WEB_LDAP_URL variable
   WEB_LDAP_URL="ldap://"
   if [ $WEB_LDAP_SSL == true ]
   then
     WEB_LDAP_URL="ldaps://"
   fi
   WEB_LDAP_URL="${WEB_LDAP_URL}${WEB_LDAP_HOST}:${WEB_LDAP_PORT}"
   WEB_LDAP_URL="${WEB_LDAP_URL}/${WEB_LDAP_BASE_DN}?${WEB_LDAP_UID}?sub?${WEB_LDAP_FILTER}"
   eval LDAP_CONF_TEMPLATE=\""$LDAP_CONF_TEMPLATE"\"
   echo "$LDAP_CONF_TEMPLATE" > /etc/apache2/conf-enabled/naemon_ldap.conf
   chown www-data:www-data /etc/apache2/conf-enabled/naemon_ldap.conf

   if [ $WEB_LDAP_SSL == true ]
   then
     SECURITY_ADD_STR="LDAPVerifyServerCert off"
     if [[ $WEB_LDAP_SSL_VERIFY == true &&  -n "$WEB_LDAP_SSL_CA" ]]
     then
       SECURITY_ADD_STR="LDAPTrustedGlobalCert CA_BASE64 $WEB_LDAP_SSL_CA"
     fi
     grep -q "$SECURITY_ADD_STR" /etc/apache2/conf-enabled/security.conf
     if (( $? != 0 ))
     then
       echo $SECURITY_ADD_STR >> /etc/apache2/conf-enabled/security.conf
     fi
   fi
  fi
  touch /._container_setup
fi

if [ $FIRST_TIME_INSTALLATION == true ]
then
  RANDOM_PASS=`date +%s | md5sum | base64 | head -c 8`
  WEB_ADMIN_PASSWORD=${WEB_ADMIN_PASSWORD:-$RANDOM_PASS}
  htpasswd -b /etc/naemon/htpasswd admin ${WEB_ADMIN_PASSWORD}
  echo "Set the thruk admin password to: $WEB_ADMIN_PASSWORD"
  
  NOTIFICATION_FROM=${NOTIFICATION_FROM:-naemon@$HOSTNAME}
  sed -i "s,/usr/bin/mail \\\,/usr/bin/mail -a \"From\: $NOTIFICATION_FROM\"\\\,g"\
   /etc/naemon/conf.d/commands.cfg
   
  WEB_USERS_FULL_ACCESS=${WEB_USERS_FULL_ACCESS:-false}
  if [ $WEB_USERS_FULL_ACCESS == true ]
  then
    sed -i 's/=admin/=*/g' /etc/naemon/cgi.cfg 
  fi
fi

function graceful_exit(){
  /etc/init.d/apache2 stop
  service naemon stop
  exit $1
}

# Start the services
service naemon start
/etc/init.d/apache2 start

# Trap exit signals and do a proper shutdown
trap "graceful_exit 0;" SIGINT SIGTERM

while true
do
  service naemon status > /dev/null
  if (( $? != 0 ))
  then
    echo "Naemon no longer running"
    graceful_exit 1
  fi
  
  /etc/init.d/apache2 status > /dev/null
  if (( $? != 0 ))
  then
    echo "Apache no longer running"
    graceful_exit 2
  fi
  sleep 1
done