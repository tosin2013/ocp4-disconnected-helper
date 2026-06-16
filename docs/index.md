---
layout: default
title: Home
nav_order: 1
description: "Complete documentation for OpenShift Disconnected Helper"
permalink: /
---

# Diátaxis Documentation Index

This project follows the [Diátaxis documentation framework](https://diataxis.fr/) for structured, comprehensive documentation.

---

## 📚 Documentation Types

### 🎓 Tutorials (Learning-Oriented)

**Purpose**: Learn by doing. Take you from beginner to capable.

| Tutorial | Time | Level | Status |
|----------|------|-------|--------|
| [Getting Started with AAP Workflows](tutorials/getting-started-with-aap-workflows.md) | 60-90 min | Beginner | ✅ Complete |
| [Your First OpenShift Image Mirror](tutorials/your-first-openshift-image-mirror.md) | 45-60 min | Beginner | ✅ Complete |
| [End-to-End Disconnected Deployment](tutorials/end-to-end-disconnected-deployment.md) | 4-6 hours | Intermediate | ✅ Complete |

**When to use**: You're new to this project or want to learn by following along.

---

### 🔧 How-To Guides (Task-Oriented)

**Purpose**: Solve a specific problem. Assume you're already competent.

#### Deployment
- [Deploy AAP Multi-Node](how-to/deploy-aap-multi-node.md) - Install AAP 2.6 with multi-node architecture
- [Deploy VyOS Router](how-to/deploy-vyos-router.md) - Set up VyOS network infrastructure
- [Deploy Workflow 1 (Registry Infrastructure)](how-to/deploy-workflow-1-registry-infrastructure.md) - Deploy container registry via AAP
- [Deploy Workflow 2 (Image Mirroring)](how-to/deploy-workflow-2-image-mirroring.md) - Mirror OpenShift images via AAP
- [Configure Operator Catalog for Disconnected](how-to/configure-operator-catalog-for-disconnected.md) - Connect cluster to mirrored operators

#### Configuration
- [Add Custom Operators](how-to/add-custom-operators.md) - Create custom operator presets
- [Build Custom Execution Environment](how-to/build-custom-execution-environment.md) - Create AAP custom EE container
- [Configure AAP Post-Install](how-to/configure-aap-post-install.md) - Post-deployment AAP configuration
- [Create Quay Robot Accounts](how-to/create-quay-robot-accounts.md) - Automate Quay authentication
- [Import GitHub Projects to AAP](how-to/import-github-projects-to-aap.md) - Sync Git repos with AAP
- [Setup Cockpit for VM Management](how-to/setup-cockpit-for-vm-management.md) - Web-based VM console
- [Setup Podman Rootless](how-to/setup-podman-rootless.md) - Non-root container runtime
- [Setup RHEL Activation Keys](how-to/setup-rhel-activation-keys.md) - Automate RHEL registration
- [Switch Registry Types](how-to/switch-registry-types.md) - Migrate Quay↔Harbor↔JFrog

#### Troubleshooting
- [Download RHEL9 ISO](how-to/download-rhel9-iso.md) - Obtain RHEL installation media
- [Resolve: AAP Login Failure](how-to/resolve-aap-login-failure.md) - Fix multi-node password issues
- [Resolve: oc-mirror Async Cache](how-to/resolve-oc-mirror-async-cache.md) - Clear Ansible async cache
- [Resolve: Registry TLS Authentication](how-to/resolve-registry-tls-authentication.md) - Fix certificate trust errors
- [Troubleshoot Workflow Failures](how-to/troubleshoot-workflow-failures.md) - Systematic AAP debugging

**Total**: 19 guides | **When to use**: You know what you want to do, just need the steps.

---

### 📖 Reference (Information-Oriented)

**Purpose**: Look up accurate technical facts.

- [AAP Job Templates](reference/aap-job-templates.md) - Complete job template reference
- [AAP Workflow Catalog](AAP_WORKFLOW_CATALOG.md) - Workflow IDs, nodes, dependencies
- [ADR Status Reference](adrs/README.md) - 36 architectural decisions
- [Ansible Roles Structure](reference/ansible-roles-structure.md) - Role architecture and patterns
- [Bootstrap Prerequisites](reference/bootstrap-prerequisites.md) - VyOS, DNS, AAP requirements
- [Environment Variables](reference/environment-variables.md) - Complete env var catalog
- [Libvirt Permissions](reference/libvirt-permissions.md) - KVM/libvirt access configuration
- [Operator Preset Catalog](reference/operator-preset-catalog.md) - 8 curated operator bundles
- [Playbook Parameters](reference/playbook-parameters.md) - All playbook parameters
- [Workflow Survey Parameters](reference/workflow-survey-parameters.md) - AAP survey reference

**Total**: 10 references | **When to use**: You need to look up exact syntax, parameters, or system facts.

---

### 💡 Explanations (Understanding-Oriented)

**Purpose**: Understand the "why" behind architectural decisions.

- [Airflow → AAP Migration](explanations/airflow-to-aap-migration.md) - Why we deprecated Airflow for AAP
- [Bootstrap vs Workflow Layers](explanations/bootstrap-vs-workflow-layers.md) - Two-tier architecture separation
- [Certificate Management Decisions](explanations/certificate-management-decisions.md) - Let's Encrypt vs self-signed
- [Developer Guide](explanations/developer-guide.md) - Contributing to this project
- [Multi-Workflow Architecture](explanations/multi-workflow-architecture.md) - Why 2 workflows not 1 monolith
- [Nested KVM Hypervisor Architecture](explanations/nested-kvm-hypervisor-architecture.md) - VM running VMs design
- [Operator Validation Framework](explanations/operator-validation-framework.md) - Pre-flight validation (ADR-0034)

**Total**: 7 explanations | **When to use**: You want to understand design decisions and trade-offs.

---

## 🧭 Navigation by Task

### "I want to learn..."
→ Start with **Tutorials**: [Getting Started with AAP Workflows](tutorials/getting-started-with-aap-workflows.md)

### "I need to do..."
→ Use **How-To Guides**: [Deploy Workflow 1](how-to/deploy-workflow-1-registry-infrastructure.md)

### "I need to look up..."
→ Check **Reference**: [AAP Workflow Catalog](AAP_WORKFLOW_CATALOG.md) or [ADRs](adrs/README.md)

### "I want to understand..."
→ Read **Explanations**: [Bootstrap vs Workflow Layers](explanations/bootstrap-vs-workflow-layers.md) or [Multi-Workflow Architecture](explanations/multi-workflow-architecture.md)

---

## 📊 Documentation Status

**v1.4.0 Coverage** (after cleanup):
- ✅ Tutorials: 3/3 complete (100%)
- ✅ How-To Guides: 18/18 complete (100%)
- ✅ Reference: 10/10 complete (100%)
- ✅ Explanations: 7/7 complete (100%)

**Total Core Documentation**: 38 Diátaxis files  
**Archived**: 21 duplicate/obsolete files moved to `.archive/`  
**Cleanup**: 52% reduction (103 → 49 total files)

[View archived documentation](.archive/README.md)

---

## 🤝 Contributing

Found a gap in the documentation? See [CONTRIBUTING.md](../CONTRIBUTING.md) for how to add or improve docs following Diátaxis principles.

---

## 📚 Further Reading

- [Diátaxis Framework](https://diataxis.fr/) - Documentation philosophy
- [ADR-0032: Multi-Workflow Architecture](adrs/adr-0032-aap-workflow-orchestration-strategy.md) - Architectural foundation
- [CHANGELOG.md](../CHANGELOG.md) - Release history
