#!/bin/bash
set -euxo pipefail

# Change ownership in GitLab CI because runner always runs as root
# See https://gitlab.com/gitlab-org/gitlab-runner/-/issues/2750
if [[ "${CI_PROJECT_DIR+is_set}" == is_set ]];
then 
	sudo chown -R flutter:flutter $CI_PROJECT_DIR
fi

exec "$@"
