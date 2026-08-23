TESTS_INIT=tests/minimal_init.lua
TESTS_DIR=tests/

.PHONY: test

test:
	@output=$$(nvim \
		--headless \
		--noplugin \
		-u ${TESTS_INIT} \
		-c "PlenaryBustedDirectory ${TESTS_DIR} { minimal_init = '${TESTS_INIT}' }" 2>&1); \
	status=$$?; \
	echo "$$output"; \
	if echo "$$output" | grep -Eq "Errors?[[:space:]]*:[[:space:]]*[1-9]" ; then \
		echo "TEST ERRORS DETECTED"; exit 1; \
	elif echo "$$output" | grep -Eq "Failures?[[:space:]]*:[[:space:]]*[1-9]|Failed[[:space:]]*:[[:space:]]*[1-9]" ; then \
		echo "TESTS FAILED"; exit 1; \
	elif [ $$status -ne 0 ]; then \
		echo "NVIM EXITED NON-ZERO ($$status)"; exit 1; \
	elif echo "$$output" | grep -Eq "Success:?" ; then \
		echo "ALL TESTS PASSED"; exit 0; \
	else \
		echo "UNEXPECTED OUTPUT"; exit 1; \
	fi
