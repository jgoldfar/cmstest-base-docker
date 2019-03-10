# Usage information
usage-targets: usage-targets-dockerbasebuild

usage-targets-dockerbasebuild:
	@echo ""
	@echo "    - build-prepared: Build ${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:prepared"
	@echo "    - push-prepared: Push ${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:prepared to Docker Hub"

usage-variables: usage-variables-dockerbasebuild
usage-variables-dockerbasebuild:
## End usage information

##
# "Prepared" image build
build-prepared: Dockerfile.prepared
	docker build \
		-f $< \
		-t ${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:prepared .

push-prepared:
	docker push ${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:prepared

.PHONY: prepared build-prepared push-prepared
prepared: build-prepared push-prepared

