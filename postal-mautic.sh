#!/bin/bash

echo "please create custom NS record 'ns1' value 'your_server_ip"
echo "please create custom NS record 'ns2' value 'your_server_ip"

echo "Do you want to continue running the script? (yes/no)"
read response

# Check the user's response
if [ "$response" = "yes" ]; then
    echo "Continuing the script..."
    # Add your script logic here
else
    echo "Exiting the script."
    exit 0
fi

apt update && apt upgrade -y

read -p "Enter website domain: " domain
read -p "Enter website password: " password
db=$(echo "$domain" | cut -d '.' -f 1)
host="ns1"

###set hostname
hostnamectl set-hostname $host.$domain

####installvirtualmin

wget http://software.virtualmin.com/gpl/scripts/install.sh
chmod a+x install.sh
sudo /bin/sh install.sh

###install otheeer version of php
LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php && apt-get update

apt-get install php8.0-{cgi,cli,fpm,pdo,gd,mbstring,mysqlnd,opcache,curl,xml,zip} -y

#### Create Weebsite
virtualmin create-domain --domain $domain --pass $password --unix --dir --webmin --web --dns --mail --mysql

###Create User
virtualmin create-user --domain $domain --user  support --pass $password --quota 1024 --real "Support"
virtualmin create-user --domain $domain --user  bounce --pass $password --quota 1024 --real "Bounce"
virtualmin create-user --domain $domain --user  feedback --pass $password --quota 1024 --real "FeedBack"


path="/home/$domain/public_html"
###Set PHP version
virtualmin set-php-directory --domain $domain --dir $path --version 8.0

###Database
virtualmin create-database --domain $domain --name $db --type mysql

virtualmin modify-dns --domain $domain --add-record "_dmarc txt v=DMARC1; p=none;"
virtualmin modify-dns --domain $domain --add-record "@ ns ns2.$domain"

#######
yum install opendkim-tools -y

# Define the domain for which you want to generate DKIM keys
DOMAIN="$domain"

# Define the directory where the DKIM keys will be stored
DKIM_DIR="/etc/opendkim/keys/${domain}"

# Create the directory if it doesn't exist
mkdir -p "$DKIM_DIR"

# Generate the DKIM keys using opendkim-genkey command
opendkim-genkey -b 2048 -d "$domain" -D "$DKIM_DIR" -s default

# Change ownership and permissions of the generated keys
chown opendkim:opendkim "${DKIM_DIR}/default.private"
chmod 400 "${DKIM_DIR}/default.private"
chmod 644 "${DKIM_DIR}/default.txt"

# Extract the DKIM TXT record value from the public key file
DKIM_TXT_RECORD="v=DKIM1;k=rsa;$(cat "$DKIM_DIR/default.txt" | awk 'NR == 2 || NR == 3 {print $1}')"

# Define the DNS zone file path
ZONE_FILE="/var/named/${domain}.zone"

# Define the name of the DKIM record (default._domainkey)
DKIM_RECORD_NAME="default._domainkey.${domain}."

virtualmin modify-dns --domain $domain --add-record "$DKIM_RECORD_NAME txt $DKIM_TXT_RECORD"

# Append the DKIM record to the DNS zone file
echo "$DKIM_RECORD_NAME IN TXT \"${DKIM_TXT_RECORD}\" >> $ZONE_FILE"

# Notify BIND to reload the zone (adjust the command based on your system)
sudo rndc reload

####### mautic

#file Download

wget -O mautic.zip https://www.dropbox.com/scl/fi/c74m2kmfx406aiviz0fkd/mautic.zip?rlkey=hqs4oin2flfufhjxu1sed0n22

#moving file
source_path="/root/mautic.zip"
destination_path="/home/$db/public_html/"

# Check if the source file exists
if [ -f "$source_path" ]; then
    # Move the file to the destination
    mv "$source_path" "$destination_path"
    echo "File moved successfully!"
else
    echo "Source file does not exist."
fi

#unzip file
zip_file="/home/$db/public_html/mautic.zip"

# Destination directory for extracted files
destination="/home/$db/public_html/"

# Check if the ZIP file exists
if [ -f "$zip_file" ]; then
    # Unzip the file
    unzip "$zip_file" -d "$destination"
    echo "File successfully unzipped!"
else
    echo "ZIP file does not exist."
fi

