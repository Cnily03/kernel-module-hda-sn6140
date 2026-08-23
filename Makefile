# SPDX-License-Identifier: GPL-2.0-or-later

.PHONY: build offline status check help

build:
	./scripts/build.sh

offline:
	./scripts/build.sh --offline

status:
	./scripts/manage.sh status

check:
	bash -n scripts/build.sh
	bash -n scripts/manage.sh
	sh -n scripts/collect-sn6140.sh

help:
	@printf '%s\n' \
	  'make build    - verify sources and build one module for uname -r' \
	  'make offline  - rebuild using the existing cache only' \
	  'make status   - read-only selected/loaded/artifact comparison' \
	  'make check    - shell syntax checks; never installs anything'
