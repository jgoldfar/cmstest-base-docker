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

.PHONY: force-clean-main-repo
force-clean-main-repo:
	@( [ -d "${MainRepoLockDir}" ] && rmdir "${MainRepoLockDir}" ) || exit 0
	$(MAKE) maybe-update-main-repo
