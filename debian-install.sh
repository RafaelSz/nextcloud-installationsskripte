#!/bin/bash

#  ----------------------------
#  NEXTCLOUD INSTALL SCRIPT
#  ----------------------------
   
#
# PREPARE
#


addaptrepository=$(which add-apt-repository)
adduser=$(which adduser)
apt=$(which apt)
aptmark=$(which apt-mark) 
cat=$(which cat)
chmod=$(which chmod)
chown=$(which chown)
clear=$(which clear)
cp=$(which cp)
curl=$(which curl)
echo=$(which echo)
mkdir=$(which mkdir)
mv=$(which mv)
rm=$(which rm)
sed=$(which sed)
service=$(which service)
sudo=$(which sudo)
su=$(which su)
systemctl=$(which systemctl)
tar=$(which tar)
touch=$(which touch)
usermod=$(which usermod)
wget=$(which wget)


${apt} install -y figlet
figlet=$(which figlet)
${touch} /etc/motd
${figlet} nextcloud > /etc/motd
${touch} /etc/motd
${cat} <<EOF >> /etc/motd

  ----------------------------
  <NAME> SERVER <FIRMA>
  SUPPORT@PCZEIM.DE
  ----------------------------
   
EOF

# Log /nextcloud-installation/indtall.log
exec > >(tee -i "/nextcloud-installation/install.log")
exec 2>&1

function update_and_clean() {
  ${apt} update -q4
  ${apt} upgrade -yq4
  ${apt} autoclean -yq4
  ${apt} autoremove -yq4
  }

CrI() {
  while ps "$!" > /dev/null; do
  echo -n '.'
  sleep '1.0'
  done
  ${echo} ''
  }

function setHOLD() {
  ${aptmark} hold nginx*
  ${aptmark} hold redis*
  ${aptmark} hold mariadb*
  ${aptmark} hold php*
  ${aptmark} hold php8.0-*
  }

function restart_all_services() {
  ${service} nginx restart
  ${service} mysql restart
  ${service} redis-server restart
  ${service} php8.0-fpm restart
  }

function nextcloud_scan_data() {
  ${su} - www-data -s /bin/bash -c '/usr/bin/php /var/www/nextcloud/occ files:scan --all'
  ${su} - www-data -s /bin/bash -c '/usr/bin/php /var/www/nextcloud/occ files:scan-app-data'
  ${service} fail2ban restart
  }
# START
# 
${echo} 'Acquire::ForceIPv4 "true";' >> /etc/apt/apt.conf.d/99force-ipv4

${apt} install -y curl gpg 
${apt} install -y apt-transport-https bash-completion bzip2 ca-certificates debian-archive-keyring dirmngr ffmpeg ghostscript git gnupg gnupg2 htop \
libfontconfig1 libfuse2 locate lsb-release libfile-fcntllock-perl net-tools screen sudo software-properties-common ssl-cert smbclient socat tree wget unzip zip & CrI

${systemctl} mask sleep.target suspend.target hibernate.target hybrid-sleep.target

/usr/bin/curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor | tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null
${echo} "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/mainline/debian `lsb_release -cs` nginx" | tee /etc/apt/sources.list.d/nginx.list

${echo} "deb https://packages.sury.org/php/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/php.list
${wget} -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg

${wget} https://downloads.mariadb.com/MariaDB/mariadb_repo_setup
${chmod} +x mariadb_repo_setup
./mariadb_repo_setup --mariadb-server-version="mariadb-10.6"

update_and_clean

${apt} remove -y apache2 nginx nginx-common nginx-full --allow-change-held-packages
${rm} -Rf /etc/apache2 /etc/nginx

${apt} install -yq4 nginx & CrI

${systemctl} enable nginx.service

${mv} /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
${touch} /etc/nginx/nginx.conf
${cat} <<EOF >/etc/nginx/nginx.conf
user www-data;
worker_processes auto;
pid /var/run/nginx.pid;
events {
  worker_connections 1024;
  multi_accept on; use epoll;
  }
