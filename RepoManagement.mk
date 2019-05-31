# Usage information
usage-targets: usage-targets-repomanagement

usage-targets-repomanagement:
	@echo ""
	@echo "    - maybe-update-main-repo: Update ${MainRepoPath} if not locked."
	@echo "    - force-clean-main-repo: Update ${MainRepoPath} without checking for locks."
	@echo "    - initialize-main-repo: Clone remote ${MainRepoRemote} to ${MainRepoPath}."
	@echo "    - initialize-crontab: Initialize crontab to run tests regularly."
	@echo "    - initialize-main-repo-deps: Ensure necessary dependencies for this package are installed."

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

${SSH_PRV_KEY_FILE}:
	ssh-keygen -t rsa -b 4090 -C "${USER_EMAIL}" -N "" -f $@

# Necessary apt packages for this software to work
INITIALIZE_DEPS:= \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common \
    git \
    mercurial

# Install git, mercurial, and docker (the latter from instructions here: https://docs.docker.com/install/linux/docker-ce/ubuntu/)
# Make sure the repository name below matches the currently used Ubuntu version
initialize-main-repo-deps: ${SSH_PRV_KEY_FILE}
	if ! which docker; then \
		sudo apt-get update ; \
		sudo apt-get install ${INITIALIZE_DEPS} ; \
		curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - ; \
		sudo apt-key fingerprint 0EBFCD88 ; \
		sudo add-apt-repository \
			"deb [arch=amd64] https://download.docker.com/linux/ubuntu \
			xenial \
			stable" ; \
		sudo apt-get update ; \
		sudo apt-get install docker-ce docker-ce-cli containerd.io ; \
		sudo usermod -aG docker ${LOCAL_USERNAME} ; \
		exit 0 ;\
	else \
		echo "Dependencies already installed." ; \
		exit 0 ; \
	fi


MainRepoParentPath:=$(dir ${MainRepoPath})
initialize-main-repo: initialize-main-repo-deps
	[ ! -d "${MainRepoParentPath}"] && ( sudo mkdir -p "${MainRepoParentPath}" ) || exit 0
	sudo chown -R ${USERINFO} "${MainRepoParentPath}"
	[ ! -d ${MainRepoPath} ] && ( hg clone --rev=1 --noupdate ${MainRepoRemote} ${MainRepoPath} ) || ( echo "Path ${MainRepoPath} exists. Skipping clone."; exit 0 )
	hg pull --cwd ${MainRepoPath} --verbose
	$(MAKE) initialize-repo-recursive INIT_BASEPATH=${MainRepoPath}

INIT_BASEPATH?=
initialize-repo-recursive:
	if [ ! -d ${INIT_BASEPATH}/.hg ] ; then \
	  echo "No repository found in ${INIT_BASEPATH}." ; \
	  exit 0 ; \
	else \
	  hg pull --cwd ${INIT_BASEPATH} ; \
	  ( hg update --cwd ${INIT_BASEPATH} --clean ) && ( \
	    echo "Update in ${INIT_BASEPATH} succeeded." ; \
	  ) || ( \
	    echo "Update in ${INIT_BASEPATH} failed." ; \
	  ) ; \
	  ( hg cat -r tip --cwd ${INIT_BASEPATH} .hgsub ) || ( echo "No subrepos in ${INIT_BASEPATH}." ; exit 0 ) \
	fi

initialize-crontab:
	crontab -l > init-crontab.bak
	@echo "# Pull CMS Repository, and if new commits are to be tested, run IWS code" > init-crontab
	@echo "# test script. If errors are returned, they should end up in stderr and" >> init-crontab
	@echo "# be reported through system mail." >> init-crontab
	@echo "*/10 * * * * cd ${PWD} && date > pullIWS.log && make maybe-update-main-repo >> pullIWS.log 2>&1" >> init-crontab
	@echo "#" >> init-crontab
	@echo "*/15 * * * * cd ${PWD} && ( date > testIWS.log && make really-test-main ) >> testIWS.log 2>&1 ) && ( date > pushIWS.log && make record-test-main > pushIWS.log 2>&1 )" >> init-crontab
	@echo "#" >> init-crontab
	@echo "# Cleanup any inconsistencies on reboot" >> init-crontab
	@echo "@reboot cd ${PWD} && make force-cleanup force-clean-main-repo > cleanupIWS.log 2>&1" >> init-crontab
	echo "New crontab available in ${PWD}/init-crontab; backup saved in ${PWD}/init-crontab.bak"
	crontab init-crontab


initialization: initialize-main-repo initialize-crontab
