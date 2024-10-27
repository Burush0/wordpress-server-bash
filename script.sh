#!/bin/bash

DB_PASSWORD=$1
SERVER_DOMAIN=$2

if [[ -z "$DB_PASSWORD" || -z "$SERVER_DOMAIN" ]]; then
  echo "Usage: $0 <DB_PASSWORD> <SERVER_DOMAIN>"
  exit 1
fi

apt update -y && apt upgrade -y && apt dist-upgrade -y &&
apt install openssh-server postgresql apache2 ghostscript libapache2-mod-php php php-bcmath php-curl php-imagick php-intl php-json php-mbstring php-mysql php-pgsql php-xml php-zip -y &&
apt autoremove -y && apt autoclean -y


# on host:
# (generate an ssh key) e.g. ssh-keygen -t rsa -b 4096
#ssh-copy-id <remote-user>@<ip-address>

sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart ssh

sudo -u postgres psql << EOF
create database wordpress;
create user wordpress with encrypted password '$DB_PASSWORD';
grant all privileges on database wordpress to wordpress;
\q
EOF

mkdir -p /srv/www
curl https://wordpress.org/latest.tar.gz | tar zx -C /srv/www

cat > /etc/apache2/sites-available/wordpress.conf << EOF
<VirtualHost *:8080>
    DocumentRoot /srv/www/
    <Directory /srv/www/wordpress>
        Options FollowSymLinks
        AllowOverride Limit Options FileInfo
        DirectoryIndex index.php
        Require all granted
    </Directory>
    <Directory /srv/www/wordpress/wp-content>
        Options FollowSymLinks
        Require all granted
    </Directory>
</VirtualHost>
EOF

a2ensite wordpress
a2enmod rewrite
a2dissite 000-default
systemctl restart apache2

cd /srv/www/wordpress/wp-content
git clone https://github.com/PostgreSQL-For-Wordpress/postgresql-for-wordpress.git
mv postgresql-for-wordpress/pg4wp pg4wp
cp pg4wp/db.php db.php
rm -rf postgresql-for-wordpress

cp /srv/www/wordpress/wp-config-sample.php /srv/www/wordpress/wp-config.php

tmp=$(mktemp) || exit 1
trap 'rm -f "$tmp"; exit' EXIT

curl -k -s 'https://api.wordpress.org/secret-key/1.1/salt/' |
awk -F"'" '
    BEGIN { OFS=FS }
    NR == FNR {
        map[$2] = $4
        next
    }
    /^define\(/ && ($2 in map) {
        $4 = map[$2]
    }
    { print }
' - "/srv/www/wordpress/wp-config.php" > "$tmp" &&
mv -- "$tmp" "/srv/www/wordpress/wp-config.php"

sed -i 's/database_name_here/wordpress/' /srv/www/wordpress/wp-config.php
sed -i 's/username_here/wordpress/' /srv/www/wordpress/wp-config.php
sed -i "s/password_here/$DB_PASSWORD/" /srv/www/wordpress/wp-config.php

sed -i "/\/\* Add any custom values between this line and the \"stop editing\" line. \*\//a \
define( 'FORCE_SSL_ADMIN', true );\
if( strpos( \$_SERVER['HTTP_X_FORWARDED_PROTO'], 'https') !== false )\
    \$_SERVER['HTTPS'] = 'on';" /srv/www/wordpress/wp-config.php

chown www-data: /srv/www
chmod 644 /srv/www/wordpress/wp-config.php

sed -i 's/Listen 80/Listen 8080/' /etc/apache2/ports.conf

apt install nginx -y

openssl req -x509 -noenc -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/nginx-selfsigned.key -out /etc/ssl/certs/nginx-selfsigned.crt -subj "/C=SE/ST=Vaestra Goetalands laen/L=Goeteborg/O=Burush Inc. /OU=DevOps Department/CN=Burush"

openssl dhparam -out /etc/nginx/dhparam.pem 4096

cat > /etc/nginx/snippets/self-signed.conf << EOF
ssl_certificate /etc/ssl/certs/nginx-selfsigned.crt;
ssl_certificate_key /etc/ssl/private/nginx-selfsigned.key;
EOF

cat > /etc/nginx/snippets/ssl-params.conf << EOF
ssl_protocols TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_dhparam /etc/nginx/dhparam.pem; 
ssl_ciphers EECDH+AESGCM:EDH+AESGCM;
ssl_ecdh_curve secp384r1;
ssl_session_timeout  10m;
ssl_session_cache shared:SSL:10m;
ssl_session_tickets off;
ssl_stapling on;
ssl_stapling_verify on;
resolver 1.1.1.1 1.0.0.1 valid=300s;
resolver_timeout 5s;
# Disable strict transport security for now. You can uncomment the following
# line if you understand the implications.
#add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";
add_header X-Frame-Options DENY;
add_header X-Content-Type-Options nosniff;
add_header X-XSS-Protection "1; mode=block";
EOF

cat > /etc/nginx/sites-available/wordpress << EOF
server {
        listen 443 ssl;
        listen [::]:443 ssl;
        include snippets/self-signed.conf;
        include snippets/ssl-params.conf;

        root /var/www/html;

        index index.html index.htm index.nginx-debian.html;

        server_name $SERVER_DOMAIN;

        location / {
                try_files \$uri \$uri/ =404;
        }

        location /wordpress/ {
                proxy_pass http://127.0.0.1:8080;
                proxy_set_header Host \$host;
                proxy_set_header X-Real-IP \$remote_addr;
                proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Host \$server_name;
                proxy_set_header X-Forwarded-Proto \$scheme;
                proxy_redirect off;
        }

        location /site {
                alias /var/www/test;
                index index.html;
                try_files \$uri \$uri/ =404;
        }
}

server {
        listen 80;
        listen [::]:80;

        server_name $SERVER_DOMAIN;

        return 301 https://\$server_name\$request_uri;
}
EOF

ln -s /etc/nginx/sites-available/wordpress /etc/nginx/sites-enabled/

systemctl restart nginx

mkdir /var/www/test
cat > /var/www/test/index.html << EOF
<!doctype html>
<html>
<head>
    <meta charset="utf-8">
    <title>Hello, Nginx!</title>
</head>
<body>
    <h1>Hello, Nginx!</h1>
    <p>We have just configured our Nginx web server on Ubuntu Server!</p>
</body>
</html>
EOF

ufw allow 22,80,443/tcp
ufw --force enable

systemctl restart apache2
systemctl restart nginx