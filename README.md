CMS Test Base Docker Image Builder
=====

[![Docker Pulls](https://img.shields.io/docker/pulls/jgoldfar/cms-test-image.svg)](https://hub.docker.com/r/jgoldfar/cms-test-image/)
[![Build Status](https://travis-ci.org/jgoldfar/cmstest-base-docker.svg?branch=master)](https://travis-ci.org/jgoldfar/cmstest-base-docker)

Setup
-----
First, add your local user to docker group:
```bash
sudo usermod -aG docker YOURUSERNAME
```

build:
```bash
docker build -t jgoldfar/cms-test-image .

```

Usage:
-----

```bash
docker run --rm -i --user="$(id -u):$(id -g)" --net=none -v "$(pwd)":/data jgoldfar/cms-test-image

# Or better in one go (does not start container twice)
docker run --rm -i --user="$(id -u):$(id -g)" --net=none -v "$(pwd)":/data jgoldfar/cms-test-image /bin/sh -c "pdflatex example.tex && pdflatex example.tex"

# View
./example.pdf
```
`WORKDIRs` match, mounted to `/data` inside container.

Why should I use this container?

-----

- Easy setup
- Julia v0.7, Maxima + SBCL, Miniconda3, and LaTeX-Minimal all available on PATH

## Container Descriptions

* `base` packages listed above
