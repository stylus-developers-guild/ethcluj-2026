# -- Project information -------------------------------------------------------
project = "ETH Cluj 2026: How To Build on Arbitrum"
author = "Stylus Developers Guild"
copyright = "2026, Stylus Developers Guild"
release = "1.0"
version = "1.0"

# -- General configuration -----------------------------------------------------
extensions = [
    "myst_parser",
    "sphinxcontrib.mermaid",
    "sphinxext.opengraph",
]

# MyST settings
myst_enable_extensions = [
    "dollarmath",
    "colon_fence",
]
myst_heading_anchors = 3

# Mermaid: CDN JS for HTML, mmdc CLI for LaTeX/PDF/EPUB
mermaid_output_format = "raw"
mermaid_cmd = "mmdc"
import os as _os
_conf_dir = _os.path.dirname(_os.path.abspath(__file__))
mermaid_params = ["-t", "neutral", "--scale", "2", "-p", _os.path.join(_conf_dir, "puppeteer-config.json")]

# Source suffixes
source_suffix = {
    ".rst": "restructuredtext",
    ".md": "markdown",
}

master_doc = "index"

# Suppress noisy warnings
suppress_warnings = [
    "epub.unknown_project_files",
    "misc.highlighting_failure",
]

# -- Options for OpenGraph meta tags -------------------------------------------
ogp_site_url = "https://stylus-developers-guild.github.io/ethcluj-2026/"
ogp_site_name = "ETH Cluj 2026: How To Build on Arbitrum"
ogp_image = "_static/images/og-card.png"
ogp_description_length = 200
ogp_type = "article"
ogp_custom_meta_tags = [
    '<meta name="twitter:card" content="summary_large_image" />',
    '<meta name="twitter:title" content="ETH Cluj 2026: How To Build on Arbitrum" />',
    '<meta name="twitter:description" content="Free workshop book — Ethereum, Solidity, Arbitrum Stylus, WASM smart contracts, and full-stack dApp development." />',
]

# -- Options for HTML output ---------------------------------------------------
html_theme = "sphinx_book_theme"
html_title = "ETH Cluj 2026"
html_static_path = ["_static"]
html_theme_options = {
    "repository_url": "https://github.com/stylus-developers-guild/ethcluj-2026",
    "use_repository_button": True,
    "show_toc_level": 2,
    "announcement": (
        "📥 Download this book as "
        '<a href="downloads/ETHCluj2026HowToBuildonArbitrum.epub">EPUB</a> or '
        '<a href="downloads/ethcluj2026.pdf">PDF</a>'
    ),
}

# -- Options for EPUB output ---------------------------------------------------
epub_title = project
epub_author = author
epub_language = "en"
epub_show_urls = "footnote"

# -- Options for LaTeX/PDF output ----------------------------------------------
latex_documents = [
    (master_doc, "ethcluj2026.tex", project, author, "manual"),
]
latex_elements = {
    "papersize": "a4paper",
    "pointsize": "11pt",
    "preamble": r"""
\usepackage[utf8]{inputenc}
""",
}

# Exclude build artifacts
exclude_patterns = ["_build", "Thumbs.db", ".DS_Store"]
