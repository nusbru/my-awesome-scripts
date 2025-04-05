#!/bin/bash

# Verifica se o nome do projeto foi fornecido
if [ -z "$1" ]; then
    echo "Informe o nome do projeto: $0 <nome-do-projeto>"
    exit 1
fi

# Define variáveis
PROJECT_NAME=$1
DATABASE_NAME=$2
BASE_DIR=$(pwd)/$PROJECT_NAME
SRC_DIR=$BASE_DIR/src
TEST_DIR=$BASE_DIR/test
API_PROJECT="$SRC_DIR/$PROJECT_NAME.API"
TEST_PROJECT="$TEST_DIR/$PROJECT_NAME.API.Tests"
DEVCONTAINER_DIR=$BASE_DIR/.devcontainer

# Cria estrutura de diretórios
echo "Criando diretórios..."
mkdir -p $SRC_DIR
mkdir -p $TEST_DIR

# Inicia repositório git no diretório base do projeto
echo "Iniciando repositório git no diretório $BASE_DIR..."
git init $BASE_DIR

# Cria o arquivo de gitignore
echo "Criando arquivo .gitignore..."
wget https://www.toptal.com/developers/gitignore/api/csharp,visualstudio,visualstudiocode,openframeworks+visualstudio,dotnetcore,rider -O $BASE_DIR/.gitignore

# Cria a solução
echo "Criando solução .NET..."
dotnet new sln -o $BASE_DIR -n $PROJECT_NAME

# Cria o projeto Minimal API
echo "Criando projeto Minimal API..."
dotnet new web -o $API_PROJECT -n "$PROJECT_NAME.API"

# Adiciona dependências ao projeto Minimal API
echo "Adicionando dependências ao projeto Minimal API..."
dotnet add $API_PROJECT package FluentValidation
dotnet add $API_PROJECT package MediatR

# Adiciona o projeto API à solução
echo "Adicionando projeto Minimal API à solução..."
dotnet sln $BASE_DIR/$PROJECT_NAME.sln add $API_PROJECT

# Cria o projeto de testes
echo "Criando projeto de testes..."
dotnet new xunit -o $TEST_PROJECT -n "$PROJECT_NAME.API.Tests"

# Adiciona dependências ao projeto de testes
echo "Adicionando dependências ao projeto de testes..."
dotnet add $TEST_PROJECT package FluentAssertions
dotnet add $TEST_PROJECT package NSubstitute
dotnet add $TEST_PROJECT package coverlet.collector

# Adiciona referência ao projeto API
echo "Adicionando referência ao projeto API no projeto de testes..."
dotnet add $TEST_PROJECT reference $API_PROJECT

# Adiciona o projeto de testes à solução
echo "Adicionando projeto de testes à solução..."
dotnet sln $BASE_DIR/$PROJECT_NAME.sln add $TEST_PROJECT

# Adiciona o Dockerfile na raiz do projeto
echo "Criando Dockerfile na raiz do projeto..."
cat <<EOL > $BASE_DIR/Dockerfile
# Etapa 1: Build
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /app

# Copia a solução e restaura as dependências
COPY ./*.sln ./
COPY ./src/$PROJECT_NAME.API/*.csproj ./src/$PROJECT_NAME.API/
RUN dotnet restore ./src/$PROJECT_NAME.API/$PROJECT_NAME.API.csproj

# Copia o restante do código e faz o build
COPY ./src/$PROJECT_NAME.API/. ./src/$PROJECT_NAME.API/
WORKDIR /app/src/$PROJECT_NAME.API
RUN dotnet publish -c Release -o /publish

# Etapa 2: Runtime
FROM mcr.microsoft.com/dotnet/aspnet:9.0
WORKDIR /app
COPY --from=build /publish .
ENTRYPOINT ["dotnet", "$PROJECT_NAME.API.dll"]
EOL

mkdir $DEVCONTAINER_DIR

# Cria Makefile
echo "Criando Makefile..."
cat <<EOL > "$BASE_DIR/Makefile"
# Tarefas
.PHONY: all build run test clean add-migration update-database remove-migration list-migrations

all: build

build:
	dotnet build "$PROJECT_NAME.sln"

run:
	dotnet run --project "$API_PROJECT"

test:
	dotnet test --project "$TEST_PROJECT"

clean:
	dotnet clean "$PROJECT_NAME.sln"

# Entity Framework Migrations
add-migration:
	dotnet ef migrations add $(name) --project "$API_PROJECT"

update-database:
	dotnet ef database update --project "$API_PROJECT"

remove-migration:
	dotnet ef migrations remove --project "$API_PROJECT"

list-migrations:
	dotnet ef migrations list --project "$API_PROJECT"
EOL

lowercase_project_name="${PROJECT_NAME,,}"

if [ -n "$DATABASE_NAME" ]; then
    echo "Criando postgres database service"
    if [ "$DATABASE_NAME" == "postgres" ]; then
        echo "Criando dockerfile com POSTGRES Database        "
        # Cria o docker-compose.yml
        cat <<EOF > $BASE_DIR/docker-compose.yml
version: '3.8'

services:
  app:
    build:
      context: .  # Diretório atual onde está seu Dockerfile
    ports:
      - "80:80"
    depends_on:
      - db

  db:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_DB: \${POSTGRES_DB}
      POSTGRES_USER: \${POSTGRES_USER}
      POSTGRES_PASSWORD_FILE: /run/secrets/postgres_password
    env_file:
      - .env
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - \${INIT_SCRIPTS_PATH:-./init-scripts}:/docker-entrypoint-initdb.d
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5
    secrets:
      - postgres_password
    deploy:
      resources:
        limits:
          cpus: \${PG_CPU_LIMIT:-1}
          memory: \${PG_MEMORY_LIMIT:-1G}

volumes:
  postgres_data:
    name: \${COMPOSE_PROJECT_NAME}_postgres_data

secrets:
  postgres_password:
    file: ./secrets/postgres_password.txt

networks: 
  "${lowercase_project_name}-network":
    driver: bridge 
EOF
        cat <<EOF > $BASE_DIR/.env
#PostgreSQL
POSTGRES_DB=${PROJECT_NAME}db
POSTGRES_USER=${PROJECT_NAME}_usr
POSTGRES_INITDB_ARGS="--data-checksums --encoding=UTF8 --locale=pt_BR.UTF-8"
POSTGRES_MAX_CONNECTIONS=100
POSTGRES_SHARED_BUFFERS=128MB

COMPOSE_PROJECT_NAME="${PROJECT_NAME}"
TZ=America/Sao_Paulo

# Configurações de recursos
PG_CPU_LIMIT=1
PG_MEMORY_LIMIT=1G

# Paths para volumes e scripts (opcional)
INIT_SCRIPTS_PATH=./init-scripts
POSTGRES_DATA_PATH=./postgres-data

# Outros parâmetros
PGDATA=/var/lib/postgresql/data
POSTGRES_MULTIPLE_DATABASES=prod,test,dev
EOF
    mkdir -p $BASE_DIR/.secrets
    echo "$(openssl rand -base64 16)" > $BASE_DIR/.secrets/postgres_password.txt
    chmod 600 $BASE_DIR/.secrets/postgres_password.txt
    fi
fi

# Adiciona todos os arquivos ao repositório Git
echo "Adicionando todos os arquivos ao repositório Git..."
git -C $BASE_DIR add --all
git -C $BASE_DIR commit -m "Initial"

echo "Configuração concluída com sucesso!"