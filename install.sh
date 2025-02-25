#!/bin/bash
# DREADNOUGHT Installer – Versão CLI com configuração local de DNS

# --- Verifica e instala utilitários necessários ---
if ! command -v figlet &> /dev/null; then
    sudo apt-get update && sudo apt-get install -y figlet
fi

# --- Exibe o banner "DREADNOUGHT" ---
banner=$(figlet -f slant DREADNOUGHT)
banner_colored=$(echo -e "\x1b[34;47;1;3m${banner}\x1b[0m")
echo "$banner_colored"
echo -e "\nPressione [ENTER] para iniciar..."
read

# --- Função para exibir progresso ---
update_progress() {
    echo "[$1%] $2"
}

# --- Função para executar comandos de forma silenciosa ---
silent() {
    "$@" >/dev/null 2>&1
}

###########################################
# DETECÇÃO DO IP ATUAL E CONFIGURAÇÃO DO ARQUIVO HOSTS
###########################################
get_current_ip() {
    ip route get 1.2.3.4 | awk '{print $7}' | head -1
}
CURRENT_IP=$(get_current_ip)
echo "IP atual detectado: $CURRENT_IP"

update_hosts_file() {
    local entry="${CURRENT_IP} portainer.local chatwoot.local evolutionapi.local typebot.local"
    echo "Realizando backup do arquivo /etc/hosts..."
    sudo cp /etc/hosts /etc/hosts.bak
    echo "Removendo entradas antigas..."
    sudo sed -i '/portainer\.local/d' /etc/hosts
    sudo sed -i '/chatwoot\.local/d' /etc/hosts
    sudo sed -i '/evolutionapi\.local/d' /etc/hosts
    sudo sed -i '/typebot\.local/d' /etc/hosts
    echo "Adicionando nova entrada: $entry"
    echo "$entry" | sudo tee -a /etc/hosts >/dev/null
    echo "Arquivo /etc/hosts atualizado."
}
update_hosts_file

###########################################
# CONFIGURAÇÃO AUTOMÁTICA DOS AMBIENTES DA EVOLUTION API
###########################################
SERVER_PORT=3003
SERVER_TYPE=http
SERVER_URL="http://$CURRENT_IP:$SERVER_PORT"
AUTHENTICATION_API_KEY=viver3378

echo "Configurando Evolution API com:"
echo "  SERVER_PORT: $SERVER_PORT"
echo "  SERVER_TYPE: $SERVER_TYPE"
echo "  SERVER_URL: $SERVER_URL"
echo "  AUTHENTICATION_API_KEY: $AUTHENTICATION_API_KEY"

###########################################
# LIMPEZA INICIAL: PARAR E REMOVER CONTAINERS E VOLUMES
###########################################
clean_docker() {
    update_progress 0 "Parando todos os containers..."
    containers=$(sudo docker ps -q)
    if [ -n "$containers" ]; then
        silent sudo docker stop $containers
    fi

    update_progress 5 "Removendo todos os containers..."
    all_containers=$(sudo docker ps -aq)
    if [ -n "$all_containers" ]; then
        silent sudo docker rm $all_containers
    fi

    update_progress 10 "Removendo todos os volumes..."
    volumes=$(sudo docker volume ls -q)
    if [ -n "$volumes" ]; then
        silent sudo docker volume rm $volumes
    fi

    update_progress 15 "Limpeza inicial concluída."
    sleep 1
}
clean_docker

