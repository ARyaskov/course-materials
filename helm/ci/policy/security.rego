package main

deny contains msg if {
	input.kind in {"Deployment", "StatefulSet", "Job"}
	container := input.spec.template.spec.containers[_]
	not container.securityContext.runAsNonRoot
	msg := sprintf("%s/%s: контейнер %s может работать от root", [input.kind, input.metadata.name, container.name])
}

deny contains msg if {
	input.kind in {"Deployment", "StatefulSet"}
	input.spec.template.spec.hostNetwork
	msg := sprintf("%s/%s: hostNetwork запрещён", [input.kind, input.metadata.name])
}

deny contains msg if {
	input.kind in {"Deployment", "StatefulSet", "Job"}
	container := input.spec.template.spec.containers[_]
	container.securityContext.privileged
	msg := sprintf("%s/%s: контейнер %s запускается привилегированным", [input.kind, input.metadata.name, container.name])
}
