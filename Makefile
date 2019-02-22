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
SSH_PRV_KEY_FILE?=/home/jgoldfar/.ssh/id_rsa

# Local path to updated main repository
MainRepoPath?=/Users/jgoldfar/Documents

# Local path to test output directory
ExternalReportDir?=/Users/jgoldfar/test-${Report_Repo_Branch}

# Internal path to test output directory
InternalReportDir?=/Tests

# Within the repo in MainRepoPath, we will expect to be running commands
# from this makefile.
CMSMakefile=misc/julia/CMSTest/ex/crontab/Makefile

# If FORCE_UPDATE is nonempty, we'll update over any existing changes.
FORCE_UPDATE?=

# Generic usage string. Use Make's subst command to interpolate the target.
USAGE_STRING:="Usage: make __tmp__ MainRepoPath=/path/to/Documents ExternalReportDir=/path/to/testdir"
## End Configurable Variables


## Start main set of targets
usage:
	@echo $(subst __tmp__,[TARGET],${USAGE_STRING})


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

prepared: build-prepared push-prepared


##
# "Main" image build and test run
# We first test if MainRepoPath isempty; if so, emit a usage message and bail.
ifeq ($(MainRepoPath),)
build-main:
	@echo $(subst __tmp__,$@,${USAGE_STRING})
	exit 1

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
# The repository will be generated into a directory with the name below:
REPO_OUTPUT_PATH:=${PWD}/${InternalRepoStem}
# We'll generate test output into the directory below:
FULL_REPORT_DIR:=${ExternalReportDir}/${REPORTID}
# TEXINPUTS is set to the value below:
Internal_TEXINPUTS:=/${InternalRepoStem}/misc/env/tex-include/Templates/:

# This target just shows the make variables we would use to run a particular build,
# as well as some general status information.
status:
	@echo REPORTID: ${REPORTID}
	@echo REPORTDATE: ${REPORTDATE} "("$(shell date -d "@${REPORTDATE}")")"
	@echo MainRepoPath: ${MainRepoPath}
	@echo FULL_REPORT_DIR: ${FULL_REPORT_DIR}
	@$(MAKE) main-is-built > /dev/null 2>&1 \
	&& echo "MAIN_REPO_IMAGE: ${MAIN_REPO_IMAGE} (Exists)" \
	|| echo "MAIN_REPO_IMAGE: ${MAIN_REPO_IMAGE} (Missing)"
	@[ -f "${FULL_REPORT_DIR}/stderr.log" ] \
	&& echo "REPORTID Tested: True (has stderr.log)" \
	|| echo "REPORTID Tested: False (has no stderr.log)"
	@[ -f "${FULL_REPORT_DIR}/build.log" ] \
	&& echo "REPORTID Tested: True (has build.log)" \
	|| echo "REPORTID Tested: False (has no build.log)"
	@[ -f "${FULL_REPORT_DIR}/committed" ] \
	&& echo "REPORTID Committed: True (has committed)" \
	|| echo "REPORTID Committed: False (has no committed)"
	@[ -d "${FULL_REPORT_DIR}/.LOCK" ] \
	&& echo "REPORTID Test Running (Locked): True" \
	|| echo "REPORTID Test Running (Locked): False"
	@[ -d "${MainRepoPath}/.LOCK" ] \
	&& echo "MainRepo Currently Exporting (Locked): True" \
	|| echo "MainRepo Currently Exporting (Locked): False"
	@[ -d "${FULL_REPORT_DIR}" ] \
	&& echo "FULL_REPORT_DIR Contents (ls -l):" \
	&& ls -l ${FULL_REPORT_DIR} \
	|| echo "FULL_REPORT_DIR Contents: Empty"

# Build an image containing a snapshot of ${MainRepoPath} at the given REPORTID
# NOTE The generated directory name must match the directory under `/` that we will
# be running the generated tests from. This is enforced by generating the files
# into $(notdir ${InternalRepoStem}).
# Note on this output format choice:
#     Tested raw files, tar, tgz, and zip, and tarballs are fastest to generate.
#     However, this isn't the end of the story: tarball generation seems highly
#     variables, despite it running what seems a deterministic process.
#     Creating a tarball takes anywhere between 10s and 40s, while creating a
#     "clean" archive directory tends to take ~18s each time. Seems like a worth-
#     while tradeoff to sometimes pay the higher price to export raw files; we
#     could have a builder that extracts the repo to a tagged subdirectory of this
#     one at some point on the future.
build-main: Dockerfile.main ${REPO_OUTPUT_PATH}
	[ ! -d "${MainRepoPath}/.LOCK" ]
	@echo "Building ${MAIN_REPO_IMAGE} with $<. Contents:"
	cat $<
	docker build \
		--no-cache \
		-f $< \
		-t ${MAIN_REPO_IMAGE} .
	$(RM) -r ${REPO_OUTPUT_PATH}

