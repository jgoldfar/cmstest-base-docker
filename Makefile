#TODO: Add test that we're using a new-enough version of CMSTest
# to run this process. Known to work well against CMSTest v3.0.1
# or versions of CMSTest newer than commit 6b9245d80691
HG?=$(shell which hg)
PWD=$(shell pwd)

export SHELL:=/bin/bash
# Attempt to ensure we can cleanup after a process failure
export SHELLOPTS:=$(if $(SHELLOPTS),$(SHELLOPTS):)pipefail:errexit

DOCKER_USERNAME?=jgoldfar
DOCKER_REPO_BASE:=cms-test-image

# Local path to SSH key authenticated to Github and Bitbucket
SSH_PRV_KEY_FILE?=/home/jgoldfar/.ssh/id_rsa

# Local path to updated main repository
MainRepoPath?=/Users/jgoldfar/Documents
# Local path to test output directory
ExternalReportDir?=/Users/jgoldfar/test-$(shell uname -s)

# Internal path to test output directory
InternalReportDir?=/Tests

# Within the repo in MainRepoPath, we will expect to be running commands
# from this makefile.
CMSMakefile=misc/julia/CMSTest/ex/crontab/Makefile

# If FORCE_UPDATE is nonempty, we'll update over any existing changes.
FORCE_UPDATE?=

usage:
	@echo "Usage Not Yet Defined"

