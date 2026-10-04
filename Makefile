# SPDX-License-Identifier: GPL-2.0-or-later

.PHONY: build offline status doctor package check help

build:
	./scripts/build.sh

offline:
	./scripts/build.sh --offline

status:
	./scripts/doctor.sh status

doctor:
	./scripts/doctor.sh check

package:
	./scripts/package.sh

check:
	@mkdir -p .work
	@for script in scripts/*.sh scripts/lib/*.sh tests/*.sh packaging/arch/dkms.conf PKGBUILD; do bash -n "$$script" || exit; done
	sh -n scripts/collect-sn6140.sh
	python3 -m unittest discover -s tests -v

help:
	@printf '%s\n' \
	  'make build    - verify sources and build one module for uname -r' \
	  'make offline  - rebuild using the existing cache only' \
	  'make package  - build an Arch DKMS package without installing' \
	  'make doctor   - read-only hardware, headers and migration checks' \
	  'make status   - read-only kernel and DKMS status' \
	  'make check    - syntax and regression checks; never installs anything'
