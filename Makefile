# CMS-Image Makefile: Orchestrate tests run against CMSTest, which handles
# automatic test discovery for "large" heterogeneous repositories.
#
# This makefile is still not safe against interrupts in the generation process
# practically anywhere. So e.g. restarting the host machine will cause things to be
# left in an undefined state, which may require a run of `make force-cleanup`.

#TODO: Add test that we're using a new-enough version of CMSTest
# to run this process. Known to work well against CMSTest v3.0.1
# or versions of CMSTest newer than commit 6b9245d80691

#TODO: Add report or check for un-uploaded report files left in REPORTDIR
#TODO: Add target to re-run analyses of commits (basically, to regenerate
#      SUMMARY and DIFF for a commit based on given stderr.log and
#      stdout.log files.

## Start configurable variables
HG?=$(shell which hg)
PWD=$(shell pwd)

# Set explicit shell
export SHELL:=/bin/bash

# Attempt to ensure we can cleanup after a process failure
export SHELLOPTS:=$(if $(SHELLOPTS),$(SHELLOPTS):)pipefail:errexit

# Username on Docker Hub
DOCKER_USERNAME?=jgoldfar

# Base image name for uploaded artifacts
DOCKER_REPO_BASE:=cms-test-image

# User info for current user (to be duplicated within the docker container:
# we don't want to run our tests as root.)
USERINFO:=$(shell id -u):$(shell id -g)

# This is the default branch we use to report these test results, as well as
# a suffix for the test directory.
Report_Repo_Branch?=$(shell uname -s)

# Local path to SSH key authenticated to Github and Bitbucket
SSH_PRV_KEY_FILE?=${HOME}/.ssh/id_rsa

# Local path to updated main repository. We should only be generating these
# targets on non-CI machines (for now) so this will be empty if CI is not.
ifeq ($(CI),)
MainRepoPath?=/Users/jgoldfar/Documents
else
MainRepoPath?=
endif

# If we're currently using the MainRepo, we'll have a lock directory here:
MainRepoLockDir:=${MainRepoPath}/.LOCK

# Local path to test output directory
ExternalReportDir?=/Users/jgoldfar/test-${Report_Repo_Branch}

# Internal path to test output directory
InternalReportDir:=/Tests

# Within the repo in MainRepoPath, we will expect to be running commands
# from this makefile.
CMSMakefile=misc/julia/CMSTest/ex/crontab/Makefile

# If FORCE_UPDATE is nonempty, we'll update over any existing changes.
FORCE_UPDATE?=

# Generic usage string. Use Make's subst command to interpolate the target.
USAGE_STRING:="Usage: make __tmp__"
## End Configurable Variables


## Start main set of targets

# Usage messages
.PHONY: usage usage-main
usage: usage-main usage-targets usage-useful-variables usage-variables

usage-main:
	@echo $(subst __tmp__,[TARGET],${USAGE_STRING})
	@echo ""
	@echo " Valid TARGETs:"

usage-useful-variables:
	@echo ""
	@echo " Useful Variables:"
	@echo "    - MainRepoPath: Path to local clone of test repository. Default: ${MainRepoPath}"
	@echo "    - ExternalReportDir: Path to local clone of report recording repository. Default: ${ExternalReportDir}"
	@echo "    - FORCE_UPDATE: Set nonempty to overwrite existing test results."
	@echo "    - Report_Repo_Branch: Branch used to record test results. Default: ${Report_Repo_Branch}"
	@echo "    - SSH_PRV_KEY_FILE: Path to local private key file authenticated to Github & Bitbucket."
	@echo "    - HG: Path to mercurial executable. Default: ${HG}"

usage-targets: usage-main-targets

usage-main-targets:
	@echo "   - usage: Show this message."
	@echo "   - cleanup-all-images: Remove all generated images."
	@echo "   - cleanup-main-images: Remove main images."
	@echo "   - force-cleanup: Remove test results and all dependencies for current revision."

# Include targets for building "base" images
include DockerBaseBuild.mk

# Include recipe to derive variables from configuration
include DerivedVariables.mk

# Include targets for building main image
include DockerMainBuild.mk

# Include targets for managing the main repository
include RepoManagement.mk

# Include main test targets
include Runtests.mk


# This section only exists to clean up in the case of a "bad" interruption in a process
remove-locks:
	@( [ -d "${FULL_REPORT_LOCK_DIR}" ] && rmdir ${FULL_REPORT_LOCK_DIR} ) || echo "${FULL_REPORT_DIR} not locked."
	@( [ -d "${MainRepoLockDir}" ] && rmdir "${MainRepoLockDir}" ) || echo "${MainRepoPath} not locked."

force-cleanup: remove-locks cleanup-main-images
	$(RM) -r ${FULL_REPORT_DIR}

# This target cleans up generated images. We check if the list is empty to avoid
# calling docker rmi with an empty argument.
cleanup-all-images:
	( \
		imagesToRemove="$(shell docker images --all --format "{{.Repository}}:{{.Tag}}" | grep '${DOCKER_REPO_BASE}')" ; \
		[ -z "$${imagesToRemove}" ] && echo "No images to remove" || docker rmi $${imagesToRemove} \
	)
	docker system prune --force --volumes

cleanup-main-images:
	( \
		imagesToRemove="$(shell docker images --all --format "{{.Repository}}:{{.Tag}}" | grep '${DOCKER_REPO_BASE}:main')" ; \
		[ -z "$${imagesToRemove}" ] && echo "No images to remove" || docker rmi $${imagesToRemove} \
	)
	docker system prune --force --volumes

# Generic (safe) clean target
clean: cleanup-main-images
	$(RM) ${PWD}/Documents-*