http {
  server_names_hash_bucket_size 64;
  access_log /var/log/nginx/access.log;
  error_log /var/log/nginx/error.log warn;
  set_real_ip_from 127.0.0.1;
  #optional ergänzen, bspw:
  #set_real_ip_from 192.168.2.0/24;
  real_ip_header X-Forwarded-For;
  real_ip_recursive on;
  include /etc/nginx/mime.types;
  default_type application/octet-stream;
  sendfile on;
  send_timeout 3600;
  tcp_nopush on;
  tcp_nodelay on;
  open_file_cache max=500 inactive=10m;
  open_file_cache_errors on;
  keepalive_timeout 65;
  reset_timedout_connection on;
  server_tokens off;
  resolver 127.0.0.53 valid=30s;
  resolver_timeout 5s;
  include /etc/nginx/conf.d/*.conf;
  }
EOF

${service} nginx restart

${mkdir} -p /var/log/nextcloud /var/www/letsencrypt/.well-known/acme-challenge /etc/letsencrypt/rsa-certs /etc/letsencrypt/ecc-certs

${chmod} -R 775 /var/www/letsencrypt
${chmod} -R 770 /etc/letsencrypt
${chown} -R www-data:www-data /var/log/nextcloud /var/www/ /etc/letsencrypt

${adduser} --disabled-login --gecos "" acmeuser

${usermod} -aG www-data acmeuser

${sed} -i '$aacmeuser ALL=NOPASSWD: /bin/systemctl reload nginx.service' /etc/sudoers
${su} - acmeuser -c "/usr/bin/curl https://get.acme.sh | sh"
${su} - acmeuser -c ".acme.sh/acme.sh --set-default-ca --server letsencrypt"

${apt} update -q4 & CrI

${apt} install -yq4 php8.0-{fpm,gd,mysql,curl,xml,zip,intl,mbstring,bz2,ldap,apcu,bcmath,gmp,imagick,igbinary,redis,smbclient,cli,common,opcache,readline} imagemagick ldap-utils nfs-common cifs-utils & CrI


AvailableRAM=$(/usr/bin/awk '/MemAvailable/ {printf "%d", $2/1024}' /proc/meminfo)
AverageFPM=$(/usr/bin/ps --no-headers -o 'rss,cmd' -C php-fpm8.0 | /usr/bin/awk '{ sum+=$1 } END { printf ("%d\n", sum/NR/1024,"M") }')
FPMS=$((AvailableRAM/AverageFPM))
PMaxSS=$((FPMS*2/3))
PMinSS=$((PMaxSS/2))
PStartS=$(((PMaxSS+PMinSS)/2))

${cp} /etc/php/8.0/fpm/pool.d/www.conf /etc/php/8.0/fpm/pool.d/www.conf.bak
${cp} /etc/php/8.0/fpm/php-fpm.conf /etc/php/8.0/fpm/php-fpm.conf.bak
${cp} /etc/php/8.0/cli/php.ini /etc/php/8.0/cli/php.ini.bak
${cp} /etc/php/8.0/fpm/php.ini /etc/php/8.0/fpm/php.ini.bak
${cp} /etc/php/8.0/fpm/php-fpm.conf /etc/php/8.0/fpm/php-fpm.conf.bak
${cp} /etc/ImageMagick-6/policy.xml /etc/ImageMagick-6/policy.xml.bak

${sed} -i 's/;env\[HOSTNAME\] = /env[HOSTNAME] = /' /etc/php/8.0/fpm/pool.d/www.conf
${sed} -i 's/;env\[TMP\] = /env[TMP] = /' /etc/php/8.0/fpm/pool.d/www.conf
${sed} -i 's/;env\[TMPDIR\] = /env[TMPDIR] = /' /etc/php/8.0/fpm/pool.d/www.conf
${sed} -i 's/;env\[TEMP\] = /env[TEMP] = /' /etc/php/8.0/fpm/pool.d/www.conf
${sed} -i 's/;env\[PATH\] = /env[PATH] = /' /etc/php/8.0/fpm/pool.d/www.conf
${sed} -i 's/pm.max_children =.*/pm.max_children = '$FPMS'/' /etc/php/8.0/fpm/pool.d/www.conf
${sed} -i 's/pm.start_servers =.*/pm.start_servers = '$PStartS'/' /etc/php/8.0/fpm/pool.d/www.conf
${sed} -i 's/pm.min_spare_servers =.*/pm.min_spare_servers = '$PMinSS'/' /etc/php/8.0/fpm/pool.d/www.conf
${sed} -i 's/pm.max_spare_servers =.*/pm.max_spare_servers = '$PMaxSS'/' /etc/php/8.0/fpm/pool.d/www.conf
${sed} -i 's/;pm.max_requests =.*/pm.max_requests = 2000/' /etc/php/8.0/fpm/pool.d/www.conf
${sed} -i 's/output_buffering =.*/output_buffering = 'Off'/' /etc/php/8.0/cli/php.ini
${sed} -i 's/max_execution_time =.*/max_execution_time = 3600/' /etc/php/8.0/cli/php.ini
${sed} -i 's/max_input_time =.*/max_input_time = 3600/' /etc/php/8.0/cli/php.ini
${sed} -i 's/post_max_size =.*/post_max_size = 10240M/' /etc/php/8.0/cli/php.ini
${sed} -i 's/upload_max_filesize =.*/upload_max_filesize = 10240M/' /etc/php/8.0/cli/php.ini
${sed} -i 's/;date.timezone.*/date.timezone = Europe\/\Berlin/' /etc/php/8.0/cli/php.ini
${sed} -i 's/memory_limit = 128M/memory_limit = 2048M/' /etc/php/8.0/fpm/php.ini
${sed} -i 's/output_buffering =.*/output_buffering = 'Off'/' /etc/php/8.0/fpm/php.ini
${sed} -i 's/max_execution_time =.*/max_execution_time = 3600/' /etc/php/8.0/fpm/php.ini
${sed} -i 's/max_input_time =.*/max_input_time = 3600/' /etc/php/8.0/fpm/php.ini
${sed} -i 's/post_max_size =.*/post_max_size = 10240M/' /etc/php/8.0/fpm/php.ini
${sed} -i 's/upload_max_filesize =.*/upload_max_filesize = 10240M/' /etc/php/8.0/fpm/php.ini
${sed} -i 's/;date.timezone.*/date.timezone = Europe\/\Berlin/' /etc/php/8.0/fpm/php.ini
${sed} -i 's/;session.cookie_secure.*/session.cookie_secure = True/' /etc/php/8.0/fpm/php.ini
${sed} -i 's/;opcache.enable=.*/opcache.enable=1/' /etc/php/8.0/fpm/php.ini
${sed} -i 's/;opcache.enable_cli=.*/opcache.enable_cli=1/' /etc/php/8.0/fpm/php.ini
${sed} -i 's/;opcache.memory_consumption=.*/opcache.memory_consumption=128/' /etc/php/8.0/fpm/php.ini
${sed} -i 's/;opcache.interned_strings_buffer=.*/opcache.interned_strings_buffer=8/' /etc/php/8.0/fpm/php.ini
${sed} -i 's/;opcache.max_accelerated_files=.*/opcache.max_accelerated_files=10000/' /etc/php/8.0/fpm/php.ini
${sed} -i 's/;opcache.revalidate_freq=.*/opcache.revalidate_freq=1/' /etc/php/8.0/fpm/php.ini
${sed} -i 's/;opcache.save_comments=.*/opcache.save_comments=1/' /etc/php/8.0/fpm/php.ini
${sed} -i 's/allow_url_fopen =.*/allow_url_fopen = 1/' /etc/php/8.0/fpm/php.ini
${sed} -i '$aapc.enable_cli=1' /etc/php/8.0/mods-available/apcu.ini
${sed} -i "s|;emergency_restart_threshold.*|emergency_restart_threshold = 10|g" /etc/php/8.0/fpm/php-fpm.conf
${sed} -i "s|;emergency_restart_interval.*|emergency_restart_interval = 1m|g" /etc/php/8.0/fpm/php-fpm.conf
${sed} -i "s|;process_control_timeout.*|process_control_timeout = 10|g" /etc/php/8.0/fpm/php-fpm.conf
${sed} -i 's/rights=\"none\" pattern=\"PS\"/rights=\"read|write\" pattern=\"PS\"/' /etc/ImageMagick-6/policy.xml
${sed} -i 's/rights=\"none\" pattern=\"EPS\"/rights=\"read|write\" pattern=\"EPS\"/' /etc/ImageMagick-6/policy.xml
${sed} -i 's/rights=\"none\" pattern=\"PDF\"/rights=\"read|write\" pattern=\"PDF\"/' /etc/ImageMagick-6/policy.xml
${sed} -i 's/rights=\"none\" pattern=\"XPS\"/rights=\"read|write\" pattern=\"XPS\"/' /etc/ImageMagick-6/policy.xml
/usr/bin/ln -s /usr/local/bin/gs /usr/bin/gs

${service} php8.0-fpm restart
${service} nginx restart

${apt} update -q4 & CrI

${apt} install -yq4 mariadb-server & CrI

${service} mysql stop
${mv} /etc/mysql/my.cnf /etc/mysql/my.cnf.bak
${cat} <<EOF >/etc/mysql/my.cnf
[client]
default-character-set = utf8mb4
port = 3306
socket = /var/run/mysqld/mysqld.sock
[mysqld_safe]
log_error=/var/log/mysql/mysql_error.log
nice = 0
socket = /var/run/mysqld/mysqld.sock
[mysqld]
basedir = /usr
bind-address = 127.0.0.1
binlog_format = ROW
bulk_insert_buffer_size = 16M
character-set-server = utf8mb4
collation-server = utf8mb4_general_ci
concurrent_insert = 2
connect_timeout = 5
datadir = /var/lib/mysql
default_storage_engine = InnoDB
expire_logs_days = 2
general_log_file = /var/log/mysql/mysql.log
general_log = 0
innodb_buffer_pool_size = 1024M
innodb_buffer_pool_instances = 1
innodb_flush_log_at_trx_commit = 2
innodb_log_buffer_size = 32M
innodb_max_dirty_pages_pct = 90
innodb_file_per_table = 1
innodb_open_files = 400
innodb_io_capacity = 4000
innodb_flush_method = O_DIRECT
# innodb_read_only_compressed=OFF
key_buffer_size = 128M
lc_messages_dir = /usr/share/mysql
lc_messages = en_US
log_bin = /var/log/mysql/mariadb-bin
log_bin_index = /var/log/mysql/mariadb-bin.index
log_error = /var/log/mysql/mysql_error.log
log_slow_verbosity = query_plan
log_warnings = 2
long_query_time = 1
max_allowed_packet = 16M
max_binlog_size = 100M
max_connections = 200
max_heap_table_size = 64M
myisam_recover_options = BACKUP
myisam_sort_buffer_size = 512M
port = 3306
pid-file = /var/run/mysqld/mysqld.pid
query_cache_limit = 2M
query_cache_size = 64M
query_cache_type = 1
query_cache_min_res_unit = 2k
read_buffer_size = 2M
read_rnd_buffer_size = 1M
skip-external-locking
skip-name-resolve
slow_query_log_file = /var/log/mysql/mariadb-slow.log
slow-query-log = 1
socket = /var/run/mysqld/mysqld.sock
sort_buffer_size = 4M
table_open_cache = 400
thread_cache_size = 128
tmp_table_size = 64M
tmpdir = /tmp
transaction_isolation = READ-COMMITTED
#unix_socket=OFF
user = mysql
wait_timeout = 600
[mysqldump]
max_allowed_packet = 16M
quick
quote-names
[isamchk]
key_buffer = 16M
EOF

${service} mysql restart

mysql=$(which mysql)
${mysql} <<EOF
CREATE DATABASE nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER nextcloud@localhost identified by 'nextcloud';
GRANT ALL PRIVILEGES on nextcloud.* to nextcloud@localhost;
FLUSH privileges;
EOF
${clear}
${echo} ""
${echo} " Your database server will now be hardened - just follow the instructions."
${echo} " Keep in mind: your MariaDB root password is still NOT set!"
${echo} ""

mysqlsecureinstallation=$(which mysql_secure_installation)
${mysqlsecureinstallation}

${apt} update -q4 & CrI

${apt} install -yq4 redis-server & CrI
${cp} /etc/redis/redis.conf /etc/redis/redis.conf.bak
${sed} -i 's/port 6379/port 0/' /etc/redis/redis.conf
${sed} -i s/\#\ unixsocket/\unixsocket/g /etc/redis/redis.conf
${sed} -i 's/unixsocketperm 700/unixsocketperm 770/' /etc/redis/redis.conf
${sed} -i 's/# maxclients 10000/maxclients 512/' /etc/redis/redis.conf
${cp} /etc/sysctl.conf /etc/sysctl.conf.bak
${sed} -i '$avm.overcommit_memory = 1' /etc/sysctl.conf

${usermod} -a -G redis www-data

${apt} install -yq4 ssl-cert & CrI

[ -f /etc/nginx/conf.d/default.conf ] && ${mv} /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.bak
${touch} /etc/nginx/conf.d/default.conf
${touch} /etc/nginx/conf.d/http.conf
${cat} <<EOF >/etc/nginx/conf.d/http.conf

upstream php-handler {
  server unix:/run/php/php8.0-fpm.sock;
  }
  server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name YOUR.DEDYN.IO;
    root /var/www;
    location ^~ /.well-known/acme-challenge {
      default_type text/plain;
      root /var/www/letsencrypt;
      }
    location / {
      return 301 https://\$host\$request_uri;
      }
    }
