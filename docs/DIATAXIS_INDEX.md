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

| Guide | Category | Status |
|-------|----------|--------|
| [Deploy Workflow 1 (Registry Infrastructure)](how-to/deploy-workflow-1-registry-infrastructure.md) | Deployment | ✅ Complete |
| [Deploy Workflow 2 (Image Mirroring)](how-to/deploy-workflow-2-image-mirroring.md) | Deployment | ✅ Complete |
| [Troubleshoot Workflow Failures](how-to/troubleshoot-workflow-failures.md) | Troubleshooting | ✅ Complete |
| [Resolve: AAP Login Failure](how-to/resolve-aap-login-failure.md) | Troubleshooting | ✅ Complete |
| [Resolve: oc-mirror Async Cache](how-to/resolve-oc-mirror-async-cache.md) | Troubleshooting | ✅ Complete |
| [Resolve: Registry TLS Authentication](how-to/resolve-registry-tls-authentication.md) | Troubleshooting | ✅ Complete |
| [Add Custom Operators](how-to/add-custom-operators.md) | Configuration | ✅ Complete |
| [Switch Registry Types](how-to/switch-registry-types.md) | Configuration | ✅ Complete |

**When to use**: You know what you want to do, just need the steps.

---

### 📖 Reference (Information-Oriented)

**Purpose**: Look up accurate technical facts.

| Reference | Status |
|-----------|--------|
| [AAP Workflow Catalog](AAP_WORKFLOW_CATALOG.md) | ✅ Complete |
| [Playbook Parameter Reference](reference/playbook-parameters.md) | ✅ Complete |
| [ADR Status Reference](adrs/README.md) | ✅ Complete (36 ADRs) |
| [Environment Variables Reference](reference/environment-variables.md) | ✅ Complete |
| [Workflow Survey Parameters](reference/workflow-survey-parameters.md) | ✅ Complete |
| [Bootstrap Prerequisites Reference](reference/bootstrap-prerequisites.md) | ✅ Complete |

**When to use**: You need to look up exact syntax, parameters, or system facts.

---

### 💡 Explanations (Understanding-Oriented)

**Purpose**: Understand the "why" behind architectural decisions.

| Explanation | Status |
|-------------|--------|
| [Bootstrap vs Workflow Layers](explanations/bootstrap-vs-workflow-layers.md) | ✅ Complete |
| [Multi-Workflow Architecture](explanations/multi-workflow-architecture.md) | ✅ Complete |
| [Certificate Management Decisions](explanations/certificate-management-decisions.md) | ✅ Complete |
| [Operator Validation Framework](explanations/operator-validation-framework.md) | ✅ Complete |
| [Airflow → AAP Migration](explanations/airflow-to-aap-migration.md) | ✅ Complete |
| [Nested KVM Hypervisor Architecture](explanations/nested-kvm-hypervisor-architecture.md) | ✅ Complete |

**When to use**: You want to understand design decisions and trade-offs.

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

**v1.4.0 Coverage**:
- ✅ Tutorials: 3/3 complete (100%)
- ✅ How-To Guides: 8/8 complete (100%)
- ✅ Reference: 6/6 complete (100%)
- ✅ Explanations: 6/6 complete (100%)

**Total Documentation**: 23 files, 100% coverage

---

## 🤝 Contributing

Found a gap in the documentation? See [CONTRIBUTING.md](../CONTRIBUTING.md) for how to add or improve docs following Diátaxis principles.

---

## 📚 Further Reading

- [Diátaxis Framework](https://diataxis.fr/) - Documentation philosophy
- [ADR-0032: Multi-Workflow Architecture](adrs/adr-0032-aap-workflow-orchestration-strategy.md) - Architectural foundation
- [CHANGELOG.md](../CHANGELOG.md) - Release history
