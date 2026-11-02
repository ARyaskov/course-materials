CHART   := ./charts/tessera
ENVS    := dev staging prod preview
KUBE_VERSION ?= 1.31.0

.PHONY: check check-fast fmt lint render unittest schema policy immutable ct clean

check-fast: fmt lint render unittest schema policy immutable
check: check-fast ct

fmt:
	@echo "== форматирование"
	@rc=0; grep -rnF "$$(printf '\t')" $(CHART)/templates/ || rc=$$?; \
	case $$rc in 0) echo "найдены табуляции"; exit 1;; 1) :;; *) exit $$rc;; esac

lint:
	@echo "== helm lint"
	@for e in $(ENVS); do \
	  helm lint $(CHART) -f envs/values-$$e.yaml >/dev/null || exit 1; \
	done

render:
	@echo "== рендеринг"
	@mkdir -p .out
	@for e in $(ENVS); do \
	  helm template t $(CHART) -f envs/values-$$e.yaml > .out/$$e.yaml || exit 1; \
	done

unittest:
	@echo "== юнит-тесты шаблонов"
	@plugins="$$(helm plugin list)" || exit $$?; \
	if printf '%s\n' "$$plugins" | awk 'NR > 1 {print $$1}' | grep -qx unittest; then \
	  helm unittest $(CHART); \
	else echo "  плагин helm-unittest не установлен, пропущено"; fi

schema: render
	@echo "== схемы Kubernetes"
	@command -v kubeconform >/dev/null || { echo "  kubeconform не установлен, пропущено"; exit 0; }; \
	for e in $(ENVS); do \
	  kubeconform -strict -kubernetes-version $(KUBE_VERSION) \
	    -ignore-missing-schemas -summary .out/$$e.yaml || exit 1; \
	done

policy: render
	@echo "== политики"
	@command -v conftest >/dev/null || { echo "  conftest не установлен, пропущено"; exit 0; }; \
	for e in $(ENVS); do \
	  conftest test --policy ci/policy .out/$$e.yaml || exit 1; \
	done

immutable:
	@echo "== иммутабельные поля не менялись"
	@./scripts/check-immutable.sh

ct:
	@echo "== установка и обновление в эфемерном кластере"
	@./scripts/ct-install.sh

clean:
	@rm -rf .out
