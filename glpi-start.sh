#!/bin/bash

# Check and set the GLPI version or use the latest if not specified
[[ ! "$VERSION_GLPI" ]] \
  && VERSION_GLPI=$(curl -s https://api.github.com/repos/glpi-project/glpi/releases/latest | grep tag_name | cut -d '"' -f 4)

if [[ -z "${TIMEZONE}" ]]; then
  echo "TIMEZONE is unset"
else
  echo "date.timezone = \"$TIMEZONE\"" > /etc/php/8.3/apache2/conf.d/timezone.ini
  echo "date.timezone = \"$TIMEZONE\"" > /etc/php/8.3/cli/conf.d/timezone.ini
fi

# Enable session.cookie_httponly
sed -i 's,session.cookie_httponly = *\(on\|off\|true\|false\|0\|1\)\?,session.cookie_httponly = on,gi' /etc/php/8.3/apache2/php.ini

FOLDER_GLPI=glpi/
FOLDER_WEB=/var/www/html/

# Check if TLS_REQCERT is present
if ! grep -q "TLS_REQCERT" /etc/ldap/ldap.conf; then
  echo "TLS_REQCERT isn't present"
  echo -e "TLS_REQCERT\tnever" >> /etc/ldap/ldap.conf
fi

# Clone the specified version of GLPI
if [ -d "${FOLDER_WEB}${FOLDER_GLPI}/bin" ]; then
  echo "GLPI is already installed"
else
  git clone --branch ${VERSION_GLPI} https://github.com/glpi-project/glpi.git ${FOLDER_WEB}${FOLDER_GLPI}
fi

# Set ownership and permissions
chown -R www-data:www-data ${FOLDER_WEB}${FOLDER_GLPI}
find ${FOLDER_WEB}${FOLDER_GLPI} -type d -exec chmod 755 {} \;
find ${FOLDER_WEB}${FOLDER_GLPI} -type f -exec chmod 644 {} \;

# Adapt the Apache server according to the version of GLPI installed
LOCAL_GLPI_VERSION=$(cat ${FOLDER_WEB}${FOLDER_GLPI}/version)
LOCAL_GLPI_MAJOR_VERSION=$(echo $LOCAL_GLPI_VERSION | cut -d. -f1)
LOCAL_GLPI_VERSION_NUM=${LOCAL_GLPI_VERSION//./}

TARGET_GLPI_VERSION="10.0.7"
TARGET_GLPI_VERSION_NUM=${TARGET_GLPI_VERSION//./}
TARGET_GLPI_MAJOR_VERSION=$(echo $TARGET_GLPI_VERSION | cut -d. -f1)

# Compare the numeric value of the version number to the target number
if [[ $LOCAL_GLPI_VERSION_NUM -lt $TARGET_GLPI_VERSION_NUM || $LOCAL_GLPI_MAJOR_VERSION -lt $TARGET_GLPI_MAJOR_VERSION ]]; then
  echo -e "<VirtualHost *:80>\n\tDocumentRoot /var/www/html/glpi\n\n\t<Directory /var/www/html/glpi>\n\t\tAllowOverride All\n\t\tOrder Allow,Deny\n\t\tAllow from all\n\t</Directory>\n\n\tErrorLog /var/log/apache2/error-glpi.log\n\tLogLevel warn\n\tCustomLog /var/log/apache2/access-glpi.log combined\n</VirtualHost>" > /etc/apache2/sites-available/000-default.conf
else
  set +H
  echo -e "<VirtualHost *:80>\n\tDocumentRoot /var/www/html/glpi/public\n\n\t<Directory /var/www/html/glpi/public>\n\t\tRequire all granted\n\t\tRewriteEngine On\n\t\tRewriteCond %{REQUEST_FILENAME} !-f\n\t\n\t\tRewriteRule ^(.*)$ index.php [QSA,L]\n\t</Directory>\n\n\tErrorLog /var/log/apache2/error-glpi.log\n\tLogLevel warn\n\tCustomLog /var/log/apache2/access-glpi.log combined\n</VirtualHost>" > /etc/apache2/sites-available/000-default.conf
fi

# Add scheduled task by cron and enable
echo "*/2 * * * * www-data /usr/bin/php /var/www/html/glpi/front/cron.php &>/dev/null" > /etc/cron.d/glpi
# Start cron service
service cron start

# Enable the rewrite module in Apache and restart Apache
a2enmod rewrite && service apache2 restart && service apache2 stop

# Fix to really stop apache
pkill -9 apache

# Launch Apache in the foreground
/usr/sbin/apache2ctl -D FOREGROUND
