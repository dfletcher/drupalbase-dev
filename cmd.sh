#!/bin/bash

# TODO these could probably be a bit smarter.
uri_protocol="$(echo "${DATABASE_URI}" | sed 's/^\([^:]*\).*$/\1/g')"
uri_username="$(echo "${DATABASE_URI}" | sed 's/^\([^:]*\):\/\/\([^:]*\).*$/\2/g')"
uri_password="$(echo "${DATABASE_URI}" | sed 's/^\([^:]*\):\/\/\([^:]*\):\([^@]*\).*$/\3/g')"
uri_host="$(echo "${DATABASE_URI}" | sed 's/^\([^:]*\):\/\/\([^:]*\):\([^@]*\)@\([^\/]*\)\/.*$/\4/g')"
uri_database="$(echo "${DATABASE_URI}" | sed 's/^\([^:]*\):\/\/\([^:]*\):\([^@]*\)@\([^\/]*\)\/\([^\/]*\).*$/\5/g')"

##
# Utility: run a mysql command with the configured creds.
#
function domysql(){
  host="${host:-${uri_host}}"
  user="${user:-${uri_username}}"
  pass="${pass:-${uri_password}}"
  mysql "-h${host}" "-u${user}" "-p${pass}" "$@"
}

##
# Execute a SQL statement in the configured database.
#
function dbexec(){
  domysql -D "${uri_database}" -e "$@"
}

##
# Utility: test if the configured database has a populated Drupal config table.
#
function drupaldbexists(){
  dbexec "select count(*) from config" 2>&1 >> /dev/null
}

##
# Utility: test if the configured database is reachable.
#
function dbalive(){
  user="${DATABASE_ROOT_USER}" pass="${DATABASE_ROOT_PASS}" domysql -e "show databases" 2>&1 > /dev/null
}

##
# Utility: test if the configured database exists.
#
function dbexists(){
  user="${DATABASE_ROOT_USER}" pass="${DATABASE_ROOT_PASS}" dbexec "show tables" 2>&1 >> /dev/null
}

##
# Utility: import SQL from standard input into the configured database.
#
function dbimport(){
  domysql -D "${uri_database}" 2>&1 >> /dev/null
}

# Symlink user's mounted composer.json file to system composer.json
if [[ ! -f ${PROJECT_DIR}/composer.json \
  && -f ${COMPOSER_PROJECT_DIR}/composer.json \
  && ! -L ${COMPOSER_PROJECT_DIR}/composer.json ]]; then
  cp ${COMPOSER_PROJECT_DIR}/composer.json ${PROJECT_DIR}/composer.json
  rm ${COMPOSER_PROJECT_DIR}/composer.json
  ln -s ${PROJECT_DIR}/composer.json ${COMPOSER_PROJECT_DIR}/composer.json
fi

# Wait for mysql.
echo "- Waiting for mysql ..."
while ! dbalive 2>&1 > /dev/null ; do
  echo -n "."
  sleep 1
done
echo

# Issue CREATE DATABASE and grant privileges if it does not exist.
if ! dbexists; then
  echo "- Database '${uri_database}' does not exist, creating it."
  user="${DATABASE_ROOT_USER}" pass="${DATABASE_ROOT_PASS}" domysql -e "CREATE DATABASE ${uri_database}" 2>&1 >> /dev/null \
    || echo "Could not create database."
  user="${DATABASE_ROOT_USER}" pass="${DATABASE_ROOT_PASS}" domysql -e "CREATE USER ${uri_username} IDENTIFIED BY '${uri_password}'" 2>&1 >> /dev/null \
    || echo "Could not create database user."
  user="${DATABASE_ROOT_USER}" pass="${DATABASE_ROOT_PASS}" domysql -e "GRANT ALL PRIVILEGES ON ${uri_database}.* TO ${uri_username}" 2>&1 >> /dev/null \
    || echo "Could not grant privileges to ${uri_username} on ${uri_database}."
fi