EOF

${cat} <<EOF >/etc/nginx/conf.d/nextcloud.conf
server {
  listen 443 ssl http2 default_server;
  listen [::]:443 ssl http2 default_server;
  server_name YOUR.DEDYN.IO;
  ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
  ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;
  ssl_trusted_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
  #ssl_certificate /etc/letsencrypt/rsa-certs/fullchain.pem;
  #ssl_certificate_key /etc/letsencrypt/rsa-certs/privkey.pem;
  #ssl_certificate /etc/letsencrypt/ecc-certs/fullchain.pem;
  #ssl_certificate_key /etc/letsencrypt/ecc-certs/privkey.pem;
  #ssl_trusted_certificate /etc/letsencrypt/ecc-certs/chain.pem;
  ssl_dhparam /etc/ssl/certs/dhparam.pem;
  ssl_session_timeout 1d;
  ssl_session_cache shared:SSL:50m;
  ssl_session_tickets off;
  ssl_protocols TLSv1.3 TLSv1.2;
  ssl_ciphers 'TLS-CHACHA20-POLY1305-SHA256:TLS-AES-256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384';
  ssl_ecdh_curve X448:secp521r1:secp384r1;
  ssl_prefer_server_ciphers on;
  ssl_stapling on;
  ssl_stapling_verify on;
  client_max_body_size 10G;
  client_body_timeout 3600s;
  fastcgi_buffers 64 4K;
  gzip on;
  gzip_vary on;
  gzip_comp_level 4;
  gzip_min_length 256;
  gzip_proxied expired no-cache no-store private no_last_modified no_etag auth;
  gzip_types application/atom+xml application/javascript application/json application/ld+json application/manifest+json application/rss+xml application/vnd.geo+json application/vnd.ms-fontobject application/wasm application/x-font-ttf application/x-web-app-manifest+json application/xhtml+xml application/xml font/opentype image/bmp image/svg+xml image/x-icon text/cache-manifest text/css text/plain text/vcard text/vnd.rim.location.xloc text/vtt text/x-component text/x-cross-domain-policy;
  add_header Strict-Transport-Security "max-age=15768000; includeSubDomains; preload;" always;
  add_header Permissions-Policy "interest-cohort=()";
  add_header Referrer-Policy "no-referrer" always;
  add_header X-Content-Type-Options "nosniff" always;
  add_header X-Download-Options "noopen" always;
  add_header X-Frame-Options "SAMEORIGIN" always;
  add_header X-Permitted-Cross-Domain-Policies "none" always;
  add_header X-Robots-Tag "none" always;
  add_header X-XSS-Protection "1; mode=block" always;
  fastcgi_hide_header X-Powered-By;
  root /var/www/nextcloud;
  index index.php index.html /index.php\$request_uri;
  location = / {
    if ( \$http_user_agent ~ ^DavClnt ) {
      return 302 /remote.php/webdav/\$is_args\$args;
      }
  }
  location = /robots.txt {
    allow all;
    log_not_found off;
    access_log off;
    }
  location ^~ /apps/rainloop/app/data {
    deny all;
    }
  location ^~ /.well-known {
    location = /.well-known/carddav { return 301 /remote.php/dav/; }
    location = /.well-known/caldav  { return 301 /remote.php/dav/; }
    location /.well-known/acme-challenge { try_files \$uri \$uri/ =404; }
    location /.well-known/pki-validation { try_files \$uri \$uri/ =404; }
    return 301 /index.php\$request_uri;
    }
  location ~ ^/(?:build|tests|config|lib|3rdparty|templates|data)(?:\$|/)  { return 404; }
  location ~ ^/(?:\.|autotest|occ|issue|indie|db_|console)  { return 404; }
  location ~ \.php(?:\$|/) {
    rewrite ^/(?!index|test|remote|public|cron|core\/ajax\/update|status|ocs\/v[12]|updater\/.+|oc[ms]-provider\/.+|.+\/richdocumentscode\/proxy) /index.php\$request_uri;
    fastcgi_split_path_info ^(.+?\.php)(/.*)\$;
    set \$path_info \$fastcgi_path_info;
    try_files \$fastcgi_script_name =404;
    include fastcgi_params;
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    fastcgi_param PATH_INFO \$path_info;
    fastcgi_param HTTPS on;
    fastcgi_param modHeadersAvailable true;
    fastcgi_param front_controller_active true;
    fastcgi_pass php-handler;
    fastcgi_intercept_errors on;
    fastcgi_request_buffering off;
    fastcgi_read_timeout 3600;
    fastcgi_send_timeout 3600;
    fastcgi_connect_timeout 3600;
    }
  location ~ \.(?:css|js|svg|gif|png|jpg|ico|wasm|tflite)\$ {
    try_files \$uri /index.php\$request_uri;
    expires 6M;
    access_log off;
    location ~ \.wasm\$ {
      default_type application/wasm;
      }
    }
  location ~ \.woff2?\$ {
    try_files \$uri /index.php\$request_uri;
    expires 7d;
    access_log off;
    }
  location /remote {
    return 301 /remote.php\$request_uri;
    }
  location / {
    try_files \$uri \$uri/ /index.php\$request_uri;
    }
}
EOF

