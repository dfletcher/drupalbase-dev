#!/bin/bash

cd ${COMPOSER_PROJECT_DIR}

# Copy user composer.json or ask composer to create one using the create-project command.
if [[ -f /appinstall/composer.json ]]; then
  cp /appinstall/composer.json ${COMPOSER_PROJECT_DIR}/composer.json
else
  composer create-project ${DRUPAL_PROJECT} ${COMPOSER_PROJECT_DIR} --no-install --no-interaction 
fi

# Run composer install.
composer install
