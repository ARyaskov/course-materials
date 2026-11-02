package main

deny contains msg if {
	input.kind in {"Deployment", "StatefulSet", "Job"}
	container := input.spec.template.spec.containers[_]
	endswith(container.image, ":latest")
	msg := sprintf("%s/%s: контейнер %s использует тег latest", [input.kind, input.metadata.name, container.name])
}

deny contains msg if {
	input.kind in {"Deployment", "StatefulSet", "Job"}
	container := input.spec.template.spec.containers[_]
	not contains(container.image, ":")
	not contains(container.image, "@")
	msg := sprintf("%s/%s: контейнер %s без тега", [input.kind, input.metadata.name, container.name])
}
