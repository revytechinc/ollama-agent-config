.PHONY: test dist lint

test:
	sh test/run.sh

dist:
	sh scripts/make-dist.sh

lint:
	sh test/posix_lint.sh
