# Case Study #002: De RLS-Vesting - Architectuurconflicten in een Multi-Tenant App

> **Kernles**: RLS-implementatie is niet alleen een beveiligingstaak—het is een volledige architectuuraudit die verborgen conflicten tussen frontend, backend en legacy code blootlegt.

---

## 🎯 KERNVERHAAL

De missie was om een multi-tenant TimeTracker-app te beveiligen met Row Level Security (RLS) voor strikte data-isolatie tussen bedrijven. Dit proces legde echter twee kritieke architectuurproblemen bloot:

1. **10+ verouderde, conflicterende RLS-policies** die nieuwe beveiligingsregels ondermijnden
2. **Een fundamenteel conflict** tussen een moderne, veilige architectuur en een overbodig geworden `invite-employee` Edge Function

De oplossing vereiste een **gefaseerde, forensische opschoning** en het vaststellen van een definitieve, duale onboarding-architectuur aangedreven door een "slimme" database-trigger.

**Tijdlijn**: 30 september - 3 oktober 2025 (permission issues → RLS implementatie → productie)

---

## 🏛️ ARCHITECTUUR EVOLUTIE

### Fase 1: De Oorspronkelijke, Conflictueuze Staat ❌

**Beveiligingsstatus**: Lek in multi-tenant isolatie

```sql
-- ❌ VOORBEELD VAN OUDE, ONVEILIGE POLICY
CREATE POLICY "Enable read access for all" 
  ON public.projects 
  FOR SELECT 
  USING (true); -- Iedereen ziet alle projecten!

-- ❌ ANDERE PERMISSIEVE POLICY
CREATE POLICY "employees_select_all"
  ON public.employees
  FOR SELECT
  USING (true); -- Geen company_id check!
```

**Onboarding Architectuur**:
- Edge Function `invite-employee` handelde medewerker toevoegingen af
- Database trigger `handle_new_user_and_employee` probeerde **ook** bedrijven aan te maken
- Resultaat: **Race conditions en 500 errors**

**Data Integriteit**:
```sql
-- ❌ GEVAARLIJKE CONSTRAINT (standaard Supabase setup)
ALTER TABLE employees
  ADD CONSTRAINT employees_company_id_fkey
  FOREIGN KEY (company_id) 
  REFERENCES companies(id)
  ON DELETE NO ACTION; -- Verweesde employees mogelijk!
```

**Problemen**:
- Cross-company data lekkage door permissieve policies
- Conflicterende signup systemen (Edge Function vs Trigger)
- Gegarandeerde data-corruptie bij company verwijdering

---

### Fase 2: De Overgangsfase (Gedeeltelijke Oplossing) ⚠️

**Aanpak**: Verwijder eerst, bouw dan opnieuw

```sql
-- STAP 1: Opschoning van oude policies (per tabel)
DO $$ 
DECLARE 
  pol record;
BEGIN
  FOR pol IN 
    SELECT policyname 
    FROM pg_policies 
    WHERE tablename = 'employees'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON employees', pol.policyname);
  END LOOP;
END $$;

-- STAP 2: Nieuwe, strikte policies
CREATE POLICY "employees_select_own_company" 
  ON employees FOR SELECT 
  USING (
    company_id IN (
      SELECT company_id 
      FROM employees 
      WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "employees_insert_admins_only"
  ON employees FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM employees
      WHERE user_id = auth.uid()
        AND role = 'admin'
        AND company_id = NEW.company_id
    )
  );
```

**Frontend Update**:
```typescript
// ❌ OUDE METHODE (Edge Function)
const { data, error } = await supabase.functions.invoke('invite-employee', {
  body: { email, full_name, role }
});

// ✅ NIEUWE METHODE (Direct RLS Insert)
const { error } = await supabase
  .from('employees')
  .insert({
    full_name: formData.full_name,
    email: formData.email,
    role: formData.role,
    company_id: targetCompanyId, // Van auth user afgeleid
  });
```

**Kritieke Fout**:
Om invite-conflicten op te lossen werd de signup-trigger **volledig verwijderd**:
```sql
DROP FUNCTION handle_new_user_and_employee() CASCADE;
```

**Nieuw Probleem**: 
- ✅ Medewerker toevoegen werkt nu (via RLS)
- ❌ Nieuwe bedrijf signup **volledig gebroken** (geen trigger meer om company aan te maken)

---

### Fase 3: De Definitieve, Robuuste Architectuur ✅

**Oplossing**: "Slimme" trigger die signup-type detecteert

