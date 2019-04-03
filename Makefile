all: namespaces.html

namespaces.html: namespaces.md
	pandoc \
	  -V subtitle='from chroot() to containers' \
	  -s -t slidy \
	  -o $@ $<

.PHONY: clean
clean:
	rm -f *.html
