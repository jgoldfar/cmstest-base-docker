# This section only exists to clean up in the case of a "bad" interruption in a process
remove-locks:
	@( [ -d "${FULL_REPORT_LOCK_DIR}" ] && rmdir ${FULL_REPORT_LOCK_DIR} ) || echo "${FULL_REPORT_DIR} not locked."
	@( [ -d "${MainRepoLockDir}" ] && rmdir "${MainRepoLockDir}" ) || echo "${MainRepoPath} not locked."

force-cleanup: remove-locks cleanup-main-images
	$(RM) -r ${FULL_REPORT_DIR}

# This target cleans up generated images. We check if the list is empty to avoid
# calling docker rmi with an empty argument.
cleanup-all-images:
	( \
		imagesToRemove="$(shell docker images --all --format "{{.Repository}}:{{.Tag}}" | grep '${DOCKER_REPO_BASE}')" ; \
		[ -z "$${imagesToRemove}" ] && echo "No images to remove" || docker rmi $${imagesToRemove} \
	)
	docker system prune --force --volumes

cleanup-main-images:
	( \
		imagesToRemove="$(shell docker images --all --format "{{.Repository}}:{{.Tag}}" | grep '${DOCKER_REPO_BASE}:main')" ; \
		[ -z "$${imagesToRemove}" ] && echo "No images to remove" || docker rmi $${imagesToRemove} \
	)
	docker system prune --force --volumes

# Generic (safe) clean target
clean: cleanup-main-images
	$(RM) ${PWD}/Documents-*