/usr/bin/openssl dhparam -dsaparam -out /etc/ssl/certs/dhparam.pem 4096

${sed} -i "s/server_name YOUR.DEDYN.IO;/server_name $(hostname);/" /etc/nginx/conf.d/http.conf
${sed} -i "s/server_name YOUR.DEDYN.IO;/server_name $(hostname);/" /etc/nginx/conf.d/nextcloud.conf

(/usr/bin/crontab -u www-data -l ; echo "*/5 * * * * /usr/bin/php -f /var/www/nextcloud/cron.php > /dev/null 2>&1") | /usr/bin/crontab -u www-data -

${service} nginx restart

${wget} https://download.nextcloud.com/server/releases/latest.tar.bz2
${tar} -xjf latest.tar.bz2 -C /var/www

${chown} -R www-data:www-data /var/www/

${rm} -f latest.tar.bz2

update_and_clean

restart_all_services
${clear}
${echo} "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
${echo} "Nextcloud-Administrator and password - Attention: password is case-sensitive:"
${echo} "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
${echo} ""
${echo} "Your Nextcloud-DB user: nextcloud"
${echo} ""
${echo} "Your Nextcloud-DB password: nextcloud"
${echo} ""
read -p "Enter your Nextcloud Administrator: " NEXTCLOUDADMINUSER
${echo} "Your Nextcloud Administrator: "$NEXTCLOUDADMINUSER
${echo} ""
read -p "Enter your Nextcloud Administrator password: " NEXTCLOUDADMINUSERPASSWORD
${echo} "Your Nextcloud Administrator password: "$NEXTCLOUDADMINUSERPASSWORD
${echo} ""
while [[ $NEXTCLOUDDATAPATH == '' ]]
do
read -p "Enter your absolute Nextcloud datapath (/your/path): " NEXTCLOUDDATAPATH
if [[ -z "$NEXTCLOUDDATAPATH" ]]; then
${echo} "datapath must not be empty!"
${echo} ""
else
${echo} "Your Nextcloud datapath: "$NEXTCLOUDDATAPATH
fi
done
if [[ ! -e $NEXTCLOUDDATAPATH ]];
then
${mkdir} -p $NEXTCLOUDDATAPATH
fi
${chown} -R www-data:www-data $NEXTCLOUDDATAPATH
${echo} "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
${echo} ""
${echo} "Your NEXTCLOUD will now be installed silently - please be patient ..."
${echo} ""
# NEXTCLOUD INSTALLATION "silently"
${su} - www-data -s /bin/bash -c "/usr/bin/php /var/www/nextcloud/occ maintenance:install --database mysql --database-name 'nextcloud' --database-user 'nextcloud' --database-pass 'nextcloud' --admin-user '$NEXTCLOUDADMINUSER' --admin-pass '$NEXTCLOUDADMINUSERPASSWORD' --data-dir '$NEXTCLOUDDATAPATH'"