# Import user database if $DATABASE_SQL_FILE is declared.
if [[ ! -z "${DATABASE_SQL_FILE}" ]]; then
  if [[ -f "${DATABASE_SQL_FILE}" ]]; then
    if test $(echo "${DATABASE_SQL_FILE}" | grep ".sql.gz$"); then
      zcat "${DATABASE_SQL_FILE}" | dbimport \
        || echo "Could not import database from file '${DATABASE_SQL_FILE}'."
    else
      dbimport < "${DATABASE_SQL_FILE}" \
        || echo "Could not import database from file '${DATABASE_SQL_FILE}'."
    fi
  else
    echo "Could not restore database from file '${DATABASE_SQL_FILE}', file not found or not readable."
  fi
fi

# If we still don't have a Drupal installation, try to build one with Drush.
if ! drupaldbexists; then

  # We need to make sure sites/default/default.settings.php exists before
  # running Drush here even though a user share might have obscured the one
  # in the image. So we run composer update here to re-generate missing files.
  [[ ! -f "${DRUPAL_CORE_DIR}/sites/default/default.settings.php" ]] && composer update

  # Install site.
  drush -y site:install standard \
    --site-name="${DRUPAL_SITE_NAME}" \
    --db-url="${DATABASE_URI}" \
    --db-su="${DATABASE_ROOT_USER}" \
    --db-su-pw="${DATABASE_ROOT_PASS}" \
    --account-name="${DRUPAL_ADMIN_USERNAME}" \
    --account-pass="${DRUPAL_ADMIN_PASSWORD}"
fi

# Development mode: enable Twig debugging.
echo -n "- enable twig debugging..."
if [[ -f /var/www/html/web/sites/default/services.yml ]]; then
  echo " services.yml already installed."
else 
  cp /tmp/dev.services.yml /var/www/html/web/sites/default/services.yml
  echo " installed services.yml."
fi

# User configuration.
[[ ! -z ${DRUPAL_MODULES} ]] && drush -y en ${DRUPAL_MODULES}
[[ ! -z ${DRUPAL_THEMES} ]] && drush -y theme:enable ${DRUPAL_THEMES}
[[ ! -z ${DRUPAL_DEFAULT_THEME} ]] && drush -y config-set system.theme default "${DRUPAL_DEFAULT_THEME}"
[[ ! -z ${DRUPAL_FRONT_PAGE} ]] && drush -y config-set system.site page.front "${DRUPAL_FRONT_PAGE}"
[[ -d "${DRUPAL_FEATURES_DIR}" ]] && drush -y en $(ls "${DRUPAL_FEATURES_DIR}")

# Development mode: disable css/js aggregation.
drush -y config-set system.performance css.preprocess 0 2>&1 >> /dev/null
drush -y config-set system.performance js.preprocess 0 2>&1 >> /dev/null

# Development mode: run `npm install` in gulp directory.
# TODO these could be configurable if anyone wants it.
extra_apt_packages="nodejs npm"
npm_global_packages="npm@latest n"
node_version=10
if [[ -d "${GULP_THEME}" ]]; then
  echo "- Gulp support..."
  echo "   * Apt install ${extra_apt_packages}..."
  apt-get update 2>&1 >> /dev/null
  apt-get -y install ${extra_apt_packages} 2>&1 >> /dev/null
  echo "   * Npm install ${npm_global_packages}..."
  npm install -g ${npm_global_packages} 2>&1 >> /dev/null
  echo "   * Change node version to ${node_version}..."
  n ${node_version} 2>&1 >> /dev/null
  echo "   * Run npm install in ${GULP_THEME}..."
  cd "${GULP_THEME}"
  npm install 2>&1 >> /dev/null
fi

# Cache reload.
echo "- Drupal cache reload..."
drush -y cr

# Fix up permissions for Apache.
echo "- Changing ownership of /var/www to www-data.www-data..."
chown -R www-data.www-data /var/www

# Run Apache.
echo "- Start Apache..."
read pid cmd state ppid pgrp session tty_nr tpgid rest < /proc/self/stat
trap "kill -TERM -${pgrp}; exit" EXIT TERM KILL SIGKILL SIGTERM SIGQUIT
. /etc/apache2/envvars
apache2 -D FOREGROUND
