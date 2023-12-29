# CMS Test Base Docker Image Builder (ARCHIVED)

[![Docker Pulls](https://img.shields.io/docker/pulls/jgoldfar/cms-test-image.svg)](https://hub.docker.com/r/jgoldfar/cms-test-image/)

This repository handles the creation of isolated test environments and orchestration of test runners; it is currently archived and only retained for informational purposes.

The use-case is "large" heterogeneous repositories with multiple implementation languages and extensive documentation, for which lightweight CI services have failed either at the clone or test phase.
The type of integration test or tests to be run can be modified easily by adjusting the necessary configuration in the `Makefile`.

The images are divided into three parts, intended to correspond roughly to components that change at roughly three rates.
All processes have access to

- Julia v0.7
- Maxima (built from a git checkout against SBCL)
- Miniconda3, and
- LaTeX (minimal installation)

The "fixed" layer is the `prepared` image, containing the main dependencies listed above, as well as a minimal set of CTAN packages, git repositories, etc. to compile everything else.

The last layer, `main`, changes for each revision of the repository (and is tagged as such, to allow exploration of previous builds)

## Setup

You'll need to install [Docker](https://www.docker.com/) for your platform, and a few other tools before getting started.

The following is the sequence of steps I've used recently to get an installation like this running on a new machine:

- Install git

```shell
sudo apt-get install git
```

- Setup your git installation (if necessary), for instance:

```shell
git config --global user.email "your-email"
git config --global user.name "Your Name"
```

If not yet set-up, you'll need to create and add a SSH key for [Github](https://github.com/settings/keys) and [Bitbucket](https://bitbucket.org/account/user/).
The guide [here](https://help.github.com/en/articles/connecting-to-github-with-ssh) gives step-by-step instructions:

```shell
ssh-keygen -t rsa -b 4090 -C "your-email" -N "password" -f ${HOME}/.ssh/id_github_ci
```

For your own purposes, I recommend to create separate keys for your everyday use on each service, and another independent key for use by the CI server.
This ensures that key invalidation if/when it happens can easily and quickly be mitigated by rotating the given keys.

As a brief aside, the easiest way to ensure these keys are always used by your user is to add them to the ssh configuration file in `~/.ssh/config`.
For example, if you created a key for bitbucket in `id_bitbucket` and a key for github in `id_github`, you'd create a file with the contents

```
Host bitbucket.org
  HostName bitbucket.org
  IdentityFile /home/username/.ssh/id_bitbucket

Host github.com
  HostName github.com
  IdentityFile /home/username/.ssh/id_github
```

- Clone [this repository](https://github.com/jgoldfar/cmstest-base-docker) somewhere convenient:

```shell
git clone git@github.com:jgoldfar/cmstest-base-docker.git ~/cmstest
cd ~/cmstest
```

- Run the initialization target:

```shell
make initialization
```

The rest of the build & test commands, etc. are stored in a Makefile.
Processes can be run and options adjusted on the command line; run `make usage`
to see what targets and options can be chosen.

## Usage

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
travis encrypt-file id_rsa --add
```

*Note*: One could explore those repositories without having actual pull access, but this isn't too much of an issue for me, because most of those projects are public or semi-public anyways.
It's not entirely clear how one would set up the necessary access controls to be able to run code pulled from a private GitHub repo, but not observe it... static package compilation would get you part of the way, but some things will have to be made public at some point.

## Roadmap/TODO

* Fixup Maxima/SBCL installation: see https://github.com/daewok/slime-docker/blob/master/resources/docker-sbcl-seccomp.json and https://github.com/daewok/slime-docker/blob/master/README.md#some-gotchas

* Consider reducing the image size by downloading git archives instead of a full clone: https://stackoverflow.com/questions/3946538/git-clone-just-the-files-please
