FROM ubuntu:latest

# Configuration variables.
ENV DATABASE_URI unspecified
ENV PROJECT_DIR /app
ENV PHP_INI /etc/php/7.2/apache2/php.ini
ENV COMPOSER_PROJECT_DIR /var/www/html
ENV DRUPAL_CORE_DIR ${COMPOSER_PROJECT_DIR}/web
ENV DRUPAL_PROJECT drupal/recommended-project
ENV DRUPAL_SITE_NAME "Drupal Website"
ENV DATABASE_ROOT_USER root
ENV DATABASE_ROOT_PASS root
ENV DRUPAL_ADMIN_USERNAME admin
ENV DRUPAL_ADMIN_PASSWORD admin
ENV DRUPAL_MODULES ""
ENV DRUPAL_THEMES ""
ENV DRUPAL_DEFAULT_THEME ""
ENV DRUPAL_FRONT_PAGE ""
ENV DRUPAL_FEATURES_DIR ""
ENV MEMCACHED_HOST memcached
ENV MEMCACHED_PORT 11211

# Basic Ubuntu/apt packages.
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update; \
  dpkg-divert --local --rename --add /sbin/initctl; \
  ln -sf /bin/true /sbin/initctl; \
  apt-get -y install \
    mysql-client apache2 libapache2-mod-php php php-cli php-common \
    php-gd php-json php-mbstring php-xdebug php-mysql php-opcache \
    php-curl php-readline php-xml php-memcached php-oauth php-bcmath \
    php-zip php-uploadprogress git curl wget locales iproute2 pwgen \
    anacron cron m4 unison netcat net-tools nano unzip jq vim; \
  sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd; \
  echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config; \
  locale-gen en_US.UTF-8; \
  mkdir -p /var/run/sshd

# This script freezes up if anyone tries running Cron. Remove it.
RUN rm -f /etc/cron.daily/apt-compat

# Apache setup.
RUN mkdir -p /var/lock/apache2 /var/run/apache2
RUN rm /etc/apache2/sites-available/000-default.conf /etc/apache2/sites-enabled/*
ADD 000-default.conf /etc/apache2/sites-available/000-default.conf
RUN a2ensite 000-default ; a2enmod rewrite vhost_alias
RUN service apache2 stop
RUN update-rc.d -f apache2 remove
RUN rm -f /var/run/apache2/apache2.pid

# PHP
COPY xdebug.ini /etc/php/7.2/mods-available/xdebug.ini
RUN phpenmod xdebug
# The command line version of xdebug segfaults. Disable it.
RUN rm -f /etc/php/7.2/cli/conf.d/20-xdebug.ini

# Install Composer.
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer \
  && php --version; composer --version

# Drush and Drupal Console.
RUN HOME=/ /usr/local/bin/composer global require drush/drush:~9 \
  && ln -s /.composer/vendor/bin/drush /usr/local/bin/drush \
  && curl https://drupalconsole.com/installer -L -o /usr/local/bin/drupal \
  && chmod +x /usr/local/bin/drupal \
  && php --version; composer --version; drupal --version; drush --version \
  && rm -rf /var/www/html/*

# onbuild.sh runs `composer create-project` if needed and `composer install`.
COPY onbuild.sh /usr/local/bin/drupalbase-onbuild.sh
RUN chmod +x /usr/local/bin/drupalbase-onbuild.sh
ONBUILD COPY . /appinstall
ONBUILD RUN /usr/local/bin/drupalbase-onbuild.sh "${COMPOSER_PROJECT_DIR}" "${DRUPAL_PROJECT}"
ONBUILD RUN rm /usr/local/bin/drupalbase-onbuild.sh
ONBUILD RUN rm -rf /appinstall

# cmd.sh does container init and starts Apache.
COPY cmd.sh /usr/local/bin/drupalbase-cmd.sh
RUN chmod +x /usr/local/bin/drupalbase-cmd.sh
CMD /bin/bash /usr/local/bin/drupalbase-cmd.sh

# Drupal development services.yml
COPY dev.services.yml /tmp/dev.services.yml

# Handy to start off in the composer home base for running drush, drupal console, or composer commands.
WORKDIR ${COMPOSER_PROJECT_DIR}

# 80 is used in dev.
EXPOSE 80

# 443 exposed in case anyone wants to use this container to test letsencrypt.
EXPOSE 443

# 9000 exposed if anyone wants to connect to xdebug from outside container.
EXPOSE 9000