```sql
-- ✅ PRODUCTIE-KLARE TRIGGER FUNCTIE
CREATE OR REPLACE FUNCTION public.handle_new_user_and_employee()
RETURNS trigger 
LANGUAGE plpgsql 
SECURITY DEFINER -- Nodig om RLS te omzeilen voor eerste records
SET search_path = public
AS $$
DECLARE
  employee_id_var uuid;
  v_company_name text;
  v_company_id uuid;
BEGIN
  -- Haal metadata op
  v_company_name := NEW.raw_user_meta_data->>'company_name';
  
  -- Check of employee record al bestaat
  SELECT id INTO employee_id_var 
  FROM employees 
  WHERE email = NEW.email;

  -- FLOW DETECTION LOGIC
  IF employee_id_var IS NOT NULL THEN
    -- === FLOW B: Employee Self-Signup ===
    -- Admin heeft employee toegevoegd, nu maakt employee een account aan
    UPDATE employees 
    SET user_id = NEW.id 
    WHERE id = employee_id_var;
    
    RAISE NOTICE 'Linked user_id % to existing employee %', NEW.id, employee_id_var;

  ELSIF v_company_name IS NOT NULL AND trim(v_company_name) <> '' THEN
    -- === FLOW A: New Company Signup ===
    -- Validatie
    IF length(trim(v_company_name)) < 2 THEN
      RAISE EXCEPTION 'Company name too short';
    END IF;

    -- Maak company aan
    INSERT INTO companies (name, created_at)
    VALUES (trim(v_company_name), now())
    RETURNING id INTO v_company_id;

    -- Maak admin employee aan
    INSERT INTO employees (
      user_id, 
      company_id, 
      full_name, 
      email, 
      role
    ) VALUES (
      NEW.id,
      v_company_id,
      COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
      NEW.email,
      'admin'
    );

    RAISE NOTICE 'Created company % and admin employee for user %', v_company_id, NEW.id;
  ELSE
    -- Geen company_name en geen bestaand employee = invalid signup
    RAISE EXCEPTION 'Invalid signup: no company_name provided and no existing employee found';
  END IF;

  RETURN NEW;
END;
$$;

-- Trigger activeren
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION handle_new_user_and_employee();
```

**Resultaat**:
- ✅ **Flow A** (Nieuwe bedrijf): `company_name` in metadata → company + admin employee aangemaakt
- ✅ **Flow B** (Employee self-signup): Geen metadata → zoek bestaand employee record → link `user_id`
- ✅ **Validatie**: Beide flows hebben error handling
- ✅ **Security**: SECURITY DEFINER alleen voor trigger, daarna RLS actief

---

## 📊 DEFINITIEVE RLS ARCHITECTUUR

### Policy Overzicht (20 policies, 6 tabellen)

| Tabel | Policies | Doel |
|-------|----------|------|
| `companies` | 2 | SELECT (eigen company), UPDATE (admins only) |
| `employees` | 4 | SELECT (own company), INSERT (admins), UPDATE (admins), DELETE (admins) |
| `projects` | 2 | SELECT (own company), INSERT+UPDATE (admins) |
| `time_entries` | 6 | Full CRUD, met admin/member role separation |
| `kilometers` | 4 | Full CRUD, met role-based access |
| `costs` | 2 | SELECT (own company), INSERT (authenticated) |

### Voorbeeld Policies: Companies Tabel

```sql
-- ✅ POLICY 1: Iedereen ziet zijn eigen company
CREATE POLICY "users_view_own_company" 
  ON companies FOR SELECT 
  USING (
    id IN (
      SELECT company_id 
      FROM employees 
      WHERE user_id = auth.uid()
    )
  );

-- ✅ POLICY 2: Alleen admins kunnen company data updaten
CREATE POLICY "admins_update_company" 
  ON companies FOR UPDATE 
  USING (
    id IN (
      SELECT company_id 
      FROM employees 
      WHERE user_id = auth.uid() 
        AND role = 'admin'
    )
  )
  WITH CHECK (
    id IN (
      SELECT company_id 
      FROM employees 
      WHERE user_id = auth.uid() 
        AND role = 'admin'
    )
  );
```

### Data Integriteit via Constraints

```sql
-- ✅ CORRECTE CASCADE SETUP
ALTER TABLE employees
  ADD CONSTRAINT employees_company_id_fkey
  FOREIGN KEY (company_id) 
  REFERENCES companies(id)
  ON DELETE CASCADE; -- Verwijder employees als company wordt verwijderd

ALTER TABLE employees
  ADD CONSTRAINT employees_user_id_fkey
  FOREIGN KEY (user_id)
  REFERENCES auth.users(id)
  ON DELETE CASCADE; -- Verwijder employee als auth user wordt verwijderd

-- ✅ ADMIN PROTECTION TRIGGER
CREATE OR REPLACE FUNCTION prevent_last_admin_removal()
RETURNS trigger AS $$
BEGIN
  IF OLD.role = 'admin' THEN
    IF (SELECT COUNT(*) FROM employees 
        WHERE company_id = OLD.company_id 
          AND role = 'admin' 
          AND id != OLD.id) = 0 THEN
      RAISE EXCEPTION 'Cannot remove last admin from company';
    END IF;
  END IF;
  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_last_admin_before_delete
  BEFORE DELETE ON employees
  FOR EACH ROW
  EXECUTE FUNCTION prevent_last_admin_removal();
```

