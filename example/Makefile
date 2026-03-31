
LOCAL :=
COVERAGE ?= true
COVERAGE_FLAG := $(if $(filter true,$(COVERAGE)),--coverage)

.DEFAULT_GOAL := test

ifneq ($(LOCAL),)
    NVIM_TEST_HOME = ..
else
    NVIM_TEST_HOME = nvim-test
endif

nvim-test:
	git clone https://github.com/lewis6991/nvim-test
	nvim-test/bin/nvim-test --init

.PHONY: test
test: $(NVIM_TEST_HOME)
	$(NVIM_TEST_HOME)/bin/nvim-test test \
		--lpath "$(CURDIR)/lua/?.lua" \
		--verbose $(COVERAGE_FLAG)