##
# "Generic" image build
build-%: Dockerfile.%
	docker build \
		-f $< \
		-t ${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:$* .

push-%: build-%
	docker push ${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:$*

base: build-base push-base

##
# "Prepared" image build
build-prepared: Dockerfile.prepared
	docker build \
		-f $< \
		--build-arg ssh_prv_key="`cat $(SSH_PRV_KEY_FILE)`" \
		-t ${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:prepared .

# Capture the PATH variable from the "Prepared" image
Prepared_Image_Path:=$(shell docker run --attach stdout --volume ${PWD}/LocalSupportScripts:/LocalSupportScripts ${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:prepared /LocalSupportScripts/echo-path)

prepared: build-prepared push-prepared


##
# "Main" image build and test run
# We first test if MainRepoPath isempty; if so, emit a usage message and bail.
ifeq ($(MainRepoPath),) 
build-main:
	$(error "Usage: make $@ MainRepoPath=/path/to/Documents")

##
# When MainRepoPath is not empty, we can build the main image
else 
# Derive REPORTID from HG node hash from MainRepoPath. If you provide a hg id
# on the command line, we'll do our best to run tests against that revision, but
# with subrepos things can get complicated...
REPORTID?=$(shell $(HG) log --cwd $(MainRepoPath) -l 1 -T '{node}')
# Derive REPORTDATE from corresponding hgdate
REPORTDATE:=$(shell $(HG) log --cwd $(MainRepoPath) -r "$(REPORTID)" -T '{word(0, date|hgdate)}')
# The generated main image will have the tag below:
MAIN_REPO_IMAGE:=${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:main-${REPORTID}
# Internal path to main repository. 
InternalRepoStem?=Documents-${REPORTID}
# The repository tarball will be generated into the file with the name below:
REPO_TARBALL:=${InternalRepoStem}.tar
# We'll generate test output into the directory below:
FULL_REPORT_DIR:=${ExternalReportDir}/${REPORTID}


# Build an image containing a snapshot of ${MainRepoPath} at the given REPORTID
# NOTE The generated tarball name must match the directory under `/` that we will
# be running the generated tests from. This is enforced by generating the tarball
# into $(notdir ${InternalRepoStem}).
# Note on this tarball:
#     Tested tar, tgz, and zip, and tarballs are fastest to generate.
#TODO: Test exporting to a new directory to avoid the cost of tarring and
# untarring the repository.
#TODO: This makefile is still not safe against interrupts in the generation process
# practically anywhere. So e.g. restarting the host machine will cause things to be
# left in an undefined state, which may require a run of `make force-cleanup`.
build-main: Dockerfile.main ${REPO_TARBALL}
	[ ! -d "${MainRepoPath}/.LOCK" ]
	docker build \
		--no-cache \
		-f Dockerfile.main \
		-t ${MAIN_REPO_IMAGE} .

${REPO_TARBALL}:
	[ ! -d "${MainRepoPath}/.LOCK" ]
	mkdir "${MainRepoPath}/.LOCK" && \
	hg archive --time \
		--cwd ${MainRepoPath} \
		--rev ${REPORTID} \
		--subrepos \
		--exclude "ugrad/climate dynamics/" \
		$(PWD)/$@ || \
	(ret=$$?; rmdir "${MainRepoPath}/.LOCK" && exit $$ret)
	rmdir "${MainRepoPath}/.LOCK"

# The dockerfile used to generate the main image is minimal; we just import the repository
# files and set the working directory to the correct location.
# NOTE: InternalRepoStem and the name of the tarball have to be kept in sync as
# above.
Dockerfile.main: Makefile
	echo "FROM ${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:prepared" > $@
	echo "MAINTAINER Jonathan Goldfarb <jgoldfar@gmail.com>" >> $@
	echo "ADD ${REPO_TARBALL} /" >> $@
	echo "WORKDIR /$(patsubst %.tar,%,${REPO_TARBALL})" >> $@

# This target will fail if the main image isn't yet built.
main-is-built:
	docker inspect ${MAIN_REPO_IMAGE}

REPO_UPDATE_CMD:=hg update
ifneq (${FORCE_UPDATE},)
REPO_UPDATE_CMD+=--clean
endif
maybe-update-main-repo:
	[ ! -d "${MainRepoPath}/.LOCK" ]
	mkdir "${MainRepoPath}/.LOCK" \
	&& cd "${MainRepoPath}" \
	&& hg status -mard \
	&& hg pull \
	&& ${REPO_UPDATE_CMD} || \
	(ret=$$?; rmdir "${MainRepoPath}/.LOCK" && exit $$ret)
	rmdir "${MainRepoPath}/.LOCK"

##
# Check that ExternalReportDir isempty, MainRepoPath is not empty
# If so, emit a usage message for test-main and push-test-main (which
# cannot run in this situation.)
ifeq ($(ExternalReportDir),) 
test-main:
	@echo "Usage: make $@ MainRepoPath=/path/to/documents ExternalReportDir=/path/to/testdir"

push-test-main:
	@echo "Usage: make $@ MainRepoPath=/path/to/documents ExternalReportDir=/path/to/testdir"

run-main:
	@echo "Usage: make $@ MainRepoPath=/path/to/documents ExternalReportDir=/path/to/testdir"

##
# If ExternalReportDir is not empty and MainRepoPath is not empty
# We can run test-main, push-test-main, and run-main
else

# This target runs tests. As part of that, it creates a lockfile in the report directory,
# so only one such set of tests will be run.
${FULL_REPORT_DIR}/stderr.log:
	$(MAKE) main-is-built || $(MAKE) build-main
	mkdir -p ${FULL_REPORT_DIR}
	[ ! -d "${FULL_REPORT_DIR}/.LOCK" ]
	mkdir "${FULL_REPORT_DIR}/.LOCK" && \
	docker run \
		--tty \
		--attach stderr \
		--attach stdout \
		--env REPOROOT="/${InternalRepoStem}" \
		--env REPORTDIR=${InternalReportDir} \
		--env REPORTID=${REPORTID} \
		--env REPORTDATE=${REPORTDATE} \
		--env JULIA_LOAD_PATH="/${InternalRepoStem}/misc/julia" \
		--env JULIA_ARGS="--project=/${InternalRepoStem}/misc/julia/CMSTest" \
		--volume ${ExternalReportDir}:${InternalReportDir} \
		${MAIN_REPO_IMAGE} \
		make -f ${CMSMakefile} \
		instantiate show-hg-info runtests-all \
		VERBOSE=true || \
	(ret=$$?; rmdir "${FULL_REPORT_DIR}/.LOCK" && exit $$ret)
	rmdir "${FULL_REPORT_DIR}/.LOCK"

# test-main is a shorter spelling of the above target.
.PHONY: test-main
test-main: ${FULL_REPORT_DIR}/stderr.log

# This target runs the same test suite against the repository as it currently
# exists. The MainRepoPath is mapped to a read-only volume in the image.
# Note that this is likely to lead to far more failures, since no output that
# usually lives in the main repo can be created. WIP
${PWD}/TestOutput/stderr.log:
	docker run \
		--rm \
		--workdir "/Documents" \
		--volume ${MainRepoPath}:/Documents:ro \
		--tty \
		--attach stderr \
		--attach stdout \
		--env REPOROOT="/Documents" \
		--env REPORTDIR=${InternalReportDir} \
		--env REPORTID=${REPORTID}-dev \
		--env REPORTDATE=${REPORTDATE} \
		--env JULIA_LOAD_PATH="/Documents/misc/julia" \
		--env JULIA_ARGS="--project=/Documents/misc/julia/CMSTest" \
		--env PATH="/LocalSupportScripts:${Prepared_Image_Path}" \
		--volume ${PWD}/TestOutput:${InternalReportDir} \
		--volume ${PWD}/LocalSupportScripts:/LocalSupportScripts:ro \
		${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:prepared \
		make -f ${CMSMakefile} --keep-going \
		instantiate show-hg-info runtests-all \
		VERBOSE=true

# This is a shorter spelling of the above target.
test-main-local: ${PWD}/TestOutput/stderr.log

# This target runs tests, while saving any output from the build process itself
# into a logfile.
${FULL_REPORT_DIR}/build.log:
	mkdir -p ${FULL_REPORT_DIR}
	$(MAKE) test-main > $@ 2>&1

# really-test-main is a shorter spelling of the above target.
really-test-main: ${FULL_REPORT_DIR}/build.log

# To commit and push tests, we need the ${ExternalReportDir} to be initialized
# to the correct git repository.
${ExternalReportDir}/.git:
	git clone git@bitbucket.org:jgoldfar/jgoldfar-cms-testresults.git $(dir $<)
	cd $(dir $<) && \
	git config user.name "IWS-Docker-${DOCKER_USERNAME}

# This target summarizes the test results and commits updated data to the
# ${ExternalReportDir} git repository. As a part of that, we emit a lock
# in the corresponding directory so existing test or report generation routines
# are not interrupted.
# Note that this process does not pull new commits into ExternalReportDir, or 
# push any commits out, so that will still have to be managed externally.
# TODO: Add git pull & git push here to make this target self-contained.
record-test-main: ${FULL_REPORT_DIR}/committed

${FULL_REPORT_DIR}/committed: ${FULL_REPORT_DIR}/build.log ${ExternalReportDir}/.git
	$(MAKE) main-is-built || $(MAKE) build-main
	[ ! -d "${FULL_REPORT_DIR}/.LOCK" ]
	mkdir "${FULL_REPORT_DIR}/.LOCK" && \
	docker run \
		--tty \
		--attach stderr \
		--attach stdout \
		--env REPOROOT="/${InternalRepoStem}" \
		--env REPORTDIR=${InternalReportDir} \
		--env REPORTID=${REPORTID} \
		--env REPORTDATE=${REPORTDATE} \
		--env JULIA_LOAD_PATH="/${InternalRepoStem}/misc/julia" \
		--env JULIA_ARGS="--project=/${InternalRepoStem}/misc/julia/CMSTest" \
		--volume ${ExternalReportDir}:${InternalReportDir} \
		${MAIN_REPO_IMAGE} \
		make -f ${CMSMakefile} \
		instantiate generate-summaries update-test-readme record-summaries \
		VERBOSE=true NOPUSH=true NOPULL=true || \
	(ret=$$?; rmdir "${FULL_REPORT_DIR}/.LOCK" && exit $$ret)
	rmdir "${FULL_REPORT_DIR}/.LOCK"

# This target allows you to drop into the built image corresponding to a given REPORTID
# to debug test failures.
run-main:
	$(MAKE) main-is-built || $(MAKE) build-main
	docker run \
		--tty --interactive \
		--attach stderr \
		--attach stdout \
		--env REPOROOT="/${InternalRepoStem}" \
		--env REPORTDIR=${InternalReportDir} \
		--env REPORTID=${REPORTID} \
		--env REPORTDATE=${REPORTDATE} \
		--env JULIA_LOAD_PATH="/${InternalRepoStem}/misc/julia" \
		--env JULIA_ARGS="--project=/${InternalRepoStem}/misc/julia/CMSTest" \
		--volume ${ExternalReportDir}:${InternalReportDir} \
		${MAIN_REPO_IMAGE} \
		bash

# This target is the same as run-main, but against the local version of MainRepoPath.
# That is, the MainRepoPath is mapped to a read-only volume in the image.
# Note that this is likely to lead to far more failures, since no output that
# usually lives in the main repo can be created. WIP
run-main-local:
	docker run \
		--rm \
		--workdir "/Documents" \
		--volume ${MainRepoPath}:/Documents:ro \
		--tty --interactive \
		--attach stderr \
		--attach stdout \
		--env REPOROOT="/Documents" \
		--env REPORTDIR=${InternalReportDir} \
		--env REPORTID=${REPORTID}-dev \
		--env REPORTDATE=${REPORTDATE} \
		--env JULIA_LOAD_PATH="/${InternalRepoStem}/misc/julia" \
		--env JULIA_ARGS="--project=/${InternalRepoStem}/misc/julia/CMSTest" \
		--env PATH="/LocalSupportScripts:${Prepared_Image_Path}" \
		--volume ${PWD}/TestOutput:${InternalReportDir} \
		--volume ${PWD}/LocalSupportScripts:/LocalSupportScripts:ro \
		${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:prepared \
		bash

# This target cleans up generated images
cleanup-main-images:
	$(warn "$@ Unimplemented.")

# This section only exists to clean up in the case of a "bad" interruption in a process
force-cleanup: cleanup-main-images
	rmdir ${FULL_REPORT_DIR}/.LOCK || echo "${FULL_REPORT_DIR} not locked."
	rmdir ${MainRepoPath}/.LOCK || echo "${MainRepoPath} not locked."
	$(RM) Documents*.tar
	$(RM) -r ${FULL_REPORT_DIR}
endif # ExternalReportDir isempty if statement
endif # MainRepoPath isempty if statement

