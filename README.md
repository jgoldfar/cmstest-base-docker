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
- Interoperates with [CMSTest](https://bitbucket.org/jgoldfar/cmstest.jl/) v3.0.1+ (i.e. commits newer than revision 6b9245d80691)

## Container Descriptions

* `base` packages listed above (most slowly changing/slowest release cadence)

* `prepared` includes `base` and the minimal set of CTAN packages, Julia envs, git repositories, etc. to compile everything else (these change more slowly, one would hope.) To build this image, you'll need to provide a private SSH key for which the public key is saved to Github and Bitbucket. To do this, I ran

```shell
ssh-keygen -t rsa -b 4096 -C "jgoldfar+docker@gmail.com" -f id_rsa
cat id_rsa
cat id_rsa.pub
```
and copied the private key to e.g. an encrypted file that can only be unlocked on Travis.
Note that this means one could explore those repositories without having actual pull
access, but this isn't too much of an issue because most of those projects are public
or semi-public anyways.
