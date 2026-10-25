# ApexCore Database System

**ApexCore** is a robust, high-performance OLTP database system built on **PostgreSQL 16+**, designed for enterprise inventory management, order processing, and strict stock tracking with ACID compliance.

---

## 🏗 Architecture & Schemas

The database architecture is logically divided into three primary schemas:

1. **`core` Schema:**
   - Manages core system entities such as users (`core.users`), authentication, and general system utilities.

2. **`inventory` Schema:**
   - Handles product catalog, categories, pricing history, warehouses, and real-time inventory states (`inventory.stock_levels`).
   - Implements strict immutable audit logging for all stock adjustments via `inventory.stock_movements`.

3. **`orders` Schema:**
   - Manages customer orders (`orders.orders`) and order line items (`orders.order_items`).
   - Implements complete order lifecycle management through PL/pgSQL stored procedures.

---

## 🔄 Core Features & Workflows

- **Strict ACID Compliance:** Guaranteed transactional safety with robust foreign keys, check constraints, and computed/generated columns.
- **Inventory Management Procedures:**
   - `inventory.receive_stock`: Adds stock to a warehouse from purchase receipts and logs movements.
   - Standardized stock movement calculations and constraint validations (`chk_stock_movement_math`).
- **Order Lifecycle Procedures:**
   - `orders.place_order`: Validates inventory, reserves stock, creates order records, and records reservation movements.
   - Additional workflow procedures: `cancel_order`, `ship_order`, `deliver_order`, and `return_order`.
- **Immutable/Transactional Migrations:** Managed via versioned migration and rollback scripts stored in the repository.

---

## 🛠 Tech Stack

- **Database:** PostgreSQL 16+
- **Language:** PL/pgSQL
- **Version Control:** Git & GitHub (Conventional Commits standard)

---

## 📂 Project Structure
```text
ApexCore/
├── db/
│   ├── migrations/     # Versioned SQL migration scripts (0001 to latest)
│   ├── rollback/       # Corresponding rollback scripts
│   └── tests/          # Scenario-based SQL test scripts
├── docs/               # Architecture diagrams and system documentation
└── README.md
