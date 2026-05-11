# logodal Polyglot Stack Makefile

# Localhost is always allowed as an insecure registry by Docker
REGISTRY = localhost:5000
# Single point of truth for versions is VERSION
TAG ?= $(shell cat VERSION)
PROJECT_NAME ?= logodal
DOCKER_BUILD_FLAGS ?= --progress=plain
NAMESPACE = logodal
DOMAIN = logodal.fazigu.org

SERVICES = frontend backend wordd

.PHONY: all build clean deploy undeploy help backup ensure-namespace sync-version $(SERVICES)

all: build

help:
	@echo "logodal Build System (Kind)"
	@echo "Usage:"
	@echo "  make build              - Build and push all microservice Docker images"
	@echo "  make deploy             - Install/Upgrade using Helm umbrella chart"
	@echo "  make <service>          - Build, Push, and Restart a specific service"

ensure-namespace:
	@kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -

# Docker Build & Push Targets
build: $(SERVICES)

$(SERVICES): ensure-namespace
	docker build $(DOCKER_BUILD_FLAGS) -t $(REGISTRY)/$(PROJECT_NAME)-$@:$(TAG) ./srv/$@
	docker push $(REGISTRY)/$(PROJECT_NAME)-$@:$(TAG)
	@if kubectl get deployment $@ -n $(NAMESPACE) > /dev/null 2>&1; then \
		kubectl rollout restart deployment/$@ -n $(NAMESPACE); \
		kubectl rollout status deployment/$@ -n $(NAMESPACE); \
	else \
		echo "⚠️  deployment/$@ not found in namespace $(NAMESPACE). Run 'make deploy' first."; \
	fi

sync-version: ## Propagate VERSION to package.json, Chart.yaml appVersions, and imageTag
	node scripts/sync-version.js

migrate: ## Run pending database migrations inside the cluster
	kubectl exec -n $(NAMESPACE) -it deploy/backend -- perl -Ilib bin/migrate.pl

backup: ## Create a timestamped SQL backup of the logodal database
	bash scripts/backup-db.sh


# Helm Commands
# i18n Note: Master truth lives in srv/frontend/share/locale/
# Both frontend and backend mount the logodal-locales ConfigMap.

deploy: ensure-namespace
	node scripts/sync-version.js
	@mkdir -p helm/share/locale
	@cp srv/frontend/share/locale/*.json helm/share/locale/
	rm -rf helm/charts/*.tgz
	helm dependency update ./helm
	kubectl delete configmap logodal-locales --namespace $(NAMESPACE) --ignore-not-found
	helm upgrade --install logodal ./helm \
		--namespace $(NAMESPACE) \
		--create-namespace \
		--values ./helm/values.yaml \
		--values ./helm/secrets.yaml \
		--set global.registry=localhost:5000 \
		--set global.domain=$(DOMAIN)

undeploy:
	helm uninstall logodal --namespace $(NAMESPACE)

# Hot-reload i18n via ConfigMap
locales:
	@echo "Updating shared locales ConfigMap..."
	@kubectl delete configmap logodal-locales --namespace $(NAMESPACE) --ignore-not-found
	@kubectl create configmap logodal-locales \
		--namespace $(NAMESPACE) \
		--from-file=en.json=srv/frontend/share/locale/en.json \
		--from-file=es.json=srv/frontend/share/locale/es.json \
		--from-file=fr.json=srv/frontend/share/locale/fr.json \
		--from-file=de.json=srv/frontend/share/locale/de.json \
		--from-file=ru.json=srv/frontend/share/locale/ru.json
	@echo "✅ ConfigMap updated. Pods will pick up changes within 5 minutes."

# Lexicon generation from Hunspell dictionaries
HUNSPELL_DICTS ?= /usr/share/hunspell
WORDD_ROOT ?= srv/wordd/share/words
LANGS = de el en es fr ru

lexicon:
	@if [ -z "$(LANG)" ]; then echo "Usage: make lexicon LANG=en"; exit 1; fi
	@echo "Generating lexicon for $(LANG)..."
	@mkdir -p $(WORDD_ROOT)/$(LANG)
	@find $(HUNSPELL_DICTS) -name "$(LANG)_[A-Z]*.dic" | xargs perl scripts/hunspell-to-lexicon.pl > $(WORDD_ROOT)/$(LANG)/lexicon.txt
	@echo "✅ $(LANG) lexicon generated: $$(wc -l < $(WORDD_ROOT)/$(LANG)/lexicon.txt) words"

lexicons:
	@for lang in $(LANGS); do \
		$(MAKE) lexicon LANG=$$lang; \
	done
	@echo "✅ All lexicons generated."
	@wc -l $(WORDD_ROOT)/*/lexicon.txt

# Cleanup
clean:
	@echo "Cleaning up local artifacts..."
	rm -rf helm/share
	rm -rf srv/frontend/dist
	rm -rf srv/frontend/node_modules
	rm -rf srv/wordd/target
	find . -name "*.exe" -delete

