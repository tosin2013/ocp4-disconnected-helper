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
| End-to-End Disconnected Deployment | 2-3 hours | Intermediate | 🚧 Planned |

**When to use**: You're new to this project or want to learn by following along.

---

### 🔧 How-To Guides (Task-Oriented)

**Purpose**: Solve a specific problem. Assume you're already competent.

| Guide | Category | Status |
|-------|----------|--------|
| [Deploy Workflow 1 (Registry Infrastructure)](how-to/deploy-workflow-1-registry-infrastructure.md) | Deployment | ✅ Complete |
| Deploy Workflow 2 (Image Mirroring) | Deployment | 🚧 Planned |
| Troubleshoot Workflow Failures | Troubleshooting | 🚧 Planned |
| Resolve: AAP Login Failure | Troubleshooting | 🚧 Planned |
| Resolve: oc-mirror Async Cache Errors | Troubleshooting | 🚧 Planned |
| Resolve: Registry TLS Authentication Failure | Troubleshooting | 🚧 Planned |
| Add Custom Operators | Configuration | 🚧 Planned |
| Switch Registry Types | Configuration | 🚧 Planned |

**When to use**: You know what you want to do, just need the steps.

---

### 📖 Reference (Information-Oriented)

**Purpose**: Look up accurate technical facts.

| Reference | Status |
|-----------|--------|
| [AAP Workflow Catalog](AAP_WORKFLOW_CATALOG.md) | ✅ Complete |
| Playbook Parameter Reference | 🚧 Planned |
| [ADR Status Reference](adrs/README.md) | ✅ Complete (36 ADRs) |
| Environment Variables Reference | 🚧 Planned |
| Survey Parameter Reference | 🚧 Planned |
| Bootstrap Prerequisites Reference | 🚧 Planned |

**When to use**: You need to look up exact syntax, parameters, or system facts.

---

### 💡 Explanations (Understanding-Oriented)

**Purpose**: Understand the "why" behind architectural decisions.

| Explanation | Status |
|-------------|--------|
| Bootstrap vs Workflow Layers | 🚧 Planned |
| Multi-Workflow Architecture | 🚧 Planned |
| Certificate Management Decisions | 🚧 Planned |
| Operator Validation Framework | 🚧 Planned |
| Airflow → AAP Migration | 🚧 Planned |
| Nested KVM Hypervisor Architecture | 🚧 Planned |

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
→ Read **Explanations**: (Coming in v1.4)

---

## 📊 Documentation Status

**v1.3.0 Coverage**:
- ✅ Tutorials: 2/3 complete (66%)
- 🚧 How-To Guides: 1/8 complete (12%)
- ✅ Reference: 2/6 complete (33%)
- 🚧 Explanations: 0/6 complete (0%)

**Next Release (v1.4)**:
- Complete all How-To Guides
- Add Explanation documents
- Complete remaining Reference docs

---

## 🤝 Contributing

Found a gap in the documentation? See [CONTRIBUTING.md](../CONTRIBUTING.md) for how to add or improve docs following Diátaxis principles.

---

## 📚 Further Reading

- [Diátaxis Framework](https://diataxis.fr/) - Documentation philosophy
- [ADR-0032: Multi-Workflow Architecture](adrs/adr-0032-aap-workflow-orchestration-strategy.md) - Architectural foundation
- [CHANGELOG.md](../CHANGELOG.md) - Release history