chown $db:$db -R /home/$db/public_html/*

####database
MYSQL_USER="root"
DATABASE_NAME="$db"
DATABASE_USER="mautic"
file="/home/$db/public_html/app/config/local.php"

sed -i "s/'db_name' => 'swdlv'/'db_name' => '$db'/" "$file"
sed -i "s/'db_user' => 'swdlv'/'db_user' => '$db'/" "$file"
sed -i "s/'mailer_from_email' => 'postal@swdlv.com'/'mailer_from_email' => 'postal@$domain'/" "$file"
sed -i "s/'mailer_host' => 'postal.swdlv.com'/'mailer_host' => 'postal.$domain'/" "$file"
sed -i "s/'mailer_user' => 'postal@swdlv.com'/'mailer_user' => 'postal@$domain'/" "$file"
sed -i "s/swdlv.com'/$domain'/" "$file"


git clone https://github.com/quick003/ritik.git

 #Create the user
mysql -u $MYSQL_USER -e "CREATE USER '$DATABASE_USER'@'localhost' IDENTIFIED BY 'pradeep';"

# Grant privileges 	to the user on the database
mysql -u $MYSQL_USER -e "GRANT ALL PRIVILEGES ON $DATABASE_NAME.* TO '$DATABASE_USER'@'localhost';"

# Flush privileges
mysql -u $MYSQL_USER -e "FLUSH PRIVILEGES;"

mysql -D $db < /root/ritik/mautic_postal.sql

##### cronjob

echo "$(crontab -l)"$'\n'"0,3,6,9,12,15,18,21,24,27,30,33,36,39,42,45,48,51,54,57 * * * * php /home/$db/public_html/bin/console mautic:segments:update > /var/log/cron.pipe 2>&1 --env=prod" | crontab -
echo "$(crontab -l)"$'\n'"1,4,7,10,13,16,19,22,25,28,31,34,37,40,43,46,49,52,55,58 * * * * php /home/$db/public_html/bin/console mautic:campaigns:update > /var/log/cron.pipe 2>&1 --env=prod" | crontab -
echo "$(crontab -l)"$'\n'"*2,5,8,11,14,17,20,23,26,29,32,35,38,41,44,47,50,53,56 * * * * php /home/$db/public_html/bin/console mautic:campaigns:trigger > /var/log/cron.pipe 2>&1 --env=prod" | crontab -
echo "$(crontab -l)"$'\n'"2,5,8,11,14,17,20,23,26,29,32,35,38,41,44,47,50,53,56,60 * * * * php /home/$db/public_html/bin/console mautic:messages:send > /var/log/cron.pipe 2>&1 --env=prod" | crontab -
echo "$(crontab -l)"$'\n'"2,5,8,11,14,17,20,23,26,29,32,35,38,41,44,47,50,53,56,60 * * * * php /home/$db/public_html/bin/console mautic:emails:send > /var/log/cron.pipe 2>&1 --env=prod" | crontab -
echo "$(crontab -l)"$'\n'"* * * * * php /home/$db/public_htmlphp mautic:broadcasts:send > /var/log/cron.pipe 2>&1 --env=prod" | crontab -
echo "Cron job added successfully."


----------------------------------------------------


sudo apt install ca-certificates curl gnupg lsb-release -y

sudo mkdir -m 0755 -p /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo   "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update -y

sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

curl -SL https://github.com/docker/compose/releases/download/v2.16.0/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose

sudo chmod +x /usr/local/bin/docker-compose

sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

apt install git curl jq -y

git clone https://postalserver.io/start/install /opt/postal/install

sudo ln -s /opt/postal/install/bin/postal /usr/bin/postal

docker run -d \
   --name postal-mariadb \
   -p 127.0.0.1:3306:3306 \
   --restart always \
   -e MARIADB_DATABASE=postal \
   -e MARIADB_ROOT_PASSWORD=postal \
   mariadb

docker run -d \
   --name postal-rabbitmq \
   -p 127.0.0.1:5672:5672 \
   --restart always \
   -e RABBITMQ_DEFAULT_USER=postal \
   -e RABBITMQ_DEFAULT_PASS=postal \
   -e RABBITMQ_DEFAULT_VHOST=postal \
   rabbitmq:3.8

postal bootstrap postal.$domain

sed -i "s/- mx.postal.example.com/- postal.$domain/" "/opt/postal/config/postal.yml"
sed -i "s/smtp_server_hostname: postal.example.com/smtp_server_hostname: postal.$domain/" "/opt/postal/config/postal.yml"
sed -i "s/spf_include: spf.postal.example.com/spf_include: spf.postal.$domain/" "/opt/postal/config/postal.yml"
sed -i "s/return_path: rp.postal.example.com/return_path: rp.postal.$domain/" "/opt/postal/config/postal.yml"
sed -i "s/route_domain: routes.postal.example.com/route_domain: routes.postal.$domain/" "/opt/postal/config/postal.yml"
sed -i "s/track_domain: track.postal.example.com/track_domain: track.postal.$domain/" "/opt/postal/config/postal.yml"
sed -i "s/from_address: postal.$domain/from_address: postal@$domain/" "/opt/postal/config/postal.yml"

postal initialize

postal make-user

postal start

docker run -d \
   --name postal-caddy \
   --restart always \
   --network host \
   -v /opt/postal/config/Caddyfile:/etc/caddy/Caddyfile \
   -v /opt/postal/caddy-data:/data \
   caddy

postal upgrade

echo "Your Postal SMTP Server link is https://postal.$domain or http://$domain:5000"
echo "Your Postal SMTP Server credential is which you entered"
echo "follow https://inguide.in/simplest-way-to-configure-postal-create-smtp-install-ssl/ for creation of organization and server"
