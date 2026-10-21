# ApexCore DB

A PostgreSQL-only transactional core for an e-commerce style OLTP system. Inventory, orders, payments, and audit logic live in the database as schemas, tables, stored procedures, triggers, and views. There is no ORM layer.

> **Status: work in progress.** The schema and procedures are being developed and reviewed. Some business rules are known to be incomplete or incorrect (see [Known Issues](#known-issues)). Do not use this code with real data yet.

---

## What this project is

Most web applications put business rules in an ORM or in application code. ApexCore moves the important rules into the database so that they are enforced no matter which client writes the data:

- Stock cannot go negative, and stock changes are recorded as movements.
- An order reserves stock inside a single transaction.
- Every change to key tables is written to an audit log.
- Reports read from views that are separate from the write path.

The project is intended as a reference for relational database design: schema separation, row-level locking, transactional procedures, ledgers, soft deletes, and migration discipline.

### Scope

- **OLTP only.** Low-latency writes, row-level locking, and consistency. Analytics are meant to be fed from the outbox or CDC, not run on the transactional tables.
- **Database only.** There is no API, UI, or payment gateway integration in this repository. The payment procedures record results that an external service provides.

---

## Architecture

### Schemas

| Schema      | Purpose                                                              |
|-------------|----------------------------------------------------------------------|
| `core`      | Users and the migration history table (`schema_migrations`).         |
| `inventory` | Categories, products, warehouses, stock levels, stock movements, price history. |
| `orders`    | Orders, order items, and the `order_item_input` composite type.      |
| `payments`  | Payment transactions and refund handling.                            |
| `audit`     | Audit log table and the trigger function that writes to it.          |
| `reporting` | Read-only views for operational and financial reports.               |

### Main tables

- `core.users`
- `inventory.categories`, `inventory.products`, `inventory.warehouses`
- `inventory.stock_levels`: quantity and reserved quantity per (warehouse, product)
- `inventory.stock_movements`: append-only log of every stock change
- `inventory.price_history`: written by a trigger when a product price changes
- `orders.orders`, `orders.order_items`
- `payments.transactions`
- `audit.audit_logs`

### Stored procedures

Stock:
- `inventory.receive_stock`: add stock from a purchase receipt
- `inventory.adjust_stock`: manual correction with a reason
- `inventory.transfer_stock`: move stock between warehouses (see Known Issues)
- `inventory.record_stock_movement`: the single place that writes movements

Orders:
- `orders.place_order`: create an order and reserve stock
- `orders.cancel_order`: cancel an order and release reservations
- `orders.ship_order`, `orders.deliver_order`: status transitions
- `orders.return_order`: returns and stock restoration

Payments:
- `payments.process_payment`: record a payment attempt
- `payments.refund_payment`: record a refund

### Views

- `reporting.v_order_financial_summaries`: paid, refunded, and balance per order
- `reporting.v_stock_availability`: available quantity per product and warehouse
- `reporting.v_warehouse_valuation`: stock value per warehouse

### Patterns used

- **Soft deletes** with `deleted_at` columns.
- **Partial unique indexes** for uniqueness among active rows.
- **Append-only ledgers** for stock movements and payment transactions.
- **Row locks** (`SELECT ... FOR UPDATE`) on stock rows before changing them.
- **Audit triggers** that record old and new values as JSON.
- **Event outbox** table for publishing changes to other systems.

---

## Repository layout

```text
apexcore-db/
├── db/
│   ├── migrations/   # Numbered forward migrations (0001 to 0029)
│   ├── rollback/     # Matching down scripts (not complete, see Known Issues)
│   └── tests/        # SQL test scripts that create their own fixtures
├── .gitignore
└── README.md
```

Migrations are applied in numeric order. Each file is meant to be run once and never edited after it is merged. Changes go into a new migration.

---

## Requirements

- PostgreSQL 16 or newer (the migrations use `gen_random_uuid()`, `clock_timestamp()`, and generated columns).
- `psql` or any client that can run multi-statement SQL scripts.
- Extensions created by migration `0003` (for example `pgcrypto`, `pg_stat_statements`).

---

## Getting started

There is no runner script yet. Apply the migrations manually in order on an empty database:

```bash
createdb apexcore
for f in db/migrations/*.sql; do
  echo "Applying $f"
  psql -v ON_ERROR_STOP=1 -d apexcore -f "$f" || break
done
```

Run a test script (each test wraps its work in a transaction):

```bash
psql -v ON_ERROR_STOP=1 -d apexcore -f db/tests/test_receive_stock.sql
```

> Some tests currently pick existing rows with `LIMIT 1` and expect data to already be present. They will fail on an empty database. See Known Issues.

---

## Example

```sql
-- Receive 100 units of a product into a warehouse
CALL inventory.receive_stock(
    p_warehouse_id => '<warehouse-uuid>',
    p_product_id   => '<product-uuid>',
    p_quantity     => 100,
    p_reference_id => NULL,
    p_notes        => 'Initial stock'
);

-- Place an order with two items
CALL orders.place_order(
    p_customer_id      => '<customer-uuid>',
    p_order_number     => 'ORD-0001',
    p_shipping_address => '{"city": "Tehran"}'::jsonb,
    p_items            => ARRAY[
        ROW('<product-uuid-1>', 2)::orders.order_item_input,
        ROW('<product-uuid-2>', 1)::orders.order_item_input
    ],
    p_notes            => NULL,
    p_order_id         => NULL
);
```

Check the exact parameter lists in the migration files before relying on these examples; signatures have changed between migrations.

---

## Design decisions

- **Logic in the database.** Rules that must always hold (stock, order status, audit) are enforced in procedures and constraints, not left to each client.
- **Movements are the source of truth for stock changes.** `stock_levels` holds the current value, and `stock_movements` explains how it got there.
- **Prices come from the database.** `place_order` reads `base_price` from `inventory.products` and does not accept a price from the client.
- **Migrations are forward-only in spirit.** Rollbacks exist for learning and local resets, not for production recovery.

---

## Known issues

This project is not production ready. The main problems found in review are:

**Data integrity**
- `place_order` checks `quantity` instead of `quantity - reserved_quantity`, so it can oversell under concurrent orders.
- `return_order` may restore stock more than once.
- `cancel_order` does not check the order status and can release reservations for shipped orders.
- Lock ordering is not consistent across procedures, so deadlocks are possible.

**Migrations**
- Migration `0028` removes both `transfer_stock` procedures and does not create a replacement. Stock transfer is currently missing.
- Migration `0028` rollback refers to a signature that no longer exists.
- Some migrations have no rollback (`0006`, `0009`, `0024`), and some rollbacks are incorrect (for example `0012` uses `DROP FUNCTION` on a procedure).
- Migration history is not consistently recorded in `schema_migrations`.

**Business rules**
- `process_payment` does not move the order out of `PENDING` on failure, and has no retry limit.
- `refund_payment` does not update order or transaction status, and accepts any amount.
- Currency is hard-coded to `USD` in several procedures.
- Audit triggers cover only some tables. `changed_by` is not set for orders.

**Tests**
- Tests depend on existing data and do not start from an empty database.
- Some tests catch `EXCEPTION WHEN others`, so a missing error is reported as a pass.
- There are no concurrency tests.

**Documentation**
- The schema name `iam` does not exist in this repository.
- There are no `seeds/` or `docs/` directories yet.

---

## Roadmap

1. Fix stock arithmetic, lock ordering, and the missing transfer procedure.
2. Fix order cancellation, return, and payment state transitions.
3. Add a migration runner and run everything in CI against a real PostgreSQL.
4. Replace ad hoc tests with pgTAP or equivalent, with no silent exception handling.
5. Add concurrency tests for oversell and deadlock cases.
6. Add an ERD, architecture decision records, and seed data.
7. Complete rollbacks for every migration.

---

## Contributing

Create a new numbered migration for every schema change. Do not edit a migration that has already been merged. Add a test for every procedure that changes stock or money.

## License

Not specified yet.
