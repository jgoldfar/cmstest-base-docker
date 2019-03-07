# Usage information
usage-targets: usage-targets-repomanagement

usage-targets-repomanagement:
	@echo ""
	@echo "    - maybe-update-main-repo: Update ${MainRepoPath} if not locked."
	@echo "    - force-clean-main-repo: Update ${MainRepoPath} without checking for locks."

usage-variables: usage-variables-repomanagement
usage-variables-repomanagement:
# End usage information

# Carefully pull and update the main repository
.PHONY: maybe-update-main-repo
REPO_UPDATE_CMD:=hg update --clean
maybe-update-main-repo:
	@[ ! -d "${MainRepoLockDir}" ] || ( echo "${MainRepoPath} Locked. Bailing." ; exit 3 )
	mkdir "${MainRepoLockDir}" \
	&& cd "${MainRepoPath}" \
	&& hg status -mard \
	&& hg pull \
	&& ${REPO_UPDATE_CMD} \
	|| (ret=$$?; rmdir "${MainRepoLockDir}" && exit $$ret)
	rmdir "${MainRepoLockDir}"

# Remove locks before trying above target
.PHONY: force-clean-main-repo
force-clean-main-repo:
	@( [ -d "${MainRepoLockDir}" ] && rmdir "${MainRepoLockDir}" ) || exit 0
	$(MAKE) maybe-update-main-repo
