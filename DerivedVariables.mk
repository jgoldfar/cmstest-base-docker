# Usage information
usage-targets: usage-targets-derivedvariables

usage-targets-derivedvariables:
	@echo ""
	@echo "    - status: Emit status information for CMSTest system."

usage-variables: usage-variables-derivedvariables
usage-variables-derivedvariables:
	@echo "    - REPORTID: revision ID to test. Default: previous revision in MainRepoPath."
# End usage information

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
# If we're currently running a process on this revision, there will be a lock
# directory here:
FULL_REPORT_LOCK_DIR:=${FULL_REPORT_DIR}/.LOCK
# TEXINPUTS is set to the value below:
Internal_TEXINPUTS:=/${InternalRepoStem}/misc/env/tex-include/Templates/:

ifeq ($(shell uname -s),Darwin)
_DATE_HR:=$(shell date -r ${REPORTDATE})
else
_DATE_HR:=$(shell date -d @${REPORTDATE})
endif

# This target just shows the make variables we would use to run a particular build,
# as well as some general status information.
.PHONY: status
status:
	@echo REPORTID: ${REPORTID}
	@echo REPORTDATE: ${REPORTDATE} "("${_DATE_HR}")"
	@echo MainRepoPath: ${MainRepoPath}
	@echo FULL_REPORT_DIR: ${FULL_REPORT_DIR}
	@[ -f "${FULL_REPORT_DIR}/stderr.log" ] \
	&& echo "REPORTID Tested: True (has stderr.log)" \
	|| echo "REPORTID Tested: False (has no stderr.log)"
	@[ -f "${FULL_REPORT_DIR}/build.log" ] \
	&& echo "REPORTID Tested: True (has build.log)" \
	|| echo "REPORTID Tested: False (has no build.log)"
	@[ -f "${FULL_REPORT_DIR}/committed" ] \
	&& echo "REPORTID Committed: True (has committed)" \
	|| echo "REPORTID Committed: False (has no committed)"
	@[ -d "${FULL_REPORT_LOCK_DIR}" ] \
	&& echo "REPORTID Test Running (Locked): True" \
	|| echo "REPORTID Test Running (Locked): False"
	@[ -d "${MainRepoLockDir}" ] \
	&& echo "MainRepo Currently Exporting (Locked): True" \
	|| echo "MainRepo Currently Exporting (Locked): False"
	@[ -d "${FULL_REPORT_DIR}" ] \
	&& echo "FULL_REPORT_DIR Contents (ls -l):" \
	&& ls -l ${FULL_REPORT_DIR} \
	|| echo "FULL_REPORT_DIR Contents: Empty"
	@[ -f "${FULL_REPORT_DIR}/build.log" ] \
	&& ( \
		echo "tail of ${FULL_REPORT_DIR}/build.log:"; \
		tail "${FULL_REPORT_DIR}/build.log" \
	) \
	|| echo "${FULL_REPORT_DIR}/build.log Missing."
	@[ -f "${FULL_REPORT_DIR}/build.log-tmp" ] \
	&& ( \
		echo "tail of ${FULL_REPORT_DIR}/build.log-tmp:"; \
		tail "${FULL_REPORT_DIR}/build.log-tmp" \
	) \
	|| echo "${FULL_REPORT_DIR}/build.log-tmp Missing."
	@$(MAKE) main-is-built > /dev/null 2>&1 \
	&& echo "MAIN_REPO_IMAGE: ${MAIN_REPO_IMAGE} (Exists)" \
	|| echo "MAIN_REPO_IMAGE: ${MAIN_REPO_IMAGE} (Missing)"
