.PHONY: help build serve open clean install docker-build docker-serve

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

install: ## Install required dependencies (asciidoctor and asciidoctor-revealjs)
	@echo "Installing Asciidoctor and Asciidoctor Reveal.js..."
	gem install asciidoctor asciidoctor-revealjs

build: ## Build the presentation from AsciiDoc to HTML
	@echo "Building presentation..."
	asciidoctor -r asciidoctor-revealjs -b revealjs presentation.adoc -o index.html
	@echo "✓ Presentation built: index.html"

docker-build: ## Build the presentation using Docker (no local Ruby/gems needed)
	@echo "Building presentation with Docker..."
	docker run --rm -v $(PWD):/documents asciidoctor/docker-asciidoctor \
		asciidoctor-revealjs presentation.adoc -o index.html
	@echo "✓ Presentation built: index.html"

docker-serve: docker-build ## Build with Docker and serve on http://localhost:8000
	@echo "Starting web server on http://localhost:8000"
	@echo "Press Ctrl+C to stop"
	python3 -m http.server 8000

serve: build ## Build and serve the presentation on http://localhost:8000
	@echo "Starting web server on http://localhost:8000"
	@echo "Press Ctrl+C to stop"
	python3 -m http.server 8000

open: build ## Build and open the presentation in the default browser
	@echo "Opening presentation..."
	@if command -v open > /dev/null; then \
		open index.html; \
	elif command -v xdg-open > /dev/null; then \
		xdg-open index.html; \
	elif command -v start > /dev/null; then \
		start index.html; \
	else \
		echo "Could not detect the web browser"; \
	fi

clean: ## Remove generated files
	@echo "Cleaning generated files..."
	rm -f index.html
	@echo "✓ Clean complete"

watch: ## Watch for changes and rebuild automatically (requires entr)
	@if ! command -v entr > /dev/null; then \
		echo "Error: entr is not installed"; \
		echo "Install it with: brew install entr (macOS) or apt-get install entr (Linux)"; \
		exit 1; \
	fi
	@echo "Watching presentation.adoc for changes..."
	@echo "Press Ctrl+C to stop"
	@echo presentation.adoc | entr -c make build

