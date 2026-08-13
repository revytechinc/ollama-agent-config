.PHONY: test dist publish publish-nginx lint

test:
	sh test/run.sh

dist:
	sh scripts/make-dist.sh

lint:
	sh test/posix_lint.sh

publish: dist
	sh scripts/publish.sh

publish-nginx: publish
	@echo "Insert include after packages.conf if missing, then:"
	@echo "  nginx -t && service nginx reload"
