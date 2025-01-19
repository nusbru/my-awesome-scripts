# my-awesome-scripts

Shell scripts to make my life easier

## Description

This project contains a collection of shell scripts that automate the creation of .NET projects with different configurations. The scripts help to quickly set up a complete development environment, including the creation of .NET solutions, Blazor projects, Minimal API projects, Git repository configuration, adding dependencies, Docker setup, and more.

## Scripts

### `blazor.sh`

This script creates a Blazor project with individual authentication, adds necessary dependencies, sets up a Git repository, creates a Dockerfile and a `docker-compose.yml` file, and configures a development environment with a dev container.

### `minimal.sh`

This script creates a Minimal API project, adds necessary dependencies, sets up a Git repository, creates a Dockerfile, and configures a development environment with a dev container.

## How to Use

1. Clone this repository.
2. Make the scripts executable:
   ```sh
   chmod +x blazor.sh minimal.sh
   ```
3. Run the desired script passing the project name as an argument:
   ```sh
   ./blazor.sh ProjectName
   ```
   or
   ```sh
   ./minimal.sh ProjectName
   ```

## Requirements

- Git
- .NET SDK
- Docker
- Bash

## License

This project is licensed under the MIT License.
