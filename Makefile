all: namespaces.s5.html namespaces.slidy.html

namespaces.s5.html: namespaces.md
	pandoc -V s5-url=/usr/share/javascript/s5/s5-blank/ui/default \
	  -V subtitle='from chroot() to containers' -s -t s5 \
	  $< \
	  -o $@

namespaces.slidy.html: namespaces.md
	pandoc \
	  -V subtitle='from chroot() to containers' -s -t slidy \
	  $< \
	  -o $@

.PHONY: html
html:
	for i in s5 slidy slideous dszlides revealjs; do echo Format $$i; pandoc -V s5-url=/usr/share/javascript/s5/default/ui/default -V subtitle='from chroot() to containers' -s -t $$i namespaces.md -o namespaces.$${i}.html; echo done; done; cp -a .. /tmp/name/
