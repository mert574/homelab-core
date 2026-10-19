# Validation harness. `make validate` runs every check; each skips with a note if
# its tool isn't installed, so it's useful locally and in CI.

CLUSTER := cluster/apps cluster/bootstrap/root-app.yaml
KC_FLAGS := -strict -ignore-missing-schemas -summary \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

.PHONY: validate tofu nix k8s sh ci

validate: tofu nix k8s sh ci
	@echo "== validation complete =="

tofu:
	@echo "== tofu =="
	@tofu fmt -check -recursive
	@tofu -chdir=tofu init -backend=false -input=false >/dev/null
	@tofu -chdir=tofu validate

nix:
	@echo "== nix flake check =="
	@if command -v nix >/dev/null 2>&1; then \
		nix flake check .; \
	else echo "  (nix not installed; skipping)"; fi

k8s:
	@echo "== kubeconform =="
	@if command -v kubeconform >/dev/null 2>&1; then \
		kubeconform $(KC_FLAGS) $(CLUSTER); \
	else echo "  (kubeconform not installed; skipping)"; fi

sh:
	@echo "== shellcheck =="
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck $$(find . -name '*.sh' -not -path './.git/*'); \
	else echo "  (shellcheck not installed; skipping)"; fi

ci:
	@echo "== actionlint =="
	@if command -v actionlint >/dev/null 2>&1; then \
		actionlint; \
	else echo "  (actionlint not installed; skipping)"; fi