declare -l YOURSERVERNAME
YOURSERVERNAME=$(hostname)

${cp} /var/www/nextcloud/config/config.php /var/www/nextcloud/config/config.php.bak
${su} - www-data -s /bin/bash -c '/usr/bin/php /var/www/nextcloud/occ config:system:set trusted_domains 0 --value=$HOSTNAME'
${su} - www-data -s /bin/bash -c '/usr/bin/php /var/www/nextcloud/occ config:system:set overwrite.cli.url --value=https://$HOSTNAME'
${echo} ""
${echo} "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"

${cp} /var/www/nextcloud/.user.ini /usr/local/src/.user.ini.bak

${sed} -i 's/output_buffering=.*/output_buffering=0/' /var/www/nextcloud/.user.ini
${chown} -R www-data:www-data /var/www

${su} - www-data -s /bin/bash -c '/usr/bin/php /var/www/nextcloud/occ background:cron'

${sed} -i '/);/d' /var/www/nextcloud/config/config.php
${cat} <<EOF >>/var/www/nextcloud/config/config.php
'activity_expire_days' => 14,
'auth.bruteforce.protection.enabled' => true,
'blacklisted_files' =>
array (
0 => '.htaccess',
1 => 'Thumbs.db',
2 => 'thumbs.db',
),
'cron_log' => true,
'default_phone_region' => 'DE',
'enable_previews' => true,
'enabledPreviewProviders' =>
array (
0 => 'OC\\Preview\\PNG',
1 => 'OC\\Preview\\JPEG',
2 => 'OC\\Preview\\GIF',
3 => 'OC\\Preview\\BMP',
4 => 'OC\\Preview\\XBitmap',
),
'filesystem_check_changes' => 0,
'filelocking.enabled' => 'true',
'htaccess.RewriteBase' => '/',
'integrity.check.disabled' => false,
'knowledgebaseenabled' => false,
'log_rotate_size' => 104857600,
'logfile' => '/var/log/nextcloud/nextcloud.log',
'loglevel' => 2,
'logtimezone' => 'Europe/Berlin',
'memcache.local' => '\\OC\\Memcache\\APCu',
'memcache.locking' => '\\OC\\Memcache\\Redis',
'overwriteprotocol' => 'https',
'preview_max_x' => 1024,
'preview_max_y' => 768,
'preview_max_scale_factor' => 1,
'redis' =>
array (
'host' => '/var/run/redis/redis-server.sock',
'port' => 0,
'timeout' => 0.0,
),
'quota_include_external_storage' => false,
'share_folder' => '/Shares',
'skeletondirectory' => '',
'trashbin_retention_obligation' => 'auto, 7',
);
EOF

