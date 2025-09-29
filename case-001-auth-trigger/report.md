🔍 DEBUG REPORT: Supabase Authentication Flow & SQL Trigger Issues
1. EXECUTIVE SUMMARY
Core Problem (2-3 sentences): A persistent 500: Database error saving new user occurred during user sign-up. The root cause was a cascade of errors: an SQL trigger using an incorrect column name (name instead of full_name), which was masked by a missing company_name field from the frontend. The persistent nature of the problem was incorrectly attributed to a "ghost trigger" (database caching) but was actually due to the faulty code being repeatedly reintroduced.

Debugging Duration: Approximately 3 days of intensive, iterative debugging.

Final Solution (1 sentence): The trigger-based approach was completely replaced by an explicit, manual manual_user_setup function, which is called via RPC from the frontend after a successful signUp().

Project Impact: A significant development delay, but it led to a deeper understanding of the interaction between the frontend, Supabase Auth, and PostgreSQL, resulting in a more robust architecture.

2. PROBLEM ANALYSIS
2.1 Initial Symptoms
Error Messages (as they appeared):

500: Database error saving new user (Generic Supabase Auth error)

ERROR: column "name" of relation "employees" does not exist (The most persistent, recurring error in the Auth logs)

ERROR: null value in column "name" of relation "companies" violates not-null constraint (An early error that revealed the frontend data problem)

ERROR: cannot drop function handle_new_user_setup() because other objects depend on it (Database protection, which led to using CASCADE)

Failing Actions: New user registration. The supabase.auth.signUp() call resulted in a 500 error, and the user was not correctly saved to the database.

Working Features: The application was largely functional before this issue escalated. Existing users could log in, and the TimeEntry.tsx component had been successfully refactored.

2.2 Misleading Clues
Incorrect Hypotheses:

The "Ghost Trigger" / Caching Hypothesis: The persistent return of the column "name" does not exist error led to the assumption that Supabase/PostgreSQL was caching an old version of the trigger. This was incorrect. The actual cause was that the faulty code (INSERT ... (name)) was repeatedly reintroduced in new scripts.

RLS as the Primary Cause: Initially, Row Level Security (RLS) was suspected as the culprit. While RLS did cause some issues (like infinite recursion), disabling it was not enough to solve the core problem.

Time Wasted on Wrong Paths: Significant time was lost repeatedly trying to DROP and CREATE OR REPLACE the trigger function, believing this would solve a caching issue.

Why They Were Misleading: The symptoms were deceptive. Because the column "name" does not exist error kept returning even after supposed fixes, a caching problem seemed like the only logical explanation. In reality, the "fixes" themselves still contained the error, or other errors (like the NULL constraint on companies.name) were masking the name/full_name issue.

3. DEBUGGING CHRONOLOGY
Phase 0: Successful Component Refactoring (Context)
Before the authentication issues, the app was stable. The TimeEntry.tsx component (1000+ lines) was successfully split into five sub-components: TimerModule.tsx, TimeEntryForm.tsx, TimeEntryList.tsx, TimeEntryCard.tsx, and TimeEntryFilters.tsx.

During this refactoring, a minor styling issue caused by a missing Heroicons package was resolved by switching to Lucide icons.

Key Takeaway: The authentication debugging began in an otherwise fully functional application.

Phase 1: Initial Authentication Problems & Frontend Fixes
Problem: Database error saving new user. The first clear error in the Auth logs was null value in column "name" of relation "companies" violates not-null constraint.

Cause: The frontend (Auth.tsx) was not sending the company_name in the signUp() call.

Solution: Auth.tsx was updated to include a company_name field and send this data in the options.data of the signUp call. This resolved the NULL constraint error but immediately revealed the next, deeper problem.

Phase 2: The Persistent "name vs. full_name" Error
Critical Discovery: After fixing the company_name issue, the error that would dominate the rest of the process appeared:

ERROR: column "name" of relation "employees" does not exist
Debugging Journey:

Database Schema Verification: A SELECT column_name FROM information_schema.columns WHERE table_name = 'employees' unambiguously confirmed the column was named full_name.

Trigger Code Adjustments: Numerous attempts were made to modify the trigger function to use full_name. These attempts repeatedly failed.

"Ghost Trigger" Diagnosis (Incorrect): Because the error persisted despite the alleged fixes, the hypothesis of a "ghost trigger" cached by the database emerged.

Forced Reinstallation: Attempts were made using DROP FUNCTION ... CASCADE; to destroy the function and all dependent objects for a clean reinstallation. This also appeared to fail.

