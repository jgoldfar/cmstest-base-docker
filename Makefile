HG?=$(shell which hg)

DOCKER_USERNAME?=jgoldfar
DOCKER_REPO_BASE:=cms-test-image

# Local path to SSH key authenticated to Github and Bitbucket
SSH_PRV_KEY_FILE?=/home/jgoldfar/.ssh/id_rsa

# Local path to updated main repository
MainRepoPath?=/Users/jgoldfar/Documents
# Local path to test output directory
ExternalReportDir?=/Users/jgoldfar/test-$(shell uname -s)

# Internal path to main repository
InternalRepoDir?=/Documents
# Internal path to test output directory
InternalReportDir?=/Tests


usage:
	$(error "Usage Not Yet Defined")

build-%: Dockerfile.%
	docker build -f $< -t ${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:$* .

push-%: build-%
	docker push ${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:$*

base: build-base push-base

# "Prepared" image build
build-prepared: Dockerfile.prepared
	docker build -f $< --build-arg ssh_prv_key="`cat $(SSH_PRV_KEY_FILE)`" -t ${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:prepared .

prepared: build-prepared push-prepared

# "Main" image build and test run
ifeq ($(MainRepoPath),) # MainRepoPath is empty
build-main:
	$(error "Usage: make $@ MainRepoPath=/path/to/Documents")

# REPORTID is not defined if MainRepoPath is not
REPORTID:=

else # MainRepoPath is not empty
build-main: Dockerfile.main
	docker build --no-cache -f $< -t ${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:main $(MainRepoPath)

Dockerfile.main: Makefile
	echo "FROM ${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:prepared" > $@
	echo "MAINTAINER Jonathan Goldfarb <jgoldfar@gmail.com>" >> $@
	echo "WORKDIR ${InternalRepoDir}" >> $@
	echo "COPY . ." >> $@

# Derive REPORTID from HG node hash from MainRepoPath
REPORTID:= $(shell $(HG) log --cwd $(MainRepoPath) -l 1 -T '{node}')
ifeq ($(ExternalReportDir),) # ExternalReportDir isempty
test-main:
	@echo "Usage: make $@ MainRepoPath=/path/to/documents ExternalReportDir=/path/to/testdir"

else # ExternalReportDir is not empty
CMSMakefile=misc/julia/CMSTest/ex/crontab/Makefile
test-main:
	mkdir -p ${ExternalReportDir}/${REPORTID}
	docker run \
		--tty \
		--attach stderr \
		--attach stdout \
		--env REPOROOT=${InternalRepoDir} \
		--env REPORTDIR=${InternalReportDir} \
		--env REPORTID=${REPORTID} \
		--env JULIA_LOAD_PATH=${InternalRepoDir}/misc/julia \
		--env JULIA_ARGS="--project=${InternalRepoDir}/misc/julia/CMSTest" \
		--volume ${ExternalReportDir}:${InternalReportDir} \
		${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:main \
		make -f ${CMSMakefile} \
		instantiate check-not-tested lock test release-lock \
		VERBOSE=true

push-test-main:
	docker run \
		--tty \
		--attach stderr \
		--attach stdout \
		--env REPOROOT=${InternalRepoDir} \
		--env REPORTDIR=${InternalReportDir} \
		--env REPORTID=${REPORTID} \
		--env JULIA_LOAD_PATH=${InternalRepoDir}/misc/julia \
		--env JULIA_ARGS="--project=${InternalRepoDir}/misc/julia/CMSTest" \
		--volume ${ExternalReportDir}:${InternalReportDir} \
		${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:main \
		make -f ${CMSMakefile} \
		check-tested generate-summaries update-test-readme record-summaries \
		VERBOSE=true
endif # ExternalReportDir isempty if statement
endif # MainRepoPath isempty if statement

run-main:
	docker run \
		--tty --interactive \
		--attach stderr \
		--attach stdout \
		--env REPOROOT=${InternalRepoDir} \
		--env REPORTDIR=${InternalReportDir} \
		--env REPORTID=${REPORTID} \
		--env JULIA_LOAD_PATH=${InternalRepoDir}/misc/julia \
		--env JULIA_ARGS="--project=${InternalRepoDir}/misc/julia/CMSTest" \
		${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:main \
		bash
