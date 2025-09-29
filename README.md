# Supabase & React: A Developer's Logbook

This repository documents my journey building a TimeTracker application with React, TypeScript, and Supabase. It serves as a collection of detailed debugging reports and architectural decisions. As a starting developer, I'm using this space to solidify my learnings and help others who might encounter similar issues.

---

## 📂 Case Studies

### Case #001: The "Ghost Trigger" - Debugging a Supabase Auth Cascade Failure

A multi-day deep-dive into a persistent `500: Database error saving new user` error caused by a cascading series of issues, including a "ghost" PostgreSQL trigger, frontend data mismatches, and RLS (Row Level Security) complexities. The final solution involved a strategic shift from an automated trigger to an explicit RPC call.

* **[📄 Read the Full Debug Report](./case-001-auth-trigger/report.md)**
* **[💬 Relive the Interactive Debugging Session (Gemini Chat)](PASTE_YOUR_SHARED_GEMINI_LINK_HERE)**

---

*More case studies will be added as the project progresses.*
