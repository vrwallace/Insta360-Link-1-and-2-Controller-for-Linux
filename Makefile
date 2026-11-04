.PHONY: all release debug cli clean test

LAZBUILD ?= lazbuild
FPC ?= fpc
PROJECT := insta360linkgui.lpi
WIDGETSET := gtk2

all: release cli

release:
	$(LAZBUILD) --build-mode=Release --widgetset=$(WIDGETSET) $(PROJECT)

debug:
	$(LAZBUILD) --build-mode=Debug --widgetset=$(WIDGETSET) $(PROJECT)

cli:
	$(FPC) -Mobjfpc -Sh -gl linkctl.pas

clean:
	python3 scripts/clean.py

# Hardware-independent regression suite; builds in a temporary directory.
test:
	python3 tests/run_tests.py
