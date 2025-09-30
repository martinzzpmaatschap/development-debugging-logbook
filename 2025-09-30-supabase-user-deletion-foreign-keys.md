---
title: "Supabase User Deletion with Foreign Key Constraints"
date: 2025-09-30
tags: [supabase, postgresql, foreign-keys, debugging, cascade-delete]
severity: medium
status: resolved
---

# Debug Log: Supabase User Deletion with Foreign Key Constraints

Debug Log: Supabase User Deletion with Foreign Key Constraints
Date: September 30, 2025
Issue: Cannot delete users via Supabase Auth UI - "Database error deleting user"
Stack: Supabase PostgreSQL with auth.users schema

Problem Summary
Foreign key constraints without ON DELETE CASCADE block user deletion. Supabase Auth UI cannot remove users when related data in other tables still references them.
Symptoms
Failed to delete user: Database error deleting user
The UI provides no details about which table is blocking the deletion.

Diagnostic Steps
Step 1: Identify Tables Referencing auth.users
sqlSELECT
  tc.table_name, 
  kcu.column_name,
  rc.delete_rule
FROM information_schema.table_constraints AS tc 
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.referential_constraints AS rc
  ON tc.constraint_name = rc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_schema = 'public'
  AND kcu.column_name LIKE '%user_id%';
Step 2: Attempt Direct SQL Delete for Precise Error
sqlDELETE FROM auth.users WHERE id = '<user-uuid>';
This reveals the exact blocking table:
ERROR: 23503: update or delete on table "users" violates 
foreign key constraint "feedback_user_id_fkey" on table "feedback"
DETAIL: Key (id)=(...) is still referenced from table "feedback"

Solution: Manual Cleanup in Correct Order
Get User IDs First
sqlSELECT id, email FROM auth.users 
WHERE email IN ('email1@test.com', 'email2@test.com');
Delete in Reverse Dependency Order
sql-- 1. Direct references to auth.users
DELETE FROM feedback 
WHERE user_id IN ('<uuid1>', '<uuid2>');

-- 2. Time entries (via employees)
DELETE FROM time_entries 
WHERE employee_id IN (
  SELECT id FROM employees 
  WHERE user_id IN ('<uuid1>', '<uuid2>')
);

-- 3. Kilometers (via employees)
DELETE FROM kilometers
WHERE employee_id IN (
  SELECT id FROM employees 
  WHERE user_id IN ('<uuid1>', '<uuid2>')
);

-- 4. Costs (via projects via employees.company_id)
DELETE FROM costs
WHERE project_id IN (
  SELECT id FROM projects 
  WHERE company_id IN (
    SELECT company_id FROM employees 
    WHERE user_id IN ('<uuid1>', '<uuid2>')
  )
);

-- 5. Employees (has CASCADE but other tables reference it)
DELETE FROM employees 
WHERE user_id IN ('<uuid1>', '<uuid2>');

-- 6. Finally, delete users
DELETE FROM auth.users 
WHERE id IN ('<uuid1>', '<uuid2>');

Implementation: Add CASCADE to Prevent Future Issues
Check Current Constraint
sqlSELECT 
  conname as constraint_name,
  conrelid::regclass as table_name,
  confrelid::regclass as referenced_table,
  CASE confdeltype 
    WHEN 'a' THEN 'NO ACTION'
    WHEN 'r' THEN 'RESTRICT'
    WHEN 'c' THEN 'CASCADE'
    WHEN 'n' THEN 'SET NULL'
    WHEN 'd' THEN 'SET DEFAULT'
  END as on_delete_action
FROM pg_constraint
WHERE conname LIKE '%feedback%user%';
Add CASCADE to Foreign Keys
sql-- Drop existing constraint
ALTER TABLE feedback
DROP CONSTRAINT feedback_user_id_fkey;

-- Add new constraint with CASCADE
ALTER TABLE feedback
ADD CONSTRAINT feedback_user_id_fkey 
  FOREIGN KEY (user_id) 
  REFERENCES auth.users(id) 
  ON DELETE CASCADE;
Repeat for All Tables Referencing auth.users
Template for each table:
sqlALTER TABLE <table_name>
DROP CONSTRAINT <constraint_name>,
ADD CONSTRAINT <constraint_name>
  FOREIGN KEY (<column_name>) 
  REFERENCES auth.users(id) 
  ON DELETE CASCADE;

Found Constraints (This Case)
TableColumnReferencesDelete RuleStatusemployeesuser_idauth.users.idCASCADE✓ OKfeedbackuser_idauth.users.idNO ACTION✗ BLOCKStime_entriesemployee_idemployees.id?Checkcostsproject_idprojects.id?Checkkilometersemployee_idemployees.id?Check

Why This Happens

Supabase Auth UI has no visibility into public schema constraints
Without CASCADE, manual deletion in correct order is required
SQL direct delete provides exact error messages
Each blocking constraint must be discovered iteratively


Prevention Checklist

 Always add ON DELETE CASCADE when creating foreign keys to auth.users
 Document all table dependencies in schema design
 Test user deletion in development environment
 Create a cleanup script for production use
 Monitor Supabase logs for constraint violations


Quick Reference for Future Debugging
sql-- 1. Find what's blocking
DELETE FROM auth.users WHERE id = '<uuid>';
-- Read error message for table name

-- 2. Delete blocking records
DELETE FROM <blocking_table> WHERE user_id = '<uuid>';

-- 3. Retry step 1 until no errors

-- 4. Add CASCADE to prevent recurrence
ALTER TABLE <blocking_table>
DROP CONSTRAINT <fkey_name>,
ADD CONSTRAINT <fkey_name>
  FOREIGN KEY (user_id) 
  REFERENCES auth.users(id) 
  ON DELETE CASCADE;

Key Takeaway
Always configure ON DELETE CASCADE on foreign keys to auth.users during initial table creation. This single configuration change eliminates the entire debugging session and allows safe user deletion via the Supabase UI.
