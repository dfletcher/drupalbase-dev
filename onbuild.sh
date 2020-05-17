#!/bin/bash

COMPOSER_PROJECT_DIR="${1}"
DRUPAL_PROJECT="${2}"

cd "${COMPOSER_PROJECT_DIR}"

# Copy user composer.json or ask composer to create one using the create-project command.
if [[ -f /appinstall/composer.json ]]; then
  cp /appinstall/composer.json ${COMPOSER_PROJECT_DIR}/composer.json
  composer install
else
  composer --no-interaction create-project ${DRUPAL_PROJECT} .
fi
