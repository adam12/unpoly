# DevContainer built on Docker

## Build

    $ docker build -f .devcontainer/Dockerfile -t unpoly-devcontainer .

## Start container

    $ docker run --rm -it -v $(pwd):/app -p 3000 unpoly-devcontainer bash

## Building assets (inside container)

    $ bundle install
    $ bundle exec rake assets:build

## Running test server (inside container)

    $ cd spec_app
    $ bundle install
    $ bundle exec rails server -b 0.0.0.0

## Running specs

    $ docker ps
    $ docker port <id-of-running-container>
    # visit http://localhost:<exposed port shown above>/specs in your browser
