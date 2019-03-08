# Usage information
usage-targets: usage-targets-dockerbasebuild

usage-targets-dockerbasebuild:
	@echo ""
	@echo "    - build-base: Build ${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:base"
	@echo "    - push-base: Push ${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:base to Docker Hub"
	@echo "    - build-prepared: Build ${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:prepared"
	@echo "    - push-prepared: Push ${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:prepared to Docker Hub"

usage-variables: usage-variables-dockerbasebuild
usage-variables-dockerbasebuild:
## End usage information

##
# "Base" image build
build-base: Dockerfile.base
	docker build \
		-f $< \
		-t ${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:base .

push-base: build-base
	docker push ${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:base

.PHONY: base build-base push-base
base: build-base push-base


##
# "Prepared" image build
build-prepared: Dockerfile.prepared
	docker build \
		-f $< \
		--build-arg ssh_prv_key="`cat $(SSH_PRV_KEY_FILE)`" \
		-t ${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:prepared .

.PHONY: prepared build-prepared push-prepared
prepared: build-prepared push-prepared

