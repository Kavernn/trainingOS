# Execution Instruction

Claude must treat this document as an **audit procedure**.

When asked to run a Supabase audit, Claude must:

1. Read this file
2. Execute every step described in the document
3. Produce the required report

# Supabase Data Integrity Rules

This document defines the **data integrity rules and audit procedure** for the application.

Supabase is the **single source of truth** for all persistent data.

Claude Code must follow these rules when analyzing, modifying, or generating code.

---

# 1. Supabase Architecture Rule

All persistent data must be stored in Supabase.

The application must never rely on local state as the source of truth.

Allowed pattern:

UI → mutation → Supabase → refresh state

Avoid:

UI → local state mutation → Supabase later

---

# 2. CRUD Verification Requirements

Every feature that interacts with Supabase must support and verify:

READ
CREATE
UPDATE
DELETE

For every view that displays data:

### READ

Verify the correct records are fetched from Supabase.

Ensure:

* correct table
* correct columns
* correct filters
* correct mapping to UI components.

---

### CREATE

If a view allows creating data:

Verify:

* insert query is sent to Supabase
* inserted record appears immediately in UI
* no stale UI state.

---

### UPDATE

If editing is possible:

Verify:

* update query targets the correct record
* changes persist in Supabase
* UI reflects the change without manual refresh.

---

### DELETE

If deletion is possible:

Verify:

* record is removed in Supabase
* UI updates immediately
* no orphaned state remains.

---

# 3. Automatic Synchronization

After every mutation:

* UI must update automatically
* data must be re-fetched or updated optimistically
* Supabase remains the single source of truth.

Allowed approaches:

refetch after mutation
or
optimistic update with rollback.

---

# 4. Special Data Relationship

The app contains two important keys:

inventory
program

inventory = master list of exercises
program = subset of exercises selected from inventory

These rules are mandatory.

---

## Delete Rule

Deleting an exercise from `program`:

Must remove it **only from program**

Must **NOT delete it from inventory**

---

## Update Rule

Editing an exercise inside `program`:

Must also update the corresponding exercise inside `inventory`.

Meaning:

program edit → propagate update to inventory

---

# 5. Audit Procedure

When auditing the codebase:

1. Locate every Supabase interaction.
2. List every View that reads data.
3. Verify CRUD operations for each feature.
4. Verify program/inventory logic.
5. Identify any desynchronization risk.

---

# 6. Required Audit Report Format

Claude must output:

1. Supabase access map (all queries)
2. CRUD validation table per view
3. program vs inventory validation
4. detected problems
5. recommended fixes