${sed} -i 's/^[ ]*//' /var/www/nextcloud/config/config.php

${chown} -R www-data:www-data /var/www

restart_all_services

${apt} update -q4 & CrI

${apt} install -yq4 fail2ban & CrI

${touch} /etc/fail2ban/filter.d/nextcloud.conf
${cat} <<EOF >/etc/fail2ban/filter.d/nextcloud.conf
[Definition]
_groupsre = (?:(?:,?\s*"\w+":(?:"[^"]+"|\w+))*)
failregex = ^\{%(_groupsre)s,?\s*"remoteAddr":"<HOST>"%(_groupsre)s,?\s*"message":"Login failed:
            ^\{%(_groupsre)s,?\s*"remoteAddr":"<HOST>"%(_groupsre)s,?\s*"message":"Trusted domain error.
datepattern = ,?\s*"time"\s*:\s*"%%Y-%%m-%%d[T ]%%H:%%M:%%S(%%z)?"
EOF
# Anlegen der fail2ban Nextcloud "jail-Datei
${touch} /etc/fail2ban/jail.d/nextcloud.local
${cat} <<EOF >/etc/fail2ban/jail.d/nextcloud.local
[nextcloud]
backend = auto
enabled = true
port = 80,443
protocol = tcp
filter = nextcloud
maxretry = 5
bantime = 3600
findtime = 3600
logpath = /var/log/nextcloud/nextcloud.log
[nginx-http-auth]
enabled = true
EOF

${apt} update -q4 & CrI

${apt} install -yq4 ufw & CrI


ufw=$(which ufw)
${ufw} allow 80/tcp

${ufw} allow 443/tcp

${ufw} allow 22/tcp

${ufw} logging medium && ufw default deny incoming && ufw enable

${service} ufw restart
${service} fail2ban restart
${service} redis-server restart

${su} - www-data -s /bin/bash -c '/usr/bin/php /var/www/nextcloud/occ app:disable survey_client'
${su} - www-data -s /bin/bash -c '/usr/bin/php /var/www/nextcloud/occ app:disable firstrunwizard'

${su} - www-data -s /bin/bash -c '/usr/bin/php /var/www/nextcloud/occ app:enable admin_audit'
${su} - www-data -s /bin/bash -c '/usr/bin/php /var/www/nextcloud/occ app:enable files_pdfviewer'

rediscli=$(which redis-cli)
${rediscli} -s /var/run/redis/redis-server.sock <<EOF
FLUSHALL
quit
EOF

${service} nginx stop
clear
${echo} "---------------------------------"
${echo} "Issue Nextcloud-DB optimizations!"
${echo} "---------------------------------"
${echo} ""
${su} - www-data -s /bin/bash -c '/usr/bin/php /var/www/nextcloud/occ db:add-missing-primary-keys'
${su} - www-data -s /bin/bash -c '/usr/bin/php /var/www/nextcloud/occ db:add-missing-indices'
${su} - www-data -s /bin/bash -c '/usr/bin/php /var/www/nextcloud/occ db:add-missing-columns'
${su} - www-data -s /bin/bash -c '/usr/bin/php /var/www/nextcloud/occ db:convert-filecache-bigint'
${su} - www-data -s /bin/bash -c '/usr/bin/php /var/www/nextcloud/occ security:certificates:import /etc/ssl/certs/ssl-cert-snakeoil.pem'

nextcloud_scan_data

restart_all_services

${su} - www-data -s /bin/bash -c '/usr/bin/php /var/www/nextcloud/cron.php'

setHOLD

# ${clear}
${echo} ""
${echo} "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
${echo} ""
${echo} " Open your browser and call your Nextcloud at"
${echo} ""
${echo} " https://$YOURSERVERNAME"
${echo} ""
${echo} "*******************************************************************************"
${echo} "Your Nextcloud DB data : nextcloud | nextcloud"
${echo} ""
${echo} "Your Nextcloud User    : "$NEXTCLOUDADMINUSER
${echo} "Your Nextcloud Password: "$NEXTCLOUDADMINUSERPASSWORD
${echo} "Your Nextcloud datapath: "$NEXTCLOUDDATAPATH
${echo} ""
${echo} "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
${echo} ""
# 
${rm} -f /var/log/nextcloud/nextcloud.log
${su} do -u www-data ${touch} /var/log/nextcloud/nextcloud.log
# 
${touch} /root/.bashrc
${cat} <<EOF >> /root/.bashrc
alias nocc="sudo -u www-data /usr/bin/php /var/www/nextcloud/occ"
EOF
# 
${touch} /root/update.sh
${cat} <<EOF >/root/update.sh
#!/bin/bash
apt update
apt upgrade -V
apt autoremove
apt autoclean
chown -R www-data:www-data /var/www/nextcloud
find /var/www/nextcloud/ -type d -exec chmod 750 {} \;
find /var/www/nextcloud/ -type f -exec chmod 640 {} \;
# 
sudo -u www-data php /var/www/nextcloud/updater/updater.phar
sudo -u www-data php /var/www/nextcloud/occ status
sudo -u www-data php /var/www/nextcloud/occ -V
sudo -u www-data php /var/www/nextcloud/occ db:add-missing-primary-keys
sudo -u www-data php /var/www/nextcloud/occ db:add-missing-indices
sudo -u www-data php /var/www/nextcloud/occ db:add-missing-columns
sudo -u www-data php /var/www/nextcloud/occ db:convert-filecache-bigint
sudo -u www-data sed -i "s/output_buffering=.*/output_buffering=0/" /var/www/nextcloud/.user.ini
# 
sudo -u www-data php /var/www/nextcloud/occ app:update --all
exit 0
EOF
${chmod} +x /root/update.sh
# 
${cat} /dev/null > ~/.bash_history
history -c
history -w
exit 0
