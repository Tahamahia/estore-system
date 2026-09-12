-- Migration 010: Expand customer model with detailed address and secondary phone
ALTER TABLE customers ADD COLUMN area TEXT;
ALTER TABLE customers ADD COLUMN street TEXT;
ALTER TABLE customers ADD COLUMN location_url TEXT;
ALTER TABLE customers ADD COLUMN phone2 TEXT;
