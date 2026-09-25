# Single entry point for every gate, plus issue bookkeeping.
#
# Language-specific commands live in `makefile.local` so this file stays
# generic. The commands this repo actually uses must also be registered in
# `hai/CONTEXT.md`; when a variable is empty its gate is skipped and reported,
# and `make verify-strict` turns any such skip into a failure.
#
# Note: write `$$` for a literal `$` inside a command (Makefile syntax).

SHELL := /bin/bash
PYTHON ?= python3
HAI ?= hai

-include makefile.local

BUILD_CMD ?=
FMT_CMD ?=
LINT_CMD ?=
TEST_CMD ?=
COVER_CMD ?=
CYC_CMD ?=
COVERAGE_FILE ?= coverage.txt
COVERAGE_BASELINE ?= coverage-baseline.txt

GATES := BUILD_CMD FMT_CMD LINT_CMD TEST_CMD COVER_CMD CYC_CMD

.PHONY: help verify verify-strict build fmt lint test coverage coverage-check cycles \
        issue issue-list issue-sync issue-check issue-touch issue-status hooks

# Gate recipes dispatch while make parses: an unconfigured gate expands to a
# skip line only, so an empty command string never reaches the shell.
define gate_skip
@printf '  [skip] %-8s not configured\n' '$(1)'
endef

define gate_run
@printf '  [run ] %-8s\n' '$(1)'
@$(2)
endef

help: ## list every target
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(firstword $(MAKEFILE_LIST)) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

verify: build fmt lint test coverage-check cycles issue-check ## run every gate (single entry point)
	@echo "verify: done. [skip] means no command is configured for that gate -- see makefile.local, which auto-detects Go / Python / Node projects."

verify-strict: ## fail if any gate is unconfigured, then run every gate
	@missing=""; \
	for pair in $(foreach g,$(GATES),'$(g)=$($(g))'); do \
	  case "$$pair" in *=) missing="$$missing $${pair%%=*}";; esac; \
	done; \
	if [ -n "$$missing" ]; then \
	  printf '  [fail] gates not configured:%s\n' "$$missing"; \
	  echo "         set them in makefile.local and register them in hai/CONTEXT.md"; \
	  exit 1; \
	fi
	@$(MAKE) --no-print-directory verify

build: ## build gate
	$(if $(strip $(BUILD_CMD)),$(call gate_run,build,$(BUILD_CMD)),$(call gate_skip,build))

fmt: ## format gate
	$(if $(strip $(FMT_CMD)),$(call gate_run,fmt,$(FMT_CMD)),$(call gate_skip,fmt))

lint: ## lint gate
	$(if $(strip $(LINT_CMD)),$(call gate_run,lint,$(LINT_CMD)),$(call gate_skip,lint))

test: ## test gate
	$(if $(strip $(TEST_CMD)),$(call gate_run,test,$(TEST_CMD)),$(call gate_skip,test))

cycles: ## cycle / layering gate
	$(if $(strip $(CYC_CMD)),$(call gate_run,cycles,$(CYC_CMD)),$(call gate_skip,cycles))

coverage: ## refresh $(COVERAGE_FILE) from COVER_CMD
	$(if $(strip $(COVER_CMD)),$(call gate_run,coverage,$(COVER_CMD)),$(call gate_skip,coverage))

# Regenerates coverage.txt first (when COVER_CMD is set and a baseline exists),
# so the gate can never compare against a stale report.
coverage-check: $(if $(and $(strip $(COVER_CMD)),$(wildcard $(COVERAGE_BASELINE))),coverage,) ## full-suite coverage must not drop below the baseline
	@if [ ! -s "$(COVERAGE_BASELINE)" ]; then \
	  printf '  [skip] %-8s no %s yet (run `make coverage`, then commit it)\n' coverage "$(COVERAGE_BASELINE)"; \
	elif [ ! -s "$(COVERAGE_FILE)" ]; then \
	  printf '  [skip] %-8s %s missing, run `make coverage`\n' coverage "$(COVERAGE_FILE)"; \
	else \
	  awk -v cur="$$(cat $(COVERAGE_FILE))" -v base="$$(cat $(COVERAGE_BASELINE))" 'BEGIN{ \
	    if (cur+0 < base+0) { printf "  [fail] coverage %.2f < baseline %.2f\n", cur, base; exit 1 } \
	    printf "  [run ] %-8s %.2f >= baseline %.2f\n", "coverage", cur, base }'; \
	fi

hooks: ## install .githooks as core.hooksPath (idempotent)
	@chmod +x .githooks/pre-push
	@git config core.hooksPath .githooks
	@echo "core.hooksPath -> .githooks"

issue: ## create an issue: make issue type=feat slug=add-login title="..."
	@if [ -z "$(type)" ] || [ -z "$(slug)" ] || [ -z "$(title)" ]; then \
	  echo 'usage: make issue type=<type> slug=<slug> title="<title>"'; exit 2; \
	fi
	@$(PYTHON) scripts/issue.py --root $(HAI) create \
		--type $(type) --slug $(slug) --title "$(title)"

issue-list: ## list active issues: make issue-list [status=<status>] [all=1]
	@$(PYTHON) scripts/issue.py --root $(HAI) list \
		$(if $(status),--status $(status)) $(if $(all),--all)

issue-sync: ## rebuild $(HAI)/ISSUES.md from the detail pages
	@$(PYTHON) scripts/issue.py --root $(HAI) sync

issue-check: ## fail when $(HAI)/ISSUES.md drifted from the detail pages
	@$(PYTHON) scripts/issue.py --root $(HAI) check

issue-touch: ## bump updated_ts: make issue-touch name=<slug>
	@$(PYTHON) scripts/issue.py --root $(HAI) touch --name $(name)

issue-status: ## move an issue + History entry: make issue-status name=<slug> status=<status> [note="..."] [note_file=<path>]
	@$(PYTHON) scripts/issue.py --root $(HAI) set-status --name $(name) --status $(status) \
		$(if $(note),--note "$(note)") $(if $(note_file),--note-file $(note_file))
