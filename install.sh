#!/bin/bash

set -e  # Para o script caso ocorra algum erro

# Atualiza o sistema
echo "Atualizando o sistema..."
sudo apt update && sudo apt upgrade -y

# Instala dependências
sudo apt install -y curl wget

# Instala Docker
echo "Instalando Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo apt install -y docker-compose-plugin

# Cria diretório do projeto
mkdir -p ~/docker-setup && cd ~/docker-setup

# Baixa os arquivos do Chatwoot
echo "Baixando Chatwoot..."
wget -O .env https://raw.githubusercontent.com/chatwoot/chatwoot/develop/.env.example
wget -O docker-compose.yml https://raw.githubusercontent.com/chatwoot/chatwoot/develop/docker-compose.production.yaml

# Ajusta permissões
echo "Ajustando permissões do Docker..."
sudo usermod -aG docker $USER

# Cria Docker Compose para Typebot, EvolutionAPI, Portainer e Wetty
cat <<EOF > docker-compose.yml
version: '3.9'

services:
  postgres:
    image: postgres:latest
    container_name: postgres
    restart: always
    environment:
      POSTGRES_USER: evolutionapi
      POSTGRES_PASSWORD: minhaSenhaForte123!
      POSTGRES_DB: evolutionapi_db
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5435:5432"

  redis:
    image: redis:latest
    container_name: redis
    restart: always
    ports:
      - "6374:6379"

  evolution-api:
    container_name: evolution_api
    image: atendai/evolution-api:v2.1.1
    restart: always
    ports:
      - "3003:8080"
    environment:
      DATABASE_CONNECTION_URI: postgresql://evolutionapi:minhaSenhaForte123!@postgres:5432/evolutionapi_db?schema=public
      CACHE_REDIS_URI: redis://redis:6379/6
      AUTHENTICATION_API_KEY: viver3378
      CHATWOOT_ENABLED: true
      TYPEBOT_ENABLED: true
    volumes:
      - evolution_instances:/evolution/instances

  typebot-builder:
    image: baptistearno/typebot-builder:latest
    container_name: typebot_builder
    restart: always
    ports:
      - "3004:3000"
    environment:
      DATABASE_URL: postgres://evolutionapi:minhaSenhaForte123!@postgres:5432/evolutionapi_db
      ENCRYPTION_SECRET: I7Ii+VDU8oi8FYEwM/ZUvMTboC7Ix0wG

  typebot-viewer:
    image: baptistearno/typebot-viewer:latest
    container_name: typebot_viewer
    restart: always
    ports:
      - "3005:3000"
    environment:
      DATABASE_URL: postgres://evolutionapi:minhaSenhaForte123!@postgres:5432/evolutionapi_db

  minio:
    image: minio/minio
    container_name: minio
    command: server /data
    ports:
      - '9001:9000'
    environment:
      MINIO_ROOT_USER: minio
      MINIO_ROOT_PASSWORD: minio123
    volumes:
      - s3-data:/data

  portainer:
    image: portainer/portainer-ce:lts
    container_name: portainer
    restart: always
    ports:
      - "8000:8000"
      - "9443:9443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data

  wetty:
    image: mydigitalwalk/wetty:latest
    container_name: wetty
    restart: always
    environment:
      SSHHOST: "localhost"
      SSHPORT: 22
      NODE_ENV: "production"
    volumes:
      - wetty-data:/home/node

  wetty-ssh:
    image: mydigitalwalk/wetty-ssh:latest
    container_name: wetty-ssh
    restart: always
    environment:
      SSHHOST: "localhost"
    volumes:
      - wetty_ssh-data:/data

volumes:
  postgres_data:
  evolution_instances:
  s3-data:
  portainer_data:
  wetty-data:
  wetty_ssh-data:
EOF

# Prepara banco do Chatwoot
echo "Preparando banco do Chatwoot..."


# Sobe todos os containers
echo "Iniciando containers..."
docker compose up -d

echo "Instalação finalizada!"