---

## 🐞 KRITIEKE DEBUG MOMENTEN

### 1. De "Verborgen Policies" Val
**Symptoom**: Nieuwe policies werkten niet, ondanks correcte syntax.

**Diagnose**:
```sql
-- Verificatie query
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies
WHERE tablename = 'employees'
ORDER BY policyname;

-- Ontdekking: 10+ oude policies actief!
-- policies: "Enable read access for all", "old_select_policy", etc.
```

**Les**: **Verwijder altijd alle oude policies eerst** voordat je nieuwe toevoegt. Policies zijn additief—een permissieve policy ondermijnt strikte policies.

---

### 2. Architecturale Desynchronisatie
**Symptoom**: RLS policies correct, maar "Add Employee" bleef 500 error geven.

**Diagnose**:
```typescript
// Frontend riep nog steeds Edge Function aan
const { data, error } = await supabase.functions.invoke('invite-employee', {
  body: { email, full_name, role }
});
// Error: Edge Function bestaat niet meer!
```

**Oplossing**: Frontend code update naar direct RLS insert.

**Les**: Een backend-architectuurwijziging is **pas compleet** als de frontend is bijgewerkt. Test beide lagen na elke change.

---

### 3. Het Kip-of-het-Ei Probleem
**Symptoom**: Na het oplossen van invite-flow, werkte nieuwe bedrijf signup niet meer.

**Root Cause**:
```sql
-- We hadden de trigger verwijderd om invite-conflicten op te lossen
DROP FUNCTION handle_new_user_and_employee() CASCADE;
-- ↑ Dit brak de "nieuwe company" flow
```

**Inzicht**: De applicatie heeft **twee fundamenteel verschillende onboarding-flows**:
1. **Flow A**: Eerste user van nieuw bedrijf (trigger moet company aanmaken)
2. **Flow B**: Employee die al door admin is toegevoegd (trigger moet alleen user_id linken)

**Oplossing**: "Slimme" trigger met auto-detectie (zie Fase 3).

---

### 4. Foreign Key Time Bomb
**Ontdekking**: Alle foreign keys stonden op `ON DELETE NO ACTION`.

```sql
-- Verificatie query
SELECT
  tc.table_name,
  kcu.column_name,
  ccu.table_name AS foreign_table_name,
  ccu.column_name AS foreign_column_name,
  rc.delete_rule
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage AS ccu
  ON ccu.constraint_name = tc.constraint_name
JOIN information_schema.referential_constraints AS rc
  ON rc.constraint_name = tc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_schema = 'public'
ORDER BY tc.table_name;

-- Resultaat: Bijna alles = NO ACTION
```

**Impact**: Bij het verwijderen van een company zouden employees, projects, time_entries blijven bestaan als verweesde data.

**Correctie**: Systematisch alle constraints updaten naar `CASCADE` (of `SET NULL` waar logisch).

---

## ⚠️ WAARSCHUWINGEN & BEST PRACTICES

### RLS is Alles-of-Niets
```sql
-- ❌ INCOMPLETE: Only SELECT policy
CREATE POLICY "employees_select" ON employees 
  FOR SELECT USING (...);
-- Resultaat: Users kunnen lezen maar niet schrijven = read-only app!

-- ✅ COMPLEET: Policies voor alle operaties
CREATE POLICY "employees_select" ON employees FOR SELECT USING (...);
CREATE POLICY "employees_insert" ON employees FOR INSERT WITH CHECK (...);
CREATE POLICY "employees_update" ON employees FOR UPDATE USING (...);
CREATE POLICY "employees_delete" ON employees FOR DELETE USING (...);
```

### Audit Tooling
Gebruik deze queries om je RLS status te controleren:

```sql
-- Check of RLS is enabled
SELECT tablename, rowsecurity 
FROM pg_tables 
WHERE schemaname = 'public';

-- List alle policies per tabel
SELECT tablename, policyname, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, cmd;

-- Test policy als specifieke user
SET ROLE authenticated;
SET request.jwt.claim.sub = '1234-5678-user-uuid';
SELECT * FROM employees; -- Wat zie je?
RESET ROLE;
```

### SECURITY DEFINER: Gebruik met Zorg
**Risico**: Omzeilt RLS en draait met verhoogde rechten.