###########################################
# SCRIPT #1 – Evolution API, Typebot, Minio, etc.
###########################################
update_progress 20 "Verificando Docker..."
install_update_docker() {
    if ! command -v docker &> /dev/null; then
        silent sudo apt-get update
        silent sudo apt-get install -y docker.io
    else
        current_version=$(docker --version | awk -F '[ ,]+' '{ print $3 }')
        latest_version=$(curl -s https://api.github.com/repos/docker/docker-ce/releases/latest | grep 'tag_name' | cut -d\" -f4 | sed 's/v//')
        if [ "$current_version" != "$latest_version" ]; then
            silent sudo apt-get update
            silent sudo apt-get install -y docker-ce docker-ce-cli containerd.io
        fi
    fi
}
install_update_docker

update_progress 30 "Instalando Docker Compose..."
install_docker_compose() {
    if ! command -v docker-compose &> /dev/null; then
        silent sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        silent sudo chmod +x /usr/local/bin/docker-compose
        silent sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
    fi
}
install_docker_compose

update_progress 35 "Instalando Portainer..."
install_portainer() {
    if [ "$(docker ps -aq -f name=portainer)" ]; then
        :
    else
        silent docker volume create portainer_data
        silent docker run -d -p 9000:9000 --name portainer --restart=always \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -v portainer_data:/data \
            portainer/portainer-ce
    fi
}
install_portainer

update_progress 40 "Configuração inicial concluída."
sleep 1

apply_migrations() {
    silent docker exec -it evolution_api sh -c "rm -rf ./prisma/migrations && cp -r ./prisma/postgresql-migrations ./prisma/migrations && npx prisma migrate deploy --schema ./prisma/postgresql-schema.prisma"
    if [ $? -ne 0 ]; then
        update_progress 0 "Erro ao aplicar migrações."
        exit 1
    fi
}

update_progress 45 "Preparando serviços do Script #1..."
cat <<EOF > docker-compose.yml
version: '3.9'

services:
  evolutionapi_postgres:
    image: postgres:latest
    container_name: evolutionapi_postgres
    restart: always
    environment:
      POSTGRES_USER: evolutionapi
      POSTGRES_PASSWORD: "minhaSenhaForte123!"
      POSTGRES_DB: evolutionapi_db
    volumes:
      - evolutionapi_postgres_data:/var/lib/postgresql/data
    ports:
      - "5435:5432"

  evolutionapi_redis:
    image: redis:latest
    container_name: evolutionapi_redis
    restart: always
    ports:
      - "6374:6379"

  evolution-api:
    container_name: evolution_api
    image: atendai/evolution-api:v2.1.1
    restart: always
    ports:
      - "3003:3003"
    environment:
      DATABASE_ENABLED: "true"
      DATABASE_PROVIDER: "postgresql"
      DATABASE_CONNECTION_URI: "postgresql://evolutionapi:minhaSenhaForte123!@evolutionapi_postgres:5432/evolutionapi_db?schema=public"
      DATABASE_CONNECTION_CLIENT_NAME: "evolution_exchange"
      DATABASE_SAVE_DATA_INSTANCE: "true"
      DATABASE_SAVE_DATA_NEW_MESSAGE: "true"
      DATABASE_SAVE_MESSAGE_UPDATE: "true"
      DATABASE_SAVE_DATA_CONTACTS: "true"
      DATABASE_SAVE_DATA_CHATS: "true"
      DATABASE_SAVE_DATA_LABELS: "true"
      DATABASE_SAVE_DATA_HISTORIC: "true"
      CACHE_REDIS_ENABLED: "true"
      CACHE_REDIS_URI: "redis://evolutionapi_redis:6379/6"
      CACHE_REDIS_PREFIX_KEY: "evolution"
      CACHE_REDIS_SAVE_INSTANCES: "true"
      CACHE_LOCAL_ENABLED: "true"
      AUTHENTICATION_API_KEY: "$AUTHENTICATION_API_KEY"
      CHATWOOT_ENABLED: "true"
      TYPEBOT_ENABLED: "true"
      SERVER_TYPE: "$SERVER_TYPE"
      SERVER_PORT: "$SERVER_PORT"
      SERVER_URL: "$SERVER_URL"
    volumes:
      - evolution_instances:/evolution/instances

  typebot-builder:
    image: baptistearno/typebot-builder:latest
    container_name: typebot_builder
    restart: always
    ports:
      - "3004:3000"
    environment:
      DATABASE_URL: "postgres://evolutionapi:minhaSenhaForte123!@evolutionapi_postgres:5432/evolutionapi_db"
      ENCRYPTION_SECRET: "I7Ii+VDU8oi8FYEwM/ZUvMTboC7Ix0wG"
      SMTP_USERNAME: "naorespondacolviver@gmail.com"
      SMTP_PASSWORD: "vlaiwkzckfvdwxvp"
      SMTP_HOST: "smtp.gmail.com"
      SMTP_PORT: "587"
      NEXTAUTH_URL: "https://builder.colviver.site"
      NEXT_PUBLIC_VIEWER_URL: "https://viewer.colviver.site"
      ADMIN_EMAIL: "aaraujo.douglas@gmail.com"
      NEXT_PUBLIC_SMTP_FROM: "naorespondacolviver@gmail.com"
      SMTP_SECURE: "true"

  typebot-viewer:
    image: baptistearno/typebot-viewer:latest
    container_name: typebot_viewer
    restart: always
    ports:
      - "3005:3000"
    environment:
      DATABASE_URL: "postgres://evolutionapi:minhaSenhaForte123!@evolutionapi_postgres:5432/evolutionapi_db"
      NEXTAUTH_URL: "https://builder.colviver.site"
      NEXT_PUBLIC_VIEWER_URL: "http://viewer.colviver.site"

  minio:
    image: minio/minio
    container_name: minio
    command: server /data
    ports:
      - "9001:9000"
    environment:
      MINIO_ROOT_USER: "minio"
      MINIO_ROOT_PASSWORD: "minio123"
    volumes:
      - s3-data:/data

  createbuckets:
    image: minio/mc
    depends_on:
      - minio
    entrypoint: >
      /bin/sh -c "
      sleep 10;
      /usr/bin/mc config host add minio http://minio:9001 minio minio123;
      /usr/bin/mc mb minio/typebot;
      /usr/bin/mc anonymous set public minio/typebot/public;
      exit 0;
      "

volumes:
  evolutionapi_postgres_data:
  evolution_instances:
  s3-data:
EOF

update_progress 50 "Subindo containers do Script #1..."
silent sudo docker-compose -f docker-compose.yml up -d
update_progress 55 "Aguardando containers..."
sleep 30
silent apply_migrations
update_progress 60 "Migrações concluídas."
silent rm -f docker-compose.yml
update_progress 65 "Arquivo temporário removido."
sleep 1

###########################################
# SCRIPT #2 – Chatwoot
###########################################
update_progress 70 "Configurando Chatwoot..."
install_docker() {
    silent sudo apt-get update
    silent sudo apt-get upgrade -y
    silent curl -fsSL https://get.docker.com -o get-docker.sh
    silent sudo sh get-docker.sh
    silent sudo apt install -y docker-compose-plugin
}
check_docker_installed() {
    if command -v docker &> /dev/null; then
        current_version=$(docker --version | awk -F '[ ,]+' '{ print $3 }')
        required_version="20.10.10"
        if [ "$(printf '%s\n' "$required_version" "$current_version" | sort -V | head -n1)" != "$required_version" ]; then
            install_docker
        fi
    else
        install_docker
    fi
}
download_files() {
    silent wget -O .env https://raw.githubusercontent.com/chatwoot/chatwoot/develop/.env.example
    silent wget -O docker-compose-chatwoot.yaml https://raw.githubusercontent.com/chatwoot/chatwoot/develop/docker-compose.production.yaml
}
configure_env() {
    cat <<'EOF' > .env
# Chatwoot Environment Variables

SECRET_KEY_BASE=replace_with_lengthy_secure_hex
FRONTEND_URL=http://0.0.0.0:3000
ASSET_CDN_HOST=
FORCE_SSL=false
ENABLE_ACCOUNT_SIGNUP=false
REDIS_URL=redis://chatwoot_redis:6379
REDIS_PASSWORD=
REDIS_SENTINELS=
REDIS_SENTINEL_MASTER_NAME=
POSTGRES_HOST=chatwoot_postgres
POSTGRES_USERNAME=postgres
POSTGRES_PASSWORD=your_super_secret_password
RAILS_ENV=development
RAILS_MAX_THREADS=5
MAILER_SENDER_EMAIL=Chatwoot <accounts@chatwoot.com>
SMTP_DOMAIN=chatwoot.com
SMTP_ADDRESS=
SMTP_PORT=1025
SMTP_USERNAME=
SMTP_PASSWORD=
SMTP_AUTHENTICATION=
SMTP_ENABLE_STARTTLS_AUTO=true
SMTP_OPENSSL_VERIFY_MODE=peer
MAILER_INBOUND_EMAIL_DOMAIN=
RAILS_INBOUND_EMAIL_SERVICE=
RAILS_INBOUND_EMAIL_PASSWORD=
MAILGUN_INGRESS_SIGNING_KEY=
MANDRILL_INGRESS_API_KEY=
ACTIVE_STORAGE_SERVICE=local
S3_BUCKET_NAME=
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_REGION=
RAILS_LOG_TO_STDOUT=true
LOG_LEVEL=info
LOG_SIZE=500
FB_VERIFY_TOKEN=
FB_APP_SECRET=
FB_APP_ID=
IG_VERIFY_TOKEN=
TWITTER_APP_ID=
TWITTER_CONSUMER_KEY=
TWITTER_CONSUMER_SECRET=
TWITTER_ENVIRONMENT=
SLACK_CLIENT_ID=
SLACK_CLIENT_SECRET=
GOOGLE_OAUTH_CLIENT_ID=
GOOGLE_OAUTH_CLIENT_SECRET=
GOOGLE_OAUTH_CALLBACK_URL=
IOS_APP_ID=L7YLMN4634.com.chatwoot.app
ANDROID_BUNDLE_ID=com.chatwoot.app
ANDROID_SHA256_CERT_FINGERPRINT=AC:73:8E:DE:EB:56:EA:CC:10:87:02:A7:65:37:7B:38:D4:5D:D4:53:F8:3B:FB:D3:C6:28:64:1D:AA:08:1E:D8
ENABLE_PUSH_RELAY_SERVER=true
STRIPE_SECRET_KEY=
STRIPE_WEBHOOK_SECRET=
DIRECT_UPLOADS_ENABLED=
AZURE_APP_ID=
AZURE_APP_SECRET=
CHATWOOT_IMPORT_DATABASE_CONNECTION_URI=postgres://chatwoot:chatwoot@chatwoot_postgres:5432/chatwoot_import_db
CHATWOOT_IMPORT_PLACEHOLDER_MEDIA_MESSAGE=true
EOF
}
configure_docker_compose() {
    cat <<'EOF' > docker-compose-chatwoot.yaml
version: '3'

services:
  base: &base
    image: chatwoot/chatwoot:latest
    env_file: .env
    volumes:
      - /data/chatwoot/storage:/app/storage

  rails:
    <<: *base
    depends_on:
      - postgres
      - redis
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
      - RAILS_ENV=production
      - INSTALLATION_ENV=docker
    entrypoint: docker/entrypoints/rails.sh
    command: ["bundle", "exec", "rails", "s", "-p", "3000", "-b", "0.0.0.0"]
    restart: always

  sidekiq:
    <<: *base
    depends_on:
      - postgres
      - redis
    environment:
      - NODE_ENV=production
      - RAILS_ENV=production
      - INSTALLATION_ENV=docker
    command: ["bundle", "exec", "sidekiq", "-C", "config/sidekiq.yml"]
    restart: always

  postgres:
    image: pgvector/pgvector:pg16
    container_name: chatwoot_postgres
    restart: always
    ports:
      - "5436:5432"
    volumes:
      - chatwoot_postgres_data:/var/lib/postgresql/data
    environment:
      - POSTGRES_DB=chatwoot
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=your_super_secret_password

  redis:
    image: redis:alpine
    container_name: chatwoot_redis
    restart: always
    command: ["sh", "-c", "redis-server --requirepass '\$REDIS_PASSWORD'"]
    env_file: .env
    volumes:
      - chatwoot_redis_data:/data
    ports:
      - "6380:6379"

volumes:
  chatwoot_postgres_data:
  chatwoot_redis_data:
EOF
}
update_progress 55 "Verificando Docker para Chatwoot..."
check_docker_installed
update_progress 60 "Baixando arquivos para Chatwoot..."
download_files
update_progress 65 "Configurando ambiente Chatwoot..."
configure_env
update_progress 70 "Configurando docker-compose para Chatwoot..."
configure_docker_compose
update_progress 75 "Preparando banco de dados do Chatwoot..."
silent docker-compose -f docker-compose-chatwoot.yaml run --rm rails bundle exec rails db:chatwoot_prepare
update_progress 80 "Iniciando Chatwoot..."
silent docker-compose -f docker-compose-chatwoot.yaml up -d
update_progress 90 "Limpando arquivos temporários..."
silent rm -f docker-compose-chatwoot.yaml
update_progress 100 "Instalação concluída."
sleep 1

echo -e "\nInstalação DREADNOUGHT concluída com sucesso!"

###########################################
# CONFIGURAÇÃO DO WETTY (via CLI)
###########################################
read -p "Digite o IP do host SSH [$CURRENT_IP]: " WETTY_SSH_HOST
WETTY_SSH_HOST=${WETTY_SSH_HOST:-$CURRENT_IP}

read -p "Digite a porta web do Wetty [3000]: " WETTY_WEB_PORT
WETTY_WEB_PORT=${WETTY_WEB_PORT:-3000}

silent docker rm -f wetty &> /dev/null
silent docker run -d \
    -p ${WETTY_WEB_PORT}:3000 \
    --name wetty \
    --restart unless-stopped \
    wettyoss/wetty:latest -- --ssh-host ${WETTY_SSH_HOST}

echo -e "\nWetty instalado com sucesso!"
echo "Acesse: http://$(curl -s ifconfig.me):${WETTY_WEB_PORT} ou localmente: http://localhost:${WETTY_WEB_PORT}"
echo -e "No login use:\nHost: ${WETTY_SSH_HOST}\nSeu usuário e senha do SSH"
clear
