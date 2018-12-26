#!/bin/bash
CURRENT_PASS=""
NEW_MYSQL_PASS="PASSWORD"

yum -y update;
yum -y upgrade;
echo "Root MySQL Password: $rootmysqlpass" > /root/passwords.txt;
echo "Wordpress MySQL Password: $wpmysqlpass" >> /root/passwords.txt;
yum -y install epel-release;
yum -y install nginx php-fpm php-mysql mariadb-server mariadb;
mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
cat > /etc/nginx/nginx.conf << "EOF"
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;
      
events {
          worker_connections 1024;
}
      
http {
log_format  main    '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
access_log          /var/log/nginx/access.log  main;
sendfile            on;
tcp_nopush          on;
tcp_nodelay         on;
keepalive_timeout   65;
types_hash_max_size 2048;
include             /etc/nginx/mime.types;
default_type        application/octet-stream;
include             /etc/nginx/conf.d/*.conf;
}
EOF
sed -i -e "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" /etc/php.ini
sed -i -e "s|listen = 127.0.0.1:9000|listen = /var/run/php-fpm/php-fpm.sock|" /etc/php-fpm.d/www.conf;
sed -i -e "s|user = apache|user = nginx|" /etc/php-fpm.d/www.conf;
sed -i -e "s|group = apache|group = nginx|" /etc/php-fpm.d/www.conf;

cat > /etc/nginx/conf.d/default.conf << "EOF"
server {
listen 80 default_server;
listen [::]:80 default_server ipv6only=on;
root /var/www/html;
index index.php index.html index.htm;
server_name 52.53.240.180;
 
location / {
    try_files $uri $uri/ /index.php?$args;
}

error_page 404 /404.html;
error_page 500 502 503 504 /50x.html;
location = /50x.html {
    root /usr/share/nginx/html;
}

location ~ \.php$ {
try_files $uri =404;
fastcgi_split_path_info ^(.+\.php)(/.+)$;
fastcgi_pass unix:/var/run/php-fpm/php-fpm.sock;
fastcgi_index index.php;
fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
include fastcgi_params;
}
}
EOF
wget https://wordpress.org/latest.zip -O /tmp/wordpress.zip;
cd /tmp/;
unzip /tmp/wordpress.zip;

systemctl start mariadb.service;
systemctl start nginx.service;
systemctl start php-fpm.service;
/usr/bin/mysqladmin -u root -h localhost create wordpress;
/usr/bin/mysqladmin -u root -h localhost password $rootmysqlpass;
/usr/bin/mysql -uroot -p$rootmysqlpass -e "CREATE USER wordpress@localhost IDENTIFIED BY '"$wpmysqlpass"'";
/usr/bin/mysql -uroot -p$rootmysqlpass -e "GRANT ALL PRIVILEGES ON wordpress.* TO wordpress@localhost";
cp /tmp/wordpress/wp-config-sample.php /tmp/wordpress/wp-config.php;
sed -i "s/'DB_NAME', 'ENTER_DATABASE_NAME_HERE'/'DB_NAME', 'wordpress'/g" /tmp/wordpress/wp-config.php;
sed -i "s/'DB_USER', 'ENTER_DATABASE_USER_HERE'/'DB_USER', 'wordpress'/g" /tmp/wordpress/wp-config.php;
sed -i "s/'DB_PASSWORD', 'ENTER_DATABASE_PASSWORD_HERE'/'DB_PASSWORD', '$wpmysqlpass'/g" /tmp/wordpress/wp-config.php;
for i in `seq 1 8`
do
wp_salt=$(</dev/urandom tr -dc 'a-zA-Z0-9!@#$%^&*()\-_ []{}<>~`+=,.;:/?|' | head -c 64 | sed -e 's/[\/&]/\\&/g');
sed -i "0,/put your unique phrase here/s/put your unique phrase here/$wp_salt/" /tmp/wordpress/wp-config.php;
done
mkdir -p /var/www/html
chmod -R 755 /var/www/html
chown -R nginx:nginx /var/nginx/html
cp -Rf /tmp/wordpress/* /var/www/html/.;
rm -f /var/www/html/index.html;
rm -Rf /tmp/wordpress*;
chown -Rf nginx:nginx /var/www/html;
systemctl enable mariadb.service;
systemctl enable php-fpm.service;
systemctl enable nginx.service;
systemctl restart nginx.service;
setenforce 0