${REPO_OUTPUT_PATH}:
	[ ! -d "${MainRepoPath}/.LOCK" ]
	mkdir "${MainRepoPath}/.LOCK" \
	&& hg archive \
		--time \
		--cwd "${MainRepoPath}" \
		--rev ${REPORTID} \
		--subrepos \
		--verbose \
		--exclude "ugrad/climate dynamics/" \
		"$@" \
	|| (ret=$$?; rmdir "${MainRepoPath}/.LOCK" && exit $$ret)
	rmdir "${MainRepoPath}/.LOCK"

# The dockerfile used to generate the main image is minimal; we just import the repository
# files and set the working directory to the correct location.
# NOTE: InternalRepoStem and the name of the tarball have to be kept in sync as
# above.
Dockerfile.main: Makefile
	@echo "FROM ${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:prepared" > $@
	@echo "" >> $@
	@echo "MAINTAINER Jonathan Goldfarb <jgoldfar@gmail.com>" >> $@
	@echo "" >> $@
	@echo "ADD ./${InternalRepoStem} /${InternalRepoStem}" >> $@
	@echo "" >> $@
	@echo "RUN chown -R ${USERINFO} /${InternalRepoStem} \\" >> $@
	@echo "    && make -C ${InternalRepoStem}/misc/env/bin latex/.chktexrc LATEX_TEMPLATE_INSTALL_ROOT=/${InternalRepoStem}" >> $@
	@echo "" >> $@
	@echo "ENV TEXINPUTS=\"${Internal_TEXINPUTS}\" \\" >> $@
	@echo "    REPOROOT=\"/${InternalRepoStem}\" \\" >> $@
	@echo "    CHKTEXRC=\"${InternalRepoStem}/misc/env/bin/latex/.chktexrc\" \\" >> $@
	@echo "    REPORTDIR=\"${InternalReportDir}\" \\" >> $@
	@echo "    REPORTID=${REPORTID} \\" >> $@
	@echo "    REPORTDATE=${REPORTDATE} \\" >> $@
	@echo "    JULIA_LOAD_PATH=\"/${InternalRepoStem}/misc/julia\" \\" >> $@
	@echo "    JULIA_ARGS=\"--project=/${InternalRepoStem}/misc/julia/CMSTest\"" >> $@
	@echo "" >> $@
	@echo "WORKDIR /${InternalRepoStem}" >> $@

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
	&& ${REPO_UPDATE_CMD} \
	|| (ret=$$?; rmdir "${MainRepoPath}/.LOCK" && exit $$ret)
	rmdir "${MainRepoPath}/.LOCK"

force-clean-main-repo:
	[ -d "${MainRepoPath}/.LOCK" ] && rmdir "${MainRepoPath}/.LOCK"
	cd "${MainRepoPath}" \
	&& hg update --clean

##
# Check that ExternalReportDir isempty, MainRepoPath is not empty
# If so, emit a usage message for test-main and push-test-main (which
# cannot run in this situation.)
ifeq ($(ExternalReportDir),)
test-main:
	@echo $(subst __tmp__,$@,${USAGE_STRING})
	exit 1

push-test-main:
	@echo $(subst __tmp__,$@,${USAGE_STRING})
	exit 1

run-main:
	@echo $(subst __tmp__,$@,${USAGE_STRING})
	exit 1

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
	date
	mkdir "${FULL_REPORT_DIR}/.LOCK" \
	&& docker run \
		--rm \
		--tty \
		--user ${USERINFO} \
		--attach stderr \
		--attach stdout \
		--volume ${ExternalReportDir}:${InternalReportDir} \
		${MAIN_REPO_IMAGE} \
		make -f ${CMSMakefile} \
		instantiate show-hg-info runtests-all \
		VERBOSE=true \
	|| (ret=$$?; rmdir "${FULL_REPORT_DIR}/.LOCK" && exit $$ret)
	rmdir "${FULL_REPORT_DIR}/.LOCK"
	date

# test-main is a shorter spelling of the above target.
.PHONY: test-main
test-main: ${FULL_REPORT_DIR}/stderr.log

