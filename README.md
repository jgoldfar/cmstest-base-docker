CMS Test Base Docker Image Builder
=====

[![Docker Pulls](https://img.shields.io/docker/pulls/jgoldfar/cms-test-image.svg)](https://hub.docker.com/r/jgoldfar/cms-test-image/)
[![Build Status](https://travis-ci.org/jgoldfar/cmstest-base-docker.svg?branch=master)](https://travis-ci.org/jgoldfar/cmstest-base-docker)

This repository handles the creation of isolated test environments and orchestration of tests run against our [CMSTest](https://bitbucket.org/jgoldfar/cmstest.jl/) package, which handles automatic test discovery for "large" heterogeneous repositories.
Interoperates with [CMSTest](https://bitbucket.org/jgoldfar/cmstest.jl/) v3.0.1+ (i.e. commits newer than revision 6b9245d80691)

The images are divided into three parts, intended to correspond roughly to components that change at roughly three rates.
All processes have access to

- Julia v0.7
- Maxima (from git) + SBCL
- Miniconda3, and 
- LaTeX (minimal installation)

The "fixed" layer is the `prepared` image, containing the main dependencies listed above, as well as a minimal set of CTAN packages, git repositories, etc. to compile everything else.

The last layer, `main`, changes for each revision of the repository (and is tagged as such, to allow exploration of previous builds)

Setup
-----
You'll need to install [Docker](https://www.docker.com/) for your platform.

The rest of the build & test commands, etc. are stored in a Makefile.
Processes can be run and options adjusted on the command line; run `make usage`
to see what targets and options can be chosen.

Usage:
-----

I run these processes with a cron job on an Ubuntu workstation, but the build steps are replicated (to the extent that they can be) on Travis.
Only the last image must be built and run on a machine having access to the main repository (which in my case is private) and test output repository.

Assuming the package is available under `$HOME/Public/cms-image`, it takes only one cron listing (always document non-obvious commands in your crontab!)

```shell
# Pull CMS Repository, and if new commits are to be tested, run IWS code
# test script. 
*/10 * * * * cd $HOME/Public/cms-image && date > testIWS.log && make pull-test-and-record >> testIWS.log 2>&1
```

There are a couple other targets that are kind to run regularly:
```shell
# Cleanup any inconsistencies on reboot
@reboot cd $HOME/Public/cms-image && make force-cleanup force-clean-main-repo > cleanupIWS.log 2>&1
#
# Cleanup CMS images monthly
@monthly cd $HOME/Public/cms-image && make cleanup-all-images > cleanup.log 2>&1
```

## Build/Implementation Details

To build the `main` image, you'll need to embed a private SSH key for which the public key is saved to Github and Bitbucket; right now, this is accomplished by using a local key that is copied into the image and deleted after use.

If you need to encrypt a key to e.g. upload this step to a secure service, you can generate a new key by running

```shell
ssh-keygen -t rsa -b 4096 -C "jgoldfar+docker@gmail.com" -f id_rsa
cat id_rsa
cat id_rsa.pub
```

and copy the private key to e.g. an encrypted file that can only be unlocked on Travis using

```shell
travis encrypy-file id_rsa --add
```

*Note*: One could explore those repositories without having actual pull access, but this isn't too much of an issue for me, because most of those projects are public or semi-public anyways.
It's not entirely clear how one would set up the necessary access controls to be able to run code pulled from a private GitHub repo, but not observe it... static package compilation would get you part of the way, but some things will have to be made public at some point.
