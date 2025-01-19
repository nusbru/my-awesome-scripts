#!/bin/bash

# Verifica se foi passado um nome de projeto
if [ -z "$1" ]; then
    echo "Uso: $0 nome_do_projeto"
    exit 1
fi

# Define variáveis
PROJECT_NAME=$1
BASE_DIR=$(pwd)/$PROJECT_NAME
SRC_DIR=$BASE_DIR/src
TEST_DIR=$BASE_DIR/test
BLAZOR_PROJECT="$SRC_DIR/$PROJECT_NAME.UI"
TEST_PROJECT="$TEST_DIR/$PROJECT_NAME.UI.Tests"
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
dotnet new web -o $BLAZOR_PROJECT -n "$PROJECT_NAME.UI"

# Adiciona os pacotes necessários
dotnet add $BLAZOR_PROJECT package Microsoft.AspNetCore.Identity.EntityFrameworkCore
dotnet add $BLAZOR_PROJECT package Npgsql.EntityFrameworkCore.PostgreSQL
dotnet add $BLAZOR_PROJECT package Microsoft.VisualStudio.Web.CodeGeneration.Design

# Adiciona o projeto API à solução
echo "Adicionando projeto Blazor à solução..."
dotnet sln $BASE_DIR/$PROJECT_NAME.sln add $BLAZOR_PROJECT

# Cria o projeto de testes
echo "Criando projeto de testes..."
dotnet new xunit -o $TEST_PROJECT -n "$PROJECT_NAME.UI.Tests"

# Adiciona dependências ao projeto de testes
echo "Adicionando dependências ao projeto de testes..."
dotnet add $TEST_PROJECT package FluentAssertions
dotnet add $TEST_PROJECT package NSubstitute
dotnet add $TEST_PROJECT package coverlet.collector

# Adiciona referência ao projeto API
echo "Adicionando referência ao projeto Blazor no projeto de testes..."
dotnet add $TEST_PROJECT reference $BLAZOR_PROJECT

# Adiciona o projeto de testes à solução
echo "Adicionando projeto de testes à solução..."
dotnet sln $BASE_DIR/$PROJECT_NAME.sln add $TEST_PROJECT

# Adiciona o Dockerfile na raiz do projeto
echo "Criando Dockerfile na raiz do projeto..."
cat <<EOL > $BASE_DIR/Dockerfile
# Etapa 1: Build
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /app

# Copia a solução e restaura a
s dependências
COPY ./*.sln ./
COPY ./src/$PROJECT_NAME.UI/*.csproj ./src/$PROJECT_NAME.UI/
RUN dotnet restore ./src/$PROJECT_NAME.UI/$PROJECT_NAME.UI.csproj

# Copia o restante do código e faz o build
COPY ./src/$PROJECT_NAME.UI/. ./src/$PROJECT_NAME.UI/
WORKDIR /app/src/$PROJECT_NAME.UI
RUN dotnet publish -c Release -o /publish

# Etapa 2: Runtime
FROM mcr.microsoft.com/dotnet/aspnet:9.0
WORKDIR /app
COPY --from=build /publish .
ENTRYPOINT ["dotnet", "$PROJECT_NAME.UI.dll"]
EOL

lowercase_project_name="${PROJECT_NAME,,}"

# Cria o docker-compose.yml
cat <<EOF > docker-compose.yml
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
    image: 'postgres:latest'
    ports:
      - 5432:5432
    environment:
      POSTGRES_USER: ${lowercase_project_name}
      POSTGRES_PASSWORD: ${lowercase_project_name}_pwd
      POSTGRES_DB: ${lowercase_project_name}db
    volumes:
      - ${PWD}/db-data/:/var/lib/postgresql/data/
    networks:
      - ${lowercase_project_name}-network

networks: 
  ${lowercase_project_name}-network:
    driver: bridge 
EOF

mkdir $DEVCONTAINER_DIR

# Cria o devcontainer.json
cat <<EOF > $DEVCONTAINER_DIR/devcontainer.json
{
    "name": "Minimal API",
    "image": "mcr.microsoft.com/dotnet/sdk:9.0",
    "customizations": {
        "vscode": {
            extensions": [
              "ms-dotnettools.csdevkit",
              "ms-dotnettools.csharp",
              "ms-dotnettools.vscodeintellicode-csharp",
              "ms-vscode-remote.remote-containers",
              "redhat.vscode-yaml",
            ]
        }
    },            
    "postCreateCommand": "dotnet restore"
}
EOF

# Cria Makefile
echo "Criando Makefile..."
cat <<EOL > "$BASE_DIR/Makefile"
.PHONY: all build run test clean

all: build

build:
		dotnet build "$PROJECT_NAME.sln"

run:
		dotnet run --project "$BLAZOR_PROJECT"

test:
		dotnet test "$TEST_PROJECT"

clean:
		dotnet clean "$PROJECT_NAME.sln"
EOL

# Adiciona todos os arquivos ao repositório Git
echo "Adicionando todos os arquivos ao repositório Git..."
git -C $BASE_DIR add --all
git -C $BASE_DIR commit -m "Initial"

echo "Configuração concluída com sucesso!"