# Capture the PATH variable from the "Prepared" image
Prepared_Image_Path:=$(shell docker run --attach stdout --volume ${PWD}/LocalSupportScripts:/LocalSupportScripts ${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:prepared /LocalSupportScripts/echo-path)

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
		--user ${USERINFO} \
		--attach stderr \
		--attach stdout \
		--env REPOROOT="/Documents" \
		--env REPORTID=${REPORTID}-dev \
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
# into a logfile. We save the logfile to a temporary file
${FULL_REPORT_DIR}/build.log:
	mkdir -p "${FULL_REPORT_DIR}"
	$(MAKE) test-main > "$@-tmp" 2>&1 || $(RM) "$@-tmp"
	[ -f "$@-tmp" ] && mv $@-tmp $@

# really-test-main is a shorter spelling of the above target.
really-test-main: ${FULL_REPORT_DIR}/build.log

# To commit and push tests, we need the ${ExternalReportDir} to be initialized
# to the correct git repository.
${ExternalReportDir}/.git:
	git clone git@bitbucket.org:jgoldfar/jgoldfar-cms-testresults.git $(dir $<)
	cd $(dir $<) \
	&& git config user.name "IWS-Docker-${DOCKER_USERNAME}" \
	&& git checkout -b ${Report_Repo_Branch} --track origin/${Report_Repo_Branch}

pull-reportdir: ${ExternalReportDir}/.git
	cd $(dir $<) \
	&& git pull --rebase

push-reportdir: ${ExternalReportDir}/.git
	cd $(dir $<) \
	&& git push -u origin ${Report_Repo_Branch}

# This target summarizes the test results and commits updated data to the
# ${ExternalReportDir} git repository. As a part of that, we emit a lock
# in the corresponding directory so existing test or report generation routines
# are not interrupted.
${FULL_REPORT_DIR}/committed: ${FULL_REPORT_DIR}/build.log ${ExternalReportDir}/.git
	$(MAKE) main-is-built || $(MAKE) build-main
	$(MAKE) pull-reportdir || echo "Pull failed."
	[ ! -d "${FULL_REPORT_DIR}/.LOCK" ]
	date
	mkdir "${FULL_REPORT_DIR}/.LOCK" \
	&& docker run \
		--rm \
		--tty \
		--user ${USERINFO} \
		--attach stderr \
		--attach stdout \
		--volume ${ExternalReportDir}:${InternalReportDir} \
		${MAIN_REPO_IMAGE} \
		make -f ${CMSMakefile} \
		instantiate generate-summaries update-test-readme record-summaries \
		VERBOSE=true NOPUSH=true NOPULL=true \
	|| (ret=$$?; rmdir "${FULL_REPORT_DIR}/.LOCK" && exit $$ret)
	rmdir "${FULL_REPORT_DIR}/.LOCK"
	date
	$(MAKE) push-reportdir || echo "Push failed."

# This is a shorter spelling of the above target.
# We don't try to run this target if the file exists (irrespective of timestamp)
# Because of timing issues, we may have a situation where this file exists, but
# doesn't "seem" new.
record-test-main: $(if $(wildcard ${FULL_REPORT_DIR}/committed),,${FULL_REPORT_DIR}/committed)

# This target allows you to drop into the built image corresponding to a given REPORTID
# to debug test failures.
run-main:
	$(MAKE) main-is-built || $(MAKE) build-main
	docker run \
		--rm \
		--tty --interactive \
		--user ${USERINFO} \
		--attach stderr \
		--attach stdout \
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
		--user ${USERINFO} \
		--attach stderr \
		--attach stdout \
		--env REPOROOT="/Documents" \
		--env REPORTID=${REPORTID}-dev \
		--env JULIA_LOAD_PATH="/Documents/misc/julia" \
		--env JULIA_ARGS="--project=/Documents/misc/julia/CMSTest" \
		--env PATH="/LocalSupportScripts:${Prepared_Image_Path}" \
		--volume ${PWD}/TestOutput:${InternalReportDir} \
		--volume ${PWD}/LocalSupportScripts:/LocalSupportScripts:ro \
		${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:prepared \
		bash

# This section only exists to clean up in the case of a "bad" interruption in a process
remove-locks:
	rmdir ${FULL_REPORT_DIR}/.LOCK || echo "${FULL_REPORT_DIR} not locked."
	rmdir ${MainRepoPath}/.LOCK || echo "${MainRepoPath} not locked."

force-cleanup: remove-locks cleanup-main-images
	$(RM) -r ${FULL_REPORT_DIR}

endif # ExternalReportDir isempty if statement
endif # MainRepoPath isempty if statement

# This target cleans up generated images
cleanup-all-images:
	docker rmi $(shell docker images --all --format "{{.Repository}}:{{.Tag}}" | grep '${DOCKER_REPO_BASE}') || echo "No images to remove."
	docker system prune --force --volumes

cleanup-main-images:
	docker rmi $(shell docker images --all --format "{{.Repository}}:{{.Tag}}" | grep '${DOCKER_REPO_BASE}:main') || echo "No images to remove."
	docker system prune --force --volumes

# Generic (safe) clean target
clean: cleanup-main-images
	$(RM) Documents*.tar
