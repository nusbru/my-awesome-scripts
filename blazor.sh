#!/bin/bash

# Verifica se foi passado um nome de projeto
if [ -z "$1" ]; then
    echo "Uso: $0 nome_do_projeto"
    exit 1
fi

PROJECT_NAME=$1

mkdir $PROJECT_NAME
cd $PROJECT_NAME

dotnet new sln -n $PROJECT_NAME

mkdir src
cd src

# Cria o projeto Blazor Server
dotnet new blazor -n $PROJECT_NAME --auth individual

# Navega para o diretório do projeto
cd $PROJECT_NAME

# Adiciona os pacotes necessários
dotnet add package Microsoft.AspNetCore.Identity.EntityFrameworkCore
dotnet add package Npgsql.EntityFrameworkCore.PostgreSQL
dotnet add package Microsoft.VisualStudio.Web.CodeGeneration.Design

cd ..
cd ..
mkdir test
cd test
# Adiciona o projeto de teste
dotnet new xunit -n ${PROJECT_NAME}.Tests

# Navega para o diretório do projeto de teste
cd ${PROJECT_NAME}.Tests

# Adiciona os pacotes de teste
dotnet add package FluentAssertions
dotnet add package NSubstitute

# Retorna para o diretório do projeto principal
cd ..
cd ..

# Cria o Dockerfile
cat <<EOF > Dockerfile
# Etapa 1: Build
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build-env
WORKDIR /app

# Copia o arquivo csproj e restaura as dependências
COPY *.csproj ./
RUN dotnet restore

# Copia o restante da aplicação e constrói
COPY . ./
RUN dotnet publish -c Release -o out

# Etapa 2: Criação da imagem final
FROM mcr.microsoft.com/dotnet/aspnet:8.0
WORKDIR /app
COPY --from=build-env /app/out .

# Expondo a porta que a aplicação irá rodar
EXPOSE 80

# Comando para rodar a aplicação
ENTRYPOINT ["dotnet", "$PROJECT_NAME.dll"]
EOF

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

# Cria a pasta .devcontainer
mkdir -p .devcontainer

# Cria o devcontainer.json
cat <<EOF > .devcontainer/devcontainer.json
{
    "name": "Blazor Server",
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

dotnet sln add ./src/$PROJECT_NAME/$PROJECT_NAME.csproj
dotnet sln add ./test/$PROJECT_NAME.Tests/$PROJECT_NAME.Tests.csproj

# Mensagem final
echo "Projeto $PROJECT_NAME criado com sucesso!"
