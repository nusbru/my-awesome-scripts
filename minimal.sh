#!/bin/bash

# Verifica se o nome do projeto foi fornecido
if [ -z "$1" ]; then
    echo "Uso: $0 <nome-do-projeto>"
    exit 1
fi

# Define variáveis
PROJECT_NAME=$1
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

# Cria o devcontainer.json
cat <<EOF > $DEVCONTAINER_DIR/devcontainer.json
{
    "name": "Minimal API",
    "image": "mcr.microsoft.com/dotnet/sdk:9.0",
    "extensions": [
      "ms-dotnettools.csdevkit",
      "ms-dotnettools.csharp",
      "ms-dotnettools.vscodeintellicode-csharp",
      "ms-vscode-remote.remote-containers",
      "redhat.vscode-yaml",
    ],
    "postCreateCommand": "dotnet restore"
}
EOF

echo "Configuração concluída com sucesso!"
