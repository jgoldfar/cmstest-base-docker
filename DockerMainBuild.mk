# Usage information
usage-targets: usage-targets-dockermainbuild

usage-targets-dockermainbuild:
	@echo ""
	@echo "    - build-main: Export ${MainRepoPath} and create corresponding Docker image."
	@echo "    - main-is-built: Check if current revision's Docker image is built."

usage-variables: usage-variables-dockermainbuild
usage-variables-dockermainbuild:
## End usage information

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
.PHONY: build-main
build-main: Dockerfile.main ${REPO_OUTPUT_PATH} ${SSH_PRV_KEY_FILE}
	@[ ! -d "${MainRepoLockDir}" ] || ( echo "${MainRepoPath} Locked. Bailing." ; exit 1 )
	@echo "Building ${MAIN_REPO_IMAGE} with $<. Contents:"
	@cat $<
	cp ${SSH_PRV_KEY_FILE} ./id_rsa
	docker build \
		--no-cache \
		-f $< \
		-t ${MAIN_REPO_IMAGE} .
	$(RM) -r ${REPO_OUTPUT_PATH} ./id_rsa

push-main:
	$(MAKE) main-is-built || ( echo "Main image not yet successfully built. Bailing." ; exit 1)
	docker tag ${MAIN_REPO_IMAGE} ${MAIN_REPO_IMAGE_PRIVATE}
	docker push ${MAIN_REPO_IMAGE_PRIVATE}

.DELETE_ON_ERROR: ${REPO_OUTPUT_PATH}
${REPO_OUTPUT_PATH}:
	@[ ! -d "${MainRepoLockDir}" ] || ( echo "${MainRepoPath} Locked. Bailing." ; exit 2 )
	mkdir "${MainRepoLockDir}" \
	&& hg archive \
		--time \
		--cwd "${MainRepoPath}" \
		--rev ${REPORTID} \
		--subrepos \
		--verbose \
		--exclude "ugrad/climate dynamics/" \
		"$@" \
	|| (ret=$$?; rmdir "${MainRepoLockDir}" && exit $$ret)
	rmdir "${MainRepoLockDir}"

# The dockerfile used to generate the main image is minimal; we just import the repository
# files and set the working directory to the correct location.
# NOTE: InternalRepoStem and the name of the tarball have to be kept in sync as
# above.
.DELETE_ON_ERROR: Dockerfile.main
.INTERMEDIATE: Dockerfile.main
Dockerfile.main: Makefile DockerMainBuild.mk
	@echo "FROM ${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:prepared" > $@
	@echo "" >> $@
	@echo "MAINTAINER Jonathan Goldfarb <jgoldfar@gmail.com>" >> $@
	@echo "" >> $@
	@echo "ADD ./${InternalRepoStem} /${InternalRepoStem}" >> $@
	@echo "ADD ./id_rsa /id_rsa" >> $@
	@echo "" >> $@
	@echo " Setup some environment/platform-specific configuration files" > /dev/null
	@echo "RUN chown -R ${USERINFO} /${InternalRepoStem} \\" >> $@
	@echo "    && make -C /${InternalRepoStem}/misc/env/bin latex/.chktexrc LATEX_TEMPLATE_INSTALL_ROOT=/${InternalRepoStem} \\" >> $@
	@echo "    && make -C /${InternalRepoStem}/misc/env/bin latex/.latexmkrc LATEX_TEMPLATE_INSTALL_ROOT=/${InternalRepoStem} \\" >> $@
	@echo " Setup git repositories to ship along with CMS" > /dev/null
	@echo "    && apt-get -qq update \\" >> $@
	@echo "    && apt-get -qq -y --no-install-recommends install openssh-client \\" >> $@
	@echo "    && make -C /${InternalRepoStem} -f /${InternalRepoStem}/misc/env/pkglists/gitproj.makefile setup IdentityFileCopy=/id_rsa \\" >> $@
	@echo "    && make -C /${InternalRepoStem} -f /${InternalRepoStem}/misc/env/pkglists/gitproj.makefile cloneAll \\" >> $@
	@echo " Cleanup afterwards" > /dev/null
	@echo "    && rm -rf /id_rsa /root/.ssh \\" >> $@
	@echo "    && apt-get -qq -y remove openssh-client \\" >> $@
	@echo "    && apt-get -qq -y autoremove \\" >> $@
	@echo "    && apt-get autoclean \\" >> $@
	@echo "    && rm -rf /var/lib/apt/lists/* /var/log/dpkg.log" >> $@
	@echo "" >> $@
	@echo "ENV TEXINPUTS=\"${Internal_TEXINPUTS}\" \\" >> $@
	@echo "    REPOROOT=\"/${InternalRepoStem}\" \\" >> $@
	@echo "    CHKTEXRC=\"/${InternalRepoStem}/misc/env/bin/latex/.chktexrc\" \\" >> $@
	@echo "    LATEXMKRCSYS=\"/${InternalRepoStem}/misc/env/bin/latex/.latexmkrc\" \\" >> $@
	@echo "    REPORTDIR=\"${InternalReportDir}\" \\" >> $@
	@echo "    REPORTID=${REPORTID} \\" >> $@
	@echo "    REPORTDATE=${REPORTDATE} \\" >> $@
	@echo "    JULIA_LOAD_PATH=\"/${InternalRepoStem}/misc/julia\" \\" >> $@
	@echo "    JULIA_ARGS=\"--project=/${InternalRepoStem}/misc/julia/CMSTest\" \\" >> $@
	@echo "    CMSTEST_CI=true" >> $@
	@echo "" >> $@
	@echo "WORKDIR /${InternalRepoStem}" >> $@

# This target will fail if the main image isn't yet built.
.PHONY: main-is-built
main-is-built:
	docker inspect ${MAIN_REPO_IMAGE} > /dev/null 2>&1

