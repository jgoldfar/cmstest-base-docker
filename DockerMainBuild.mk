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
build-main: Dockerfile.main ${REPO_OUTPUT_PATH}
	@[ ! -d "${MainRepoLockDir}" ] || ( echo "${MainRepoPath} Locked. Bailing." ; exit 1 )
	@echo "Building ${MAIN_REPO_IMAGE} with $<. Contents:"
	@cat $<
	docker build \
		--no-cache \
		-f $< \
		-t ${MAIN_REPO_IMAGE} .
	$(RM) -r ${REPO_OUTPUT_PATH}

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
Dockerfile.main: Makefile
	@echo "FROM ${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:prepared" > $@
	@echo "" >> $@
	@echo "MAINTAINER Jonathan Goldfarb <jgoldfar@gmail.com>" >> $@
	@echo "" >> $@
	@echo "ADD ./${InternalRepoStem} /${InternalRepoStem}" >> $@
	@echo "" >> $@
	@echo "RUN chown -R ${USERINFO} /${InternalRepoStem} \\" >> $@
	@echo "    && make -C /${InternalRepoStem}/misc/env/bin latex/.chktexrc LATEX_TEMPLATE_INSTALL_ROOT=/${InternalRepoStem}" >> $@
	@echo "" >> $@
	@echo "ENV TEXINPUTS=\"${Internal_TEXINPUTS}\" \\" >> $@
	@echo "    REPOROOT=\"/${InternalRepoStem}\" \\" >> $@
	@echo "    CHKTEXRC=\"/${InternalRepoStem}/misc/env/bin/latex/.chktexrc\" \\" >> $@
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

