SPHINXOPTS  ?=
SPHINXBUILD ?= sphinx-build
SOURCEDIR    = docs
BUILDDIR     = docs/_build

.PHONY: help html epub latex pdf clean all install

help:
	@echo "Usage:"
	@echo "  make install  - install Python dependencies"
	@echo "  make html     - build HTML site"
	@echo "  make epub     - build EPUB book"
	@echo "  make latex    - build LaTeX source"
	@echo "  make pdf      - build PDF (requires latexmk + texlive)"
	@echo "  make all      - build HTML + EPUB + PDF, collect downloads"
	@echo "  make clean    - remove build artifacts"

install:
	pip install -r $(SOURCEDIR)/requirements.txt

html:
	$(SPHINXBUILD) -b html $(SPHINXOPTS) $(SOURCEDIR) $(BUILDDIR)/html

epub:
	$(SPHINXBUILD) -b epub $(SPHINXOPTS) $(SOURCEDIR) $(BUILDDIR)/epub

latex:
	$(SPHINXBUILD) -b latex $(SPHINXOPTS) $(SOURCEDIR) $(BUILDDIR)/latex

pdf: latex
	cd $(BUILDDIR)/latex && latexmk -pdf -interaction=nonstopmode ethcluj2026.tex

all: html epub pdf
	mkdir -p $(BUILDDIR)/html/downloads
	cp $(BUILDDIR)/epub/*.epub $(BUILDDIR)/html/downloads/ 2>/dev/null || true
	cp $(BUILDDIR)/latex/*.pdf  $(BUILDDIR)/html/downloads/ 2>/dev/null || true
	touch $(BUILDDIR)/html/.nojekyll
	@echo ""
	@echo "All outputs in $(BUILDDIR)/html  (site + downloads/)"

clean:
	rm -rf $(BUILDDIR)
