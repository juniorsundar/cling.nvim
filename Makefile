TESTS_INIT=tests/minimal_init.lua
TESTS_DIR=tests/

.PHONY: test

test:
	@output=$$(nvim \
		--headless \
		--noplugin \
		-u ${TESTS_INIT} \
		-c "PlenaryBustedDirectory ${TESTS_DIR} { minimal_init = '${TESTS_INIT}' }" 2>&1 || true); \
	echo "$$output"; \
	if echo "$$output" | grep -q "Failed : 	[1-9]"; then \
		echo "TESTS FAILED"; exit 1; \
	elif echo "$$output" | grep -q "Errors : 	[1-9]"; then \
		echo "TEST ERRORS DETECTED"; exit 1; \
	elif echo "$$output" | grep -q "Success"; then \
		echo "ALL TESTS PASSED"; exit 0; \
	else \
		echo "UNEXPECTED OUTPUT"; exit 1; \
	fi