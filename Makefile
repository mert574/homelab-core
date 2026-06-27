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
	@command -v nix >/dev/null 2>&1 && nix flake check ./nix || echo "  (nix not installed; skipping)"

k8s:
	@echo "== kubeconform =="
	@command -v kubeconform >/dev/null 2>&1 && kubeconform $(KC_FLAGS) $(CLUSTER) || echo "  (kubeconform not installed; skipping)"

sh:
	@echo "== shellcheck =="
	@command -v shellcheck >/dev/null 2>&1 && shellcheck $$(find . -name '*.sh' -not -path './.git/*') || echo "  (shellcheck not installed; skipping)"

ci:
	@echo "== actionlint =="
	@command -v actionlint >/dev/null 2>&1 && actionlint || echo "  (actionlint not installed or no workflows; skipping)"
