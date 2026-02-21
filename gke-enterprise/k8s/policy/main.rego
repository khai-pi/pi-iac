# ============================================================
# Conftest / OPA Policies
# Run by CI on every PR to catch policy violations
# before they reach the cluster.
# ============================================================

package main

import future.keywords

# ── Rule: resource requests must be set ─────────────────────
deny contains msg if {
  input.kind == "Pod"
  container := input.spec.containers[_]
  not container.resources.requests.cpu
  msg := sprintf(
    "Pod '%s': container '%s' must set resources.requests.cpu",
    [input.metadata.name, container.name]
  )
}

deny contains msg if {
  input.kind == "Pod"
  container := input.spec.containers[_]
  not container.resources.requests.memory
  msg := sprintf(
    "Pod '%s': container '%s' must set resources.requests.memory",
    [input.metadata.name, container.name]
  )
}

deny contains msg if {
  input.kind == "Pod"
  container := input.spec.containers[_]
  not container.resources.limits.memory
  msg := sprintf(
    "Pod '%s': container '%s' must set resources.limits.memory",
    [input.metadata.name, container.name]
  )
}

# ── Rule: no latest / mutable image tags ────────────────────
denied_tags := {"latest", "master", "main", "dev", "test", "staging"}

deny contains msg if {
  input.kind == "Pod"
  container := input.spec.containers[_]
  parts := split(container.image, ":")
  count(parts) == 2
  denied_tags[parts[1]]
  msg := sprintf(
    "Pod '%s': container '%s' uses disallowed tag '%s'",
    [input.metadata.name, container.name, parts[1]]
  )
}

deny contains msg if {
  input.kind == "Pod"
  container := input.spec.containers[_]
  not contains(container.image, ":")
  msg := sprintf(
    "Pod '%s': container '%s' must specify an explicit image tag",
    [input.metadata.name, container.name]
  )
}

# ── Rule: runAsNonRoot required ──────────────────────────────
deny contains msg if {
  input.kind == "Pod"
  not input.spec.securityContext.runAsNonRoot
  msg := sprintf(
    "Pod '%s': spec.securityContext.runAsNonRoot must be true",
    [input.metadata.name]
  )
}

# ── Rule: no privilege escalation ───────────────────────────
deny contains msg if {
  input.kind == "Pod"
  container := input.spec.containers[_]
  container.securityContext.allowPrivilegeEscalation == true
  msg := sprintf(
    "Pod '%s': container '%s' must not set allowPrivilegeEscalation=true",
    [input.metadata.name, container.name]
  )
}

# ── Rule: must drop ALL capabilities ────────────────────────
deny contains msg if {
  input.kind == "Pod"
  container := input.spec.containers[_]
  not container.securityContext.capabilities.drop
  msg := sprintf(
    "Pod '%s': container '%s' must drop ALL capabilities",
    [input.metadata.name, container.name]
  )
}

# ── Rule: seccompProfile required ───────────────────────────
deny contains msg if {
  input.kind == "Pod"
  not input.spec.securityContext.seccompProfile
  msg := sprintf(
    "Pod '%s': must set seccompProfile (use RuntimeDefault)",
    [input.metadata.name]
  )
}

# ── Rule: images from approved registries only ───────────────
approved_registries := {
  "europe-west1-docker.pkg.dev/myorg-shared-services/",
  "registry.k8s.io/",
  "gcr.io/gke-release/",
}

deny contains msg if {
  input.kind == "Pod"
  container := input.spec.containers[_]
  not any_approved(container.image)
  msg := sprintf(
    "Pod '%s': container '%s' image '%s' is not from an approved registry",
    [input.metadata.name, container.name, container.image]
  )
}

any_approved(image) if {
  registry := approved_registries[_]
  startswith(image, registry)
}

# ── Rule: NodePort services disallowed ───────────────────────
deny contains msg if {
  input.kind == "Service"
  input.spec.type == "NodePort"
  msg := sprintf(
    "Service '%s': NodePort is not allowed. Use ClusterIP or LoadBalancer.",
    [input.metadata.name]
  )
}

# ── Rule: required labels on Deployments and Rollouts ────────
required_labels := {"app", "team"}

warn contains msg if {
  input.kind in {"Deployment", "Rollout"}
  label := required_labels[_]
  not input.metadata.labels[label]
  msg := sprintf(
    "%s '%s' is missing recommended label '%s'",
    [input.kind, input.metadata.name, label]
  )
}

# ── Rule: PodDisruptionBudget should exist for Deployments ───
warn contains msg if {
  input.kind == "Deployment"
  replicas := input.spec.replicas
  replicas >= 2
  # This is a warn — PDB is checked separately by CI
  msg := sprintf(
    "Deployment '%s' has %d replicas — ensure a PodDisruptionBudget exists",
    [input.metadata.name, replicas]
  )
}
