-- Migration 021: Backfill winners from duplicate columns
--
-- Phase 4 consolidates duplicate columns on order_items. Winners are the
-- canonical live-code fields; losers are historical duplicates that no
-- code path writes anymore. Before we can stop reading the losers (PART B)
-- and physically drop them (PART C), every row must carry the same value
-- on the winner.
--
-- Winner ← Loser
--   unit_price_local   ← sale_price_lyd
--   category           ← item_category
--   product_image_url  ← product_thumb_url
--
-- Applied statement by statement on remote D1. Verify:
--   SELECT COUNT(*) FROM order_items WHERE (unit_price_local IS NULL OR unit_price_local = 0) AND sale_price_lyd > 0;
--   SELECT COUNT(*) FROM order_items WHERE category IS NULL AND item_category IS NOT NULL;
--   SELECT COUNT(*) FROM order_items WHERE product_image_url IS NULL AND product_thumb_url IS NOT NULL;
-- All three must return 0.

UPDATE order_items
   SET unit_price_local = sale_price_lyd
 WHERE (unit_price_local IS NULL OR unit_price_local = 0)
   AND sale_price_lyd IS NOT NULL AND sale_price_lyd > 0;

UPDATE order_items
   SET category = item_category
 WHERE category IS NULL AND item_category IS NOT NULL;

UPDATE order_items
   SET product_image_url = product_thumb_url
 WHERE product_image_url IS NULL AND product_thumb_url IS NOT NULL;