**Veilig gebruik**:
1. ✅ Alleen voor **zeer specifieke** processen (zoals signup trigger)
2. ✅ Altijd `SET search_path = public` toevoegen (security)
3. ✅ Zorg dat de functie **geen user input** direct uitvoert
4. ✅ Gebruik `RAISE EXCEPTION` voor validatie

```sql
-- ✅ VEILIG VOORBEELD
CREATE FUNCTION my_function()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public -- Voorkom schema injection
AS $$
BEGIN
  -- Validatie EERST
  IF NEW.some_field IS NULL THEN
    RAISE EXCEPTION 'Invalid input';
  END IF;
  -- Dan pas logica
  ...
END;
$$;
```

### Frontend en Backend Moeten Synchroon Evolueren
**Werkwijze**:
1. Update backend (RLS policies, trigger)
2. Test backend direct met SQL queries
3. Update frontend code
4. Test volledige flow end-to-end
5. **Verwijder** oude code (Edge Functions, oude API calls)

**Gebruik een checklist**:
- [ ] Backend functionaliteit werkt (SQL test)
- [ ] Frontend code gebruikt nieuwe methode
- [ ] Oude code is verwijderd of disabled
- [ ] End-to-end test succesvol
- [ ] Error handling getest

---

## 💡 PERSOONLIJKE NOTA (voor mede-coders)

Dit hele traject was alleen mogelijk door één werkprincipe **religieus** toe te passen bij AI-assisted development:

> **"We werken alleen op basis van feiten, en dubbele controle op output van de LLM. We controleren eerst en passen daarna wijzigingen aan. We doen geen aannames."**

Dit dwong de AI (en mijzelf) om:
- Geen overhaaste conclusies te trekken
- Na elke wijziging een verificatie-query uit te voeren
- Eigen suggesties kritisch te analyseren
- Elke "zou moeten werken" claim te testen

**Resultaat**: Een dynamiek van **"samen een bewezen oplossing bouwen"** in plaats van "een antwoord krijgen".

Het voelt traag aan, maar bespaart uren debugging van aannames. Ik raad dit iedereen aan die met AI codeert aan complexe systemen.

---

## 🚀 VERIFICATIE CHECKLIST

Voor anderen die deze case study willen repliceren of een vergelijkbaar project hebben:

### Database Verificatie
```sql
-- 1. Check RLS is enabled op alle tabellen
SELECT tablename, rowsecurity 
FROM pg_tables 
WHERE schemaname = 'public' AND tablename IN 
  ('companies', 'employees', 'projects', 'time_entries', 'kilometers', 'costs');

-- 2. Count policies per tabel (moet 20 zijn)
SELECT COUNT(*) as total_policies
FROM pg_policies
WHERE schemaname = 'public';

-- 3. Verify cascade constraints
SELECT tc.table_name, kcu.column_name, rc.delete_rule
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu USING (constraint_name)
JOIN information_schema.referential_constraints rc USING (constraint_name)
WHERE tc.constraint_type = 'FOREIGN KEY' 
  AND tc.table_schema = 'public'
  AND rc.delete_rule != 'CASCADE';
-- Moet leeg zijn (behalve project_manager_id -> SET NULL)

-- 4. Check trigger bestaat en is actief
SELECT trigger_name, event_manipulation, action_statement
FROM information_schema.triggers
WHERE trigger_schema = 'auth' 
  AND event_object_table = 'users';
```

### Functionele Tests
1. ✅ **Nieuwe bedrijf signup**: Metadata met `company_name` → company + admin employee aangemaakt
2. ✅ **Employee self-signup**: Admin voegt employee toe → employee maakt account → `user_id` gelinkt
3. ✅ **Cross-company isolatie**: Login bij 2 accounts → check dat data gescheiden is
4. ✅ **Role-based access**: Member kan alleen eigen data zien, admin ziet alles
5. ✅ **Last admin protection**: Probeer laatste admin te verwijderen → moet falen
6. ✅ **Cascade deletes**: Verwijder test company → check dat employees ook weg zijn

---

## 📚 REFERENTIES

- [Supabase RLS Documentation](https://supabase.com/docs/guides/auth/row-level-security)
- [PostgreSQL Policy Documentation](https://www.postgresql.org/docs/current/sql-createpolicy.html)
- [SECURITY DEFINER Best Practices](https://www.postgresql.org/docs/current/sql-createfunction.html#SQL-CREATEFUNCTION-SECURITY)

---

**Project Status**: Productie-klaar  
**Laatste Update**: 3 oktober 2025  
**Supabase Project**: xgrjabdudpsynesdoook (eu-west-1)  
**Final Policy Count**: 20 policies over 6 tabellen
