all: namespaces.html

namespaces.html: namespaces.md Makefile
	if [ -f Slidy2/scripts/slidy.js ]; \
	  then SURL="-V slidy-url=./Slidy2/ --self-contained"; \
	  else SURL=""; \
	fi; \
	pandoc \
	  -V subtitle='from chroot() to containers' \
	  $$SURL \
	  -s -t slidy \
	  -o $@ $<

.PHONY: clean
clean:
	rm -f *.html
