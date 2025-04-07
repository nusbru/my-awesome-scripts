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

echo ".secrets" >> $BASE_DIR/.gitignore
echo ".devcontainer" >> $BASE_DIR/.gitignore
echo ".env" >> $BASE_DIR/.gitignore

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
      POSTGRES_INITDB_ARGS: \${POSTGRES_INITDB_ARGS}
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
POSTGRES_DB=${lowercase_project_name}db
POSTGRES_USER=${lowercase_project_name}_usr
POSTGRES_INITDB_ARGS="--data-checksums --encoding=UTF8 --locale=C.UTF-8"
POSTGRES_MAX_CONNECTIONS=100
POSTGRES_SHARED_BUFFERS=128MB

COMPOSE_PROJECT_NAME="${lowercase_project_name}"
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

    if [ "$DATABASE_NAME" == "mssql" ]; then
        echo "Criando dockerfile com MSSQL Database"
        # Cria o docker-compose.yml
        cat <<EOF > $BASE_DIR/docker-compose.yml

services:
  app:
    build:
      context: .
    ports:
      - "80:80"
    depends_on:
      - db      
  db:
    image: mcr.microsoft.com/mssql/server:2022-latest
    restart: unless-stopped
    user: root
    command: >
      bash -c "chown -R 10001 /var/opt/mssql && /opt/mssql/bin/sqlservr"
    environment:
      ACCEPT_EULA: "Y"
      MSSQL_SA_PASSWORD_FILE: /run/secrets/mssql_password
    env_file:
      - .env
    ports:
      - "1433:1433"
    volumes:
      - mssql_data:/var/opt/mssql/data
      - ${MSSQL_INIT_SCRIPTS_PATH:-./mssql-init-scripts}:/docker-entrypoint-initdb.d
    healthcheck:
      test: ["CMD-SHELL", "/opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P \$(cat /run/secrets/mssql_password) -Q 'SELECT 1' || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
    secrets:
      - mssql_password
    deploy:
      resources:
        limits:
          cpus: ${MSSQL_CPU_LIMIT:-1}
          memory: ${MSSQL_MEMORY_LIMIT:-2G}
volumes:
  mssql_data:
    name: \${COMPOSE_PROJECT_NAME}_mssql_data

secrets:
  mssql_password:
    file: ./.secrets/mssql_password.txt

networks: 
  "${lowercase_project_name}-network":
    driver: bridge         
EOF
        cat <<EOF > $BASE_DIR/.env
#MSSQL
MSSQL_DB=${lowercase_project_name}db
MSSQL_PID=Express
MSSQL_CPU_LIMIT=1
MSSQL_MEMORY_LIMIT=2G
MSSQL_INIT_SCRIPTS_PATH=./mssql-init-scripts
PG_CPU_LIMIT=1
PG_MEMORY_LIMIT=1G
EOF
    mkdir -p $BASE_DIR/.secrets
    echo "$(openssl rand -base64 16)" > $BASE_DIR/.secrets/mssql_password.txt
    chmod 600 $BASE_DIR/.secrets/mssql_password.txt
    fi
fi

# Adiciona todos os arquivos ao repositório Git
echo "Adicionando todos os arquivos ao repositório Git..."
git -C $BASE_DIR add --all
git -C $BASE_DIR commit -m "Initial"

echo "Configuração concluída com sucesso!"