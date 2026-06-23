SPHINXOPTS  ?=
SPHINXBUILD ?= sphinx-build
SOURCEDIR    = docs
BUILDDIR     = docs/_build

.PHONY: help html epub latex pdf clean all install

# Default: build everything and collect downloads
all: html epub latex
	mkdir -p $(BUILDDIR)/html/downloads
	cp $(BUILDDIR)/epub/*.epub $(BUILDDIR)/html/downloads/ 2>/dev/null || true
	touch $(BUILDDIR)/html/.nojekyll
	@echo ""
	@echo "Done. Outputs:"
	@echo "  HTML site  -> $(BUILDDIR)/html/"
	@echo "  EPUB book  -> $(BUILDDIR)/epub/*.epub"
	@echo "  LaTeX src  -> $(BUILDDIR)/latex/ethcluj2026.tex"
	@echo ""
	@echo "To also build PDF (needs texlive + latexmk):"
	@echo "  make pdf"

help:
	@echo "Usage:"
	@echo "  make          - build HTML + EPUB + LaTeX, collect downloads"
	@echo "  make install  - install Python + Node dependencies"
	@echo "  make html     - build HTML site only"
	@echo "  make epub     - build EPUB book only"
	@echo "  make latex    - build LaTeX source only"
	@echo "  make pdf      - build PDF via latexmk (requires texlive)"
	@echo "  make clean    - remove all build artifacts"

install:
	pip install -r $(SOURCEDIR)/requirements.txt
	@echo "Installing mermaid-cli (needs npm)..."
	npm install @mermaid-js/mermaid-cli
	@echo ""
	@echo "Dependencies installed. Run 'make' to build."

html:
	$(SPHINXBUILD) -b html $(SPHINXOPTS) $(SOURCEDIR) $(BUILDDIR)/html

epub:
	$(SPHINXBUILD) -b epub $(SPHINXOPTS) $(SOURCEDIR) $(BUILDDIR)/epub

latex:
	$(SPHINXBUILD) -b latex $(SPHINXOPTS) $(SOURCEDIR) $(BUILDDIR)/latex

pdf: latex
	cd $(BUILDDIR)/latex && latexmk -pdf -interaction=nonstopmode ethcluj2026.tex
	mkdir -p $(BUILDDIR)/html/downloads
	cp $(BUILDDIR)/latex/*.pdf $(BUILDDIR)/html/downloads/ 2>/dev/null || true

clean:
	rm -rf $(BUILDDIR)
