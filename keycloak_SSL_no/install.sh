#!/bin/bash

#Functions
script_exit() {
    echo Incorrect input
    exit
}

program_exists() {
    type "$1" > /dev/null 2>&1
}

put_hostname() {
    sed -i '/KC_HOSTNAME/d' .env
    read -p "Enter your domain [$1]: " -e domain
    case "$domain" in
        ""  )
            echo KC_HOSTNAME=$1 >> .env
        ;;
        *   )
            echo KC_HOSTNAME=$domain >> .env
            KC_HOSTNAME=$domain
        ;;
    esac
}

email_dialog() {
    read -p "Enter your email [$1]: " -e mail
    case "$mail" in
        ""  )
            if [ ! "$1" ]; then
                script_exit
            fi
        ;;
        *   )
            sed -i '/EMAIL/d' .env
            echo EMAIL=$mail >> .env
            EMAIL=$mail
        ;;
    esac
}

check_email() {
    check_mail=$(echo "$1" | awk '/@/{print $0}')
    case "$check_mail" in
        ""  )   script_exit;;
        *   )   echo;;
    esac
}

check_domain() {
    case "$1" in
        ""  )
            echo There is no A-record for the domain
            script_exit
        ;;
        *   )
            echo Please check the A-records
            echo $1
        ;;
    esac
}

restore_config() {
echo
echo Restore config
cat  <<EOF >.env
POSTGRES_DB=keycloak_db
POSTGRES_USER=keycloak_db_user
POSTGRES_PASSWORD=keycloak_db_user_password
KC_HOSTNAME=
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=
EMAIL=
EOF
exit
}

create_pass() {
    sed -i '/KEYCLOAK_ADMIN_PASSWORD/d' .env
    echo KEYCLOAK_ADMIN_PASSWORD=$(tr -dc 'A-Za-z0-9!?%=' < /dev/urandom | head -c 16) >> .env
}


# Start script
source .env

# Get docker
if program_exists "docker"; then
    echo "Docker is installed."
    echo
else
    echo "Docker is not installed. Installation..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
fi

# Get domain
case "$KC_HOSTNAME" in
    ""  )
        KC_HOSTNAME=$(curl -s 2ip.ru).sslip.io
        put_hostname $KC_HOSTNAME
    ;;
    *   )
        put_hostname $KC_HOSTNAME
    ;;
esac

# Get email
email_dialog $EMAIL
source .env
check_email $EMAIL

# Check domain
a_record=$(dig A $KC_HOSTNAME +short)
check_domain $a_record
echo
echo Please make sure that ports 80/tcp and 443/tcp are open.

# Get config
echo
echo Check your config:
cat .env
echo
read -p "Is config correct? [y\N]: " -e choice
case "$choice" in
    "" | "N" | "n"  )   restore_config;;
    "Y" | "y"       )   echo;;
    *               )   script_exit;;
esac

# Get generate password
case "$KEYCLOAK_ADMIN_PASSWORD" in 
    ""  )   create_pass;;
    *   )   echo;;
esac

# Phase 1
docker compose -f ./docker-compose-initiate.yaml up -d nginx
docker compose -f ./docker-compose-initiate.yaml up certbot
docker compose -f ./docker-compose-initiate.yaml down

# Some configurations for let's encrypt
curl -L --create-dirs -o letsencrypt/options-ssl-nginx.conf https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf
openssl dhparam -out letsencrypt/ssl-dhparams.pem 2048

# Phase 2
cat <<EOF >./crontab
# m h  dom mon dow   command
0 0 1 * * $(pwd)/cron_job.sh

EOF
crontab ./crontab

# Start Keycloak
docker compose -f ./docker-compose.yaml up -d

# Get final config
echo Your configuration:
cat .env
source .env
echo

# Open keycloak
echo Keycloak is will be available in a minute at https://$KC_HOSTNAME
echo Username: $KEYCLOAK_ADMIN
echo Password: $KEYCLOAK_ADMIN_PASSWORD