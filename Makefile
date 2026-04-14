.PHONY: build --verbose

build:
	./scripts/build.sh $(filter --verbose,$(MAKECMDGOALS))

--verbose:
	@:
