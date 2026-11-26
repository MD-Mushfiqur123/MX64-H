PYTHON ?= python3
OUT ?= build/mx64h-demo.elf

.PHONY: check test example boot-image rtl-lint clean
check:
	$(PYTHON) scripts/check_repo.py
	$(PYTHON) scripts/check_rtl_sources.py
	$(PYTHON) tools/mx64/abi_check.py
	$(PYTHON) tools/mx64/audit_isa.py
	$(PYTHON) tools/mx64/platform_check.py platforms/fpga/template.json
	$(PYTHON) tools/mx64/platform_check.py platforms/asic/template.json
	$(PYTHON) scripts/check_phase37_6.py

test:
	$(PYTHON) tools/mx64/assembler_tests.py
	$(PYTHON) tools/mx64/architecture_tests.py
	$(PYTHON) tools/mx64/elf64_tests.py
	$(PYTHON) tools/mx64/multisection_tests.py
	$(PYTHON) tools/mx64/smoke_test.py
	$(PYTHON) tools/mx64/boot_image_tests.py
	$(PYTHON) tools/mx64/platform_tests.py
	$(PYTHON) tools/mx64/load_image_tests.py

rtl-lint:
	bash scripts/run_rtl_lint.sh

example:
	mkdir -p build
	$(PYTHON) tools/mx64/mxbuild.py software/examples/main.s software/examples/worker.s software/examples/memory.s -o $(OUT) --entry _start --map build/mx64h-demo.map

boot-image: example
	$(PYTHON) tools/mx64/mxboot.py pack $(OUT) -o build/mx64h-demo.mxb --platform generic
	$(PYTHON) tools/mx64/mxboot.py inspect build/mx64h-demo.mxb

clean:
	rm -rf build
