-- TWO TALES V3: READ-ONLY customer-ID diagnostics.
-- Run in Supabase SQL Editor. This DOES NOT modify or delete records.
-- The SQL editor often has no auth.uid() context, so rows are grouped by user_id.
WITH expanded AS (
  SELECT b.user_id, c.value ->> 'id' AS customer_id,
         c.value ->> 'name' AS customer_name, c.ordinality AS position
  FROM public.business_state AS b
  CROSS JOIN LATERAL jsonb_array_elements(
    CASE WHEN jsonb_typeof(b.payload -> 'customers') = 'array'
      THEN b.payload -> 'customers' ELSE '[]'::jsonb END
  ) WITH ORDINALITY AS c(value, ordinality)
)
SELECT user_id, customer_id, count(*) AS occurrences,
       string_agg(coalesce(customer_name,'(unnamed)'), ' | ' ORDER BY position) AS customer_names,
       array_agg(position ORDER BY position) AS json_positions
FROM expanded
GROUP BY user_id, customer_id
HAVING count(*) > 1 OR customer_id IS NULL OR customer_id = ''
ORDER BY occurrences DESC;
-- Zero rows means the CLOUD SNAPSHOT currently has no duplicate customer IDs.
-- It does not verify the unsaved local recovery snapshot.

-- For comparison, current normalized customer counts by owner:
SELECT user_id, count(*) AS normalized_customer_count
FROM public.tt_customers GROUP BY user_id ORDER BY normalized_customer_count DESC;
