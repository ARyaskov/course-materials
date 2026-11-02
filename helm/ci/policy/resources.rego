package main

deny contains msg if {
	input.kind in {"Deployment", "StatefulSet"}
	container := input.spec.template.spec.containers[_]
	not container.resources.requests.cpu
	msg := sprintf("%s/%s: контейнер %s без requests.cpu", [input.kind, input.metadata.name, container.name])
}

deny contains msg if {
	input.kind in {"Deployment", "StatefulSet"}
	container := input.spec.template.spec.containers[_]
	not container.resources.limits.memory
	msg := sprintf("%s/%s: контейнер %s без limits.memory", [input.kind, input.metadata.name, container.name])
}

# Жёсткий лимит CPU приводит к троттлингу и росту задержки на хвостах.
warn contains msg if {
	input.kind in {"Deployment", "StatefulSet"}
	container := input.spec.template.spec.containers[_]
	container.resources.limits.cpu
	msg := sprintf("%s/%s: контейнер %s имеет limits.cpu — это приводит к троттлингу", [input.kind, input.metadata.name, container.name])
}