Phase 3: Strategic Pivot & The RPC Solution
A New Direction: After many failed attempts, the strategic decision was made to stop fighting the trigger and adopt a fundamentally different approach.

New Approach:

The automatic AFTER INSERT trigger was completely removed.

A manual manual_user_setup() function was created in the database.

The frontend (Auth.tsx) was modified to explicitly call this function via supabase.rpc() after a successful signUp().

Result: This approach worked immediately and flawlessly, proving the problem lay within the trigger's automation, not the core SQL logic.

4. DEFINITIVE SOLUTION
Backend (SQL):
The trigger was completely removed and replaced with an RPC function.

SQL

-- Remove the trigger and its associated function entirely
DROP FUNCTION IF EXISTS public.handle_new_user_setup() CASCADE;

-- Create a manual setup function to be called via RPC
CREATE OR REPLACE FUNCTION public.manual_user_setup(
  p_user_id UUID,
  p_email TEXT,
  p_company_name TEXT,
  p_full_name TEXT
)
RETURNS void AS $$
DECLARE
  v_company_id UUID;
BEGIN
  -- Controlled setup logic:
  -- 1. Create the company
  INSERT INTO public.companies (name)
  VALUES (p_company_name)
  RETURNING id INTO v_company_id;

  -- 2. Create the employee record using the verified 'full_name' column
  INSERT INTO public.employees (user_id, company_id, email, full_name, role)
  VALUES (p_user_id, v_company_id, p_email, p_full_name, 'admin');

  -- 3. Update the user's metadata
  UPDATE auth.users
  SET raw_user_meta_data = raw_user_meta_data || jsonb_build_object('company_id', v_company_id)
  WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
Frontend (TypeScript):
The handleSignUp function in Auth.tsx was adapted to execute the RPC call.

TypeScript

// After a successful signup in Auth.tsx:
const { data: authData, error: authError } = await supabase.auth.signUp({
  email,
  password,
});

if (authError) throw authError;

// Call the manual setup function via RPC
if (authData.user) {
  const { error: rpcError } = await supabase.rpc('manual_user_setup', {
    p_user_id: authData.user.id,
    p_email: email,
    p_company_name: companyName,
    p_full_name: fullName,
  });

  if (rpcError) throw rpcError;
}
5. ROOT CAUSE ANALYSIS
Why the Problem Was So Persistent: A Cascade of Errors

The issue was not a single "ghost trigger" but a cascade of four separate, compounding errors:

Initial Fault (Backend): The trigger code used the column name when the database schema had full_name.

Masking Fault (Frontend): The frontend did not send a company_name. This caused a NOT NULL constraint error, which hid the underlying name/full_name fault.

Diagnostic Error (Human): After the frontend was fixed, the name/full_name error surfaced. Its persistence led to the incorrect diagnosis of "database caching."

Consistency Error (Human): In the rush to fix the "cache" problem, the original fault (INSERT ... (name)) was repeatedly reintroduced into the "fixed" scripts, perpetuating the cycle.

This "whack-a-mole" situation, where fixing one error only revealed the next, created the illusion of an unsolvable, mysterious problem.

6. PREVENTION STRATEGIES
✅ DOs:
Schema-First Verification:

ALWAYS check the schema before writing code that depends on it.

SQL

-- Before writing a trigger:
SELECT column_name FROM information_schema.columns
WHERE table_name = 'employees';
Incremental Builds:

Start with the smallest possible working trigger (e.g., only the company insert).

Test after every single addition. Never implement multiple INSERTs or UPDATEs at once.

Frontend-Backend Contract:

Explicitly document what metadata the frontend must provide.

Validate this data's existence in the trigger before performing INSERT operations.

RLS Strategy:

ALWAYS start with RLS disabled when developing triggers.

Only enable RLS once the core functionality is proven to work, and test each policy individually.

Consider Trigger Alternatives:

For complex, multi-step setups like user onboarding, an RPC call (like the final solution) is superior. It's explicit, easier to debug, and less prone to "magic" failures.

⚠️ DON'Ts:
❌ Don't assume CREATE OR REPLACE refreshes a trigger cache. Use a full DROP FUNCTION ... CASCADE; followed by CREATE FUNCTION for a guaranteed clean installation.

❌ Don't debug multiple features at once. Isolate the problem to the smallest reproducible case.

❌ Don't keep fixing if 3+ attempts fail. Stop, rethink your strategy, and choose a different approach (e.g., trigger → RPC).

❌ Don't ignore Auth logs. For errors related to auth.users, the Supabase Auth logs are the most reliable source, not the general Postgres logs.
