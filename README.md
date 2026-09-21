# 🚀 ApexCore: High-Throughput Transactional Engine (OLTP)

> **Enterprise-Grade PostgreSQL Core Engine designed without ORM dependencies, built for strict ACID compliance, data integrity, and high-concurrency workloads.**

---

## 📌 Executive Summary

**ApexCore** is a production-ready, pure-database backend engine developed in PostgreSQL. The project serves as an architectural demonstration of modern relational database engineering, enforcing business rules and transactional integrity at the database layer rather than relying on heavy application-level ORM frameworks.

By leveraging pure SQL, procedural logic (`PL/pgSQL`), advanced indexing, strict constraints, and transaction isolation, ApexCore achieves maximum throughput, zero data corruption, and robust observability.

---

## 🏗 System Architecture & Philosophy

Modern web applications often shift business logic to ORMs (e.g., Hibernate, Prisma, TypeORM), introducing N+1 query overhead, unoptimized lock contention, and impedance mismatches. **ApexCore** reverses this paradigm:

* **Zero-ORM Philosophy:** Pure, optimized, and predictable SQL execution with direct connection management.
* **Database as Single Source of Truth:** Business constraints, foreign keys, check rules, and state machines are enforced natively inside the database engine.
* **Strict ACID Compliance:** Guaranteed data consistency under high-concurrency inventory adjustments and checkout transactions.
* **Domain-Driven Schemas:** Logical separation using PostgreSQL Schemas (`iam`, `inventory`, `orders`, `audit`).

---

## 🧭 System Boundary (OLTP vs. OLAP)

ApexCore is strictly an **OLTP (Online Transaction Processing)** engine:
* **Focus:** Millisecond-level latency, write-heavy concurrency, and row-level locking.
* **Scope:** Serves as the operational single-source-of-truth backend. Analytical workloads (OLAP / Data Warehousing) are decoupled via outbox/CDC patterns to ensure non-blocking transactional performance.

---

## 🛠 Tech Stack & Tooling

* **Database Engine:** PostgreSQL 16+
* **IDE / Tooling:** JetBrains DataGrip
* **Migration Strategy:** Versioned, immutable, forward-only SQL migrations (`db/migrations`) paired with deterministic rollbacks (`db/rollback`).
* **Design Patterns:** Soft Deletes, Hierarchical Trees (Self-Referential), Event Outbox, Audit Trail Triggers, Partial Unique Indexing.

---

## 📂 Repository Structure
```plaintext
apexcore/
├── db/
│   ├── migrations/             # Immutable, numbered migration scripts
│   │   ├── 0001_init_schemas.sql
│   │   ├── 0002_enable_extensions.sql
│   │   └── ...
│   ├── rollback/               # Deterministic down-migrations
│   ├── seeds/                  # Deterministic test & demo datasets
│   └── tests/                  # pgTAP / unit assertion scripts
├── docs/                       # Architecture decisions (ADRs) & ERDs
└── README.md
