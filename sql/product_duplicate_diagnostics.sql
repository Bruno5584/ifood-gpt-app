-- Diagnóstico de produtos duplicados e complementos relacionados
-- Restaurante alvo
\set restaurant_id 'c15fb33a-36c3-4ab1-9871-a416195e7eb7'
\set target_names '''teste 2'',''teste 3'''

-- 1) Produtos por restaurante/nome (inclui metadados para inspecionar manualmente)
WITH target_products AS (
  SELECT *
  FROM products
  WHERE restaurant_id = :'restaurant_id'
    AND name IN (:target_names)
)
SELECT id,
       restaurant_id,
       name,
       slug,
       category_id,
       is_active,
       created_at,
       updated_at
FROM target_products
ORDER BY name, created_at, id;

-- 2) modifier_groups ligados aos produtos acima
SELECT mg.id,
       mg.product_id,
       mg.restaurant_id,
       mg.title,
       mg.sort_order
FROM modifier_groups mg
JOIN products p ON p.id = mg.product_id
WHERE p.restaurant_id = :'restaurant_id'
  AND p.name IN (:target_names)
ORDER BY mg.product_id, mg.sort_order, mg.id;

-- 3) product_groups ligados aos produtos acima
SELECT pg.id,
       pg.product_id,
       pg.group_id,
       pg.min_qty,
       pg.max_qty,
       pg.sort_order
FROM product_groups pg
JOIN products p ON p.id = pg.product_id
WHERE p.restaurant_id = :'restaurant_id'
  AND p.name IN (:target_names)
ORDER BY pg.product_id, pg.sort_order, pg.id;

-- 4) modifiers ligados às categorias acima
SELECT m.id,
       m.group_id,
       m.name,
       m.unit_price,
       m.max_per_item,
       m.sort_order
FROM modifiers m
JOIN modifier_groups mg ON mg.id = m.group_id
JOIN products p ON p.id = mg.product_id
WHERE p.restaurant_id = :'restaurant_id'
  AND p.name IN (:target_names)
ORDER BY mg.product_id, mg.id, m.sort_order, m.id;


/* =============================================================
   Script seguro para excluir apenas produtos duplicados
   Mantém a primeira ocorrência por (restaurant_id, name) e
   remove as cópias extras + seus complementos vinculados.
   Execute em TRANSACTION e revise os registros afetados.
   ============================================================= */
BEGIN;

WITH target AS (
  SELECT id,
         restaurant_id,
         name,
         ROW_NUMBER() OVER (
           PARTITION BY restaurant_id, name
           ORDER BY created_at NULLS LAST, id
         ) AS rn
  FROM products
  WHERE restaurant_id = :'restaurant_id'
    AND name IN (:target_names)
),
keep_one AS (
  SELECT id FROM target WHERE rn = 1
),
products_to_remove AS (
  SELECT id FROM target WHERE rn > 1
),
groups_to_remove AS (
  SELECT id
  FROM modifier_groups
  WHERE product_id IN (SELECT id FROM products_to_remove)
),
deleted_modifiers AS (
  DELETE FROM modifiers
  WHERE group_id IN (SELECT id FROM groups_to_remove)
  RETURNING id
),
deleted_product_groups AS (
  DELETE FROM product_groups
  WHERE product_id IN (SELECT id FROM products_to_remove)
     OR group_id IN (SELECT id FROM groups_to_remove)
  RETURNING id
),
deleted_groups AS (
  DELETE FROM modifier_groups
  WHERE id IN (SELECT id FROM groups_to_remove)
  RETURNING id
)
DELETE FROM products
WHERE id IN (SELECT id FROM products_to_remove);

COMMIT;
