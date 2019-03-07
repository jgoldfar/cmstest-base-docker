# Usage information
usage-targets: usage-targets-runtests

usage-targets-runtests:
	@echo ""
	@echo "    - test-main: Run tests into ${FULL_REPORT_DIR}"
	@echo "    - test-main-local: Run tests for ${MainRepoPath} as a read-only volume into TestOutput."
	@echo "    - really-test-main: Run test-main while also saving stderr/stdout into a logfile."
	@echo "    - {pull,push}-reportdir: Pull or push results from ${ExternalReportDir}."
	@echo "    - record-test-main: Generate summary information and record to repository after test-main completes."
	@echo "    - pull-test-and-record: Orchestrate entire test sequence: pull, test, record."
	@echo "    - run-main: Start bash shell in latest main image. Run with RUN_MAIN_AS_ROOT=true to run as root."

usage-variables: usage-variables-runtests
usage-variables-runtests:
## End usage information

# This target runs tests. As part of that, it creates a lockfile in the report directory,
# so only one such set of tests will be run.
${FULL_REPORT_DIR}/stderr.log:
	$(MAKE) main-is-built || $(MAKE) build-main
	mkdir -p ${FULL_REPORT_DIR}
	@[ ! -d "${FULL_REPORT_LOCK_DIR}" ] || ( echo "${FULL_REPORT_DIR} Locked. Bailing" ; exit 1 )
	date
	mkdir "${FULL_REPORT_LOCK_DIR}" \
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
	|| (ret=$$?; rmdir "${FULL_REPORT_LOCK_DIR}" && exit $$ret)
	rmdir "${FULL_REPORT_LOCK_DIR}"
	date

# test-main is a shorter spelling of the above target.
.PHONY: test-main
test-main:
	@( [ ! -z "${FORCE_UPDATE}" ] && $(RM) ${FULL_REPORT_DIR}/*.log ) || exit 0
	@[ ! -f "${FULL_REPORT_DIR}/stderr.log" ] || ( \
		echo "Test results exist in ${FULL_REPORT_DIR}. Bailing." ; \
		echo "Run make with FORCE_UPDATE=true to override." ; \
		exit 1 \
	)
	$(MAKE) ${FULL_REPORT_DIR}/stderr.log

# Command to capture the PATH variable from the "Prepared" image
Prepared_Image_Path_Command:=docker run --attach stdout --volume ${PWD}/LocalSupportScripts:/LocalSupportScripts ${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:prepared /LocalSupportScripts/echo-path

# This target runs the same test suite against the repository as it currently
# exists. The MainRepoPath is mapped to a read-only volume in the image.
# Note that this is likely to lead to far more failures, since no output that
# usually lives in the main repo can be created. WIP
${PWD}/TestOutput/stderr.log:
	Prepared_Image_Path=$(shell ${Prepared_Image_Path_Command}) && \
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
		--env PATH="/LocalSupportScripts:$${Prepared_Image_Path}" \
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
	@( [ ! -z "${FORCE_UPDATE}" ] && $(RM) $@-tmp ) || exit 0
	@[ ! -f "$@-tmp" ] || ( echo "Previous temporary output $@-tmp exists. Bailing"; exit 1 )
	date > "$@-tmp"
	$(MAKE) test-main >> "$@-tmp" 2>&1
	date >> "$@-tmp"
	@( [ -f "$@-tmp" ] && mv $@-tmp $@ ) || ( echo "Creation of temporary output failed. Check logfiles." ; exit 1 )

# really-test-main is a shorter spelling of the above target.
really-test-main:
	@[ ! -z "${FORCE_UPDATE}" ] && $(RM) "${FULL_REPORT_DIR}/build.log" || exit 0
	@[ ! -f "${FULL_REPORT_DIR}/build.log" ] ||	( \
			echo "Previous output ${FULL_REPORT_DIR}/build.log exists. Bailing." ; \
			echo "Run make with FORCE_UPDATE=true to override." ; \
			exit 1 ; \
		)
	$(MAKE) ${FULL_REPORT_DIR}/build.log

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
	@[ -z "${FORCE_UPDATE}" ] && ( \
		$(MAKE) pull-reportdir || ( echo "Pull ${ExternalReportDir} failed." ; exit 1	) \
	) || exit 0
	@[ ! -d "${FULL_REPORT_LOCK_DIR}" ] || ( echo "${FULL_REPORT_DIR} Locked. Bailing." ; exit 1 )
	date
	mkdir "${FULL_REPORT_LOCK_DIR}" \
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
	|| (ret=$$?; rmdir "${FULL_REPORT_LOCK_DIR}" && exit $$ret)
	rmdir "${FULL_REPORT_LOCK_DIR}"
	date
	@[ -z "${FORCE_UPDATE}" ] && ( \
		$(MAKE) push-reportdir || ( echo "Push ${ExternalReportDir} failed."; exit 1 ) \
	) || exit 0

# This is a shorter spelling of the above target.
# We don't try to run this target if the file exists (irrespective of timestamp)
# Because of timing issues, we may have a situation where this file exists, but
# doesn't "seem" new.
record-test-main:
	@( [ ! -z "${FORCE_UPDATE}" ] && $(RM) "${FULL_REPORT_DIR}/committed" ) || exit 0
	@[ ! -f "${FULL_REPORT_DIR}/committed" ] || ( \
		echo "Results in ${FULL_REPORT_DIR} exist. Bailing." ; \
		echo "Run make with FORCE_UPDATE=true to override." ; \
		exit 1 ; \
	)
	$(MAKE) ${FULL_REPORT_DIR}/committed

# This target wraps the pull, test, and record-test targets to simplify calling
# this makefile from cron
pull-test-and-record:
	[ ! -d "${FULL_REPORT_LOCK_DIR}" ]
	$(MAKE) record-test-main || exit 0
	[ ! -d "${MainRepoLockDir}" ]
	$(MAKE) maybe-update-main-repo
	$(MAKE) really-test-main
	$(MAKE) record-test-main

# This target allows you to drop into the built image corresponding to a given REPORTID
# to debug test failures.
# To install packages, set RUN_MAIN_AS_ROOT to be nonempty
RUN_MAIN_AS_ROOT?=
run-main:
	$(MAKE) main-is-built || $(MAKE) build-main
	docker run \
		--rm \
		--tty --interactive \
		$(shell [ ! -z "${RUN_MAIN_AS_ROOT}" ] || echo "--user ${USERINFO}" ) \
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
	@[ ! -d "${MainRepoLockDir}" ] || ( echo "${MainRepoPath} Locked. Bailing." ; exit 1 )
	mkdir "${MainRepoLockDir}"
	Prepared_Image_Path=$(shell ${Prepared_Image_Path_Command}) && \
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
		--env PATH="/LocalSupportScripts:$${Prepared_Image_Path}" \
		--volume ${PWD}/TestOutput:${InternalReportDir} \
		--volume ${PWD}/LocalSupportScripts:/LocalSupportScripts:ro \
		${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:prepared \
		bash \
	|| exit 0
	rmdir "${MainRepoLockDir}"
