# Supabase & React: A Developer's Logbook

This repository documents my journey building a TimeTracker application with React, TypeScript, and Supabase. It serves as a collection of detailed debugging reports and architectural decisions. As a starting developer, I'm using this space to solidify my learnings and help others who might encounter similar issues.

---

## 📂 Case Studies

### Case #001: The "Ghost Trigger" - Debugging a Supabase Auth Cascade Failure

A multi-day deep-dive into a persistent `500: Database error saving new user` error caused by a cascading series of issues, including a "ghost" PostgreSQL trigger, frontend data mismatches, and RLS (Row Level Security) complexities. The final solution involved a strategic shift from an automated trigger to an explicit RPC call.

* **[📄 Read the Full Debug Report](./case-001-auth-trigger/report.md)**
* **[💬 Relive the Interactive Debugging Session (Gemini Chat)](https://g.co/gemini/share/3982645bdc70)**

---

### Debug Log 2025-09-30: Supabase User Deletion with Foreign Key Constraints

Users could not be deleted via the Supabase Auth UI ("Database error deleting user") because foreign keys without `ON DELETE CASCADE` blocked the delete. Covers how to find the blocking table with a direct SQL delete, the correct manual cleanup order, and adding `CASCADE` to prevent it from happening again.

* **[📄 Read the Debug Log](./2025-09-30-supabase-user-deletion-foreign-keys.md)**

---

### Case #002: De RLS-Vesting - Architectuurconflicten in een Multi-Tenant App

Securing a multi-tenant TimeTracker with Row Level Security turned into a full architecture audit: 10+ outdated, conflicting policies undermined the new rules, and the `invite-employee` Edge Function clashed with the database trigger. Resolved through a phased cleanup and a single trigger-driven onboarding flow. *(Written in Dutch.)*

* **[📄 Read the Case Study](./case-002-rls-vesting-architectuurconflicten.md)**

---

### Case #003: Espanso Detection Failure on Ubuntu 24.04 — GNOME Shortcuts Workaround

Espanso 2.3.0 parsed its config and could inject text, but never detected typed triggers on Ubuntu 24.04 + GNOME + Xorg. Testing detection and injection separately showed only detection was broken; the workaround binds GNOME keyboard shortcuts to `espanso match exec`.

* **[📄 Read the Case Study](./case-003-espanso-detection-failure.md)**
* **Files:** [`trust_prompts.yml`](./trust_prompts.yml) · [`setup-trust-shortcuts.sh`](./setup-trust-shortcuts.sh)

---

### Case #004: Logbook Housekeeping — Index, Broken Link, Lost Markdown

A short report on repairing this logbook itself: missing README entries, a dead link caused by a duplicate-download filename (`trust_prompts (1).yml`), and a debug log whose markdown formatting was lost.

* **[📄 Read the Case Study](./case-004-logbook-housekeeping.md)**

---

*More case studies will be added as the project progresses.*
