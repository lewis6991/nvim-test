
LOCAL :=

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
		--lpath=$(PWD)/lua/?.lua
