DOCKER_USERNAME?=jgoldfar
DOCKER_REPO_BASE:="cms-test-image"

build-%: Dockerfile.%
	docker build -f Dockerfile.$* -t ${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:$* .

push-%: build-%
	docker push ${DOCKER_USERNAME}/${DOCKER_REPO_BASE}:$*

base: build-base push-base

prepared: build-prepared push-prepared

MainRepoPath?=
ifeq ($(MainRepoPath),) # MainRepoPath is empty
main:

else # MainRepoPath is not empty

endif # MainRepoPath isempty if statement
