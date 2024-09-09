#!/bin/bash

# Functions
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

generate_cert() {
    sed -i '/SSL_CERTIFICATE/d' .env
    sed -i '/SSL_CERTIFICATE_KEY/d' .env
    mkdir certs
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout certs/nginx-selfsigned.key -out certs/nginx-selfsigned.crt -subj "/C=RU/ST=Moscow/L=Moscow/O=TestOrg/OU=IT/CN=$KC_HOSTNAME/emailAddress=it@$KC_HOSTNAME"
    echo SSL_CERTIFICATE=./certs/nginx-selfsigned.crt >> .env
    echo SSL_CERTIFICATE_KEY=./certs/nginx-selfsigned.key >> .env
}

cert_dialog() {
    read -p "Enter path to your certificate [$1]: " -e path_cert
    case "$path_cert" in
        ""  )
            if [ ! "$1" ]; then
                script_exit
            fi
        ;;
        *   )
            sed -i '/SSL_CERTIFICATE/d' .env
            echo SSL_CERTIFICATE=$path_cert >> .env
        ;;
    esac

    read -p "Enter path to your private key [$2]: " -e path_privkey
    case "$path_privkey" in
        ""  )
            if [ ! "$2" ]; then
                script_exit
            fi
        ;;
        *   )
            sed -i '/SSL_CERTIFICATE_KEY/d' .env
            echo SSL_CERTIFICATE_KEY=$path_privkey >> .env
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
    SSL_CERTIFICATE=
    SSL_CERTIFICATE_KEY=
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

# Get ssl_cetrificate
read -p "Do you have certificate [y\N]: " -e check_cert
case "$check_cert" in
    "" | "N" | "n"  )   generate_cert;;
    "Y" | "y"       )   cert_dialog $SSL_CERTIFICATE $SSL_CERTIFICATE_KEY;;
    *               )   script_exit;;
esac

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