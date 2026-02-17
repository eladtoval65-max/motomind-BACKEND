-- ═══════════════════════════════════════════════════════════
-- MOTOMIND v2 — FULL DATABASE SETUP
-- Run this in your Railway PostgreSQL Query tab
-- ═══════════════════════════════════════════════════════════

-- ─── 1. USERS (with identity verification) ──────────────────
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  full_name VARCHAR(100) NOT NULL,
  email VARCHAR(150) UNIQUE NOT NULL,
  phone VARCHAR(20),
  avatar_url TEXT,
  -- Identity Verification
  id_verified BOOLEAN DEFAULT false,
  id_verified_at TIMESTAMP,
  id_country VARCHAR(10) DEFAULT 'IL',
  -- Trust Metrics
  trust_score NUMERIC(3,1) DEFAULT 5.0,
  total_sales INTEGER DEFAULT 0,
  total_purchases INTEGER DEFAULT 0,
  member_since TIMESTAMP DEFAULT NOW(),
  -- Language preference
  preferred_language VARCHAR(5) DEFAULT 'he',
  is_active BOOLEAN DEFAULT true
);

-- ─── 2. CAR MODELS ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS car_models (
  id SERIAL PRIMARY KEY,
  make VARCHAR(100) NOT NULL,
  model VARCHAR(100) NOT NULL,
  year INTEGER NOT NULL,
  vehicle_type VARCHAR(30) DEFAULT 'car' -- car, motorcycle, bike, van
);

-- ─── 3. LISTINGS ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS listings (
  id SERIAL PRIMARY KEY,
  car_model_id INTEGER REFERENCES car_models(id),
  seller_id INTEGER REFERENCES users(id),
  price INTEGER NOT NULL,
  mileage INTEGER NOT NULL,
  year INTEGER NOT NULL,
  status VARCHAR(20) DEFAULT 'active',
  ownership_type VARCHAR(50),
  description_he TEXT,
  description_en TEXT,
  is_gov_verified BOOLEAN DEFAULT false,
  is_cleared_by_police BOOLEAN DEFAULT false,
  safety_grade INTEGER CHECK (safety_grade BETWEEN 1 AND 10),
  test_validity_date DATE,
  is_suspicious BOOLEAN DEFAULT false,
  image_url TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);

-- ─── 4. ORACLE SCORES ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS oracle_scores (
  id SERIAL PRIMARY KEY,
  listing_id INTEGER REFERENCES listings(id),
  smart_score NUMERIC(3,1),
  reliability_score NUMERIC(3,1),
  projected_annual_maintenance_cost INTEGER,
  future_resale_value_24m INTEGER,
  confidence_index NUMERIC(3,1),
  negotiation_strategy TEXT,
  end_of_life_warning BOOLEAN DEFAULT false,
  persona_match_score NUMERIC(3,1)
);

-- ─── 5. MARKET PRICE DATA (Fair Price Indicator) ────────────
CREATE TABLE IF NOT EXISTS market_prices (
  id SERIAL PRIMARY KEY,
  make VARCHAR(100) NOT NULL,
  model VARCHAR(100) NOT NULL,
  year INTEGER NOT NULL,
  mileage_band VARCHAR(30), -- e.g. '0-50k', '50k-100k', '100k+'
  price_low INTEGER NOT NULL,
  price_avg INTEGER NOT NULL,
  price_high INTEGER NOT NULL,
  sample_count INTEGER DEFAULT 0,
  updated_at TIMESTAMP DEFAULT NOW()
);

-- ─── 6. REVIEWS (Two-way: buyer reviews seller AND vice versa)
CREATE TABLE IF NOT EXISTS reviews (
  id SERIAL PRIMARY KEY,
  listing_id INTEGER REFERENCES listings(id),
  reviewer_id INTEGER REFERENCES users(id),
  reviewee_id INTEGER REFERENCES users(id),
  reviewer_role VARCHAR(10) NOT NULL, -- 'buyer' or 'seller'
  rating INTEGER CHECK (rating BETWEEN 1 AND 5),
  comment TEXT,
  -- Specific trust dimensions
  was_honest BOOLEAN,
  was_on_time BOOLEAN,
  car_matched_description BOOLEAN, -- only for seller reviews
  created_at TIMESTAMP DEFAULT NOW()
);

-- ─── 7. VEHICLE HISTORY ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS vehicle_history (
  id SERIAL PRIMARY KEY,
  listing_id INTEGER REFERENCES listings(id),
  license_plate VARCHAR(20),
  previous_owners INTEGER DEFAULT 1,
  accident_count INTEGER DEFAULT 0,
  last_test_date DATE,
  test_validity_date DATE,
  is_stolen BOOLEAN DEFAULT false,
  has_outstanding_finance BOOLEAN DEFAULT false,
  imported BOOLEAN DEFAULT false,
  raw_gov_data JSONB,
  fetched_at TIMESTAMP DEFAULT NOW()
);

-- ─── 8. COMMUNITY FEED ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS community_posts (
  id SERIAL PRIMARY KEY,
  author_id INTEGER REFERENCES users(id),
  title_he TEXT,
  title_en TEXT,
  body_he TEXT,
  body_en TEXT,
  category VARCHAR(30), -- 'question', 'tip', 'review', 'deal'
  upvotes INTEGER DEFAULT 0,
  is_pinned BOOLEAN DEFAULT false,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS community_replies (
  id SERIAL PRIMARY KEY,
  post_id INTEGER REFERENCES community_posts(id),
  author_id INTEGER REFERENCES users(id),
  body_he TEXT,
  body_en TEXT,
  upvotes INTEGER DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════
-- SEED DATA
-- ═══════════════════════════════════════════════════════════

-- Users
INSERT INTO users (full_name, email, phone, id_verified, id_verified_at, trust_score, total_sales, member_since, preferred_language) VALUES
  ('David Cohen', 'david@example.com', '054-1234567', true, NOW() - INTERVAL '6 months', 9.2, 3, NOW() - INTERVAL '8 months', 'he'),
  ('Sarah Levi', 'sarah@example.com', '052-9876543', true, NOW() - INTERVAL '3 months', 8.7, 1, NOW() - INTERVAL '4 months', 'he'),
  ('AutoMax TLV', 'automax@example.com', '03-5551234', true, NOW() - INTERVAL '1 year', 9.5, 24, NOW() - INTERVAL '14 months', 'he'),
  ('Noa Shapiro', 'noa@example.com', '050-7654321', true, NOW() - INTERVAL '2 months', 8.1, 1, NOW() - INTERVAL '5 months', 'en'),
  ('Avi Ben-David', 'avi@example.com', '054-1112233', false, NULL, 6.0, 0, NOW() - INTERVAL '1 month', 'he'),
  ('Yossi Mizrahi', 'yossi@example.com', '052-3334455', true, NOW() - INTERVAL '5 months', 9.0, 2, NOW() - INTERVAL '7 months', 'he');

-- Car Models
INSERT INTO car_models (make, model, year, vehicle_type) VALUES
  ('Toyota', 'Corolla', 2019, 'car'),
  ('Hyundai', 'Elantra', 2020, 'car'),
  ('Kia', 'Sportage', 2018, 'car'),
  ('Mazda', 'CX-5', 2021, 'car'),
  ('Honda', 'Civic', 2018, 'car'),
  ('Volkswagen', 'Golf', 2019, 'car'),
  ('Skoda', 'Octavia', 2020, 'car'),
  ('Ford', 'Focus', 2017, 'car');

-- Listings
INSERT INTO listings (car_model_id, seller_id, price, mileage, year, ownership_type, is_gov_verified, is_cleared_by_police, safety_grade, test_validity_date, image_url, description_he, description_en) VALUES
  (1, 1, 68000, 52000, 2019, 'Private', true, true, 9, '2026-08-10', 'https://images.unsplash.com/photo-1621007947382-bb3c3994e3fb?w=600', 'טויוטה קורולה במצב מצוין. מטופלת בקביעות, ללא תאונות.', 'Excellent condition Toyota Corolla. Regularly serviced, no accidents.'),
  (2, 2, 55000, 71000, 2020, 'Private', true, true, 8, '2026-03-15', 'https://images.unsplash.com/photo-1555215695-3004980ad54e?w=600', 'יונדאי אלנטרה שמורה מאוד. בעלים ראשון.', 'Very well kept Hyundai Elantra. First owner.'),
  (3, 3, 82000, 44000, 2018, 'Dealer', true, true, 7, '2026-06-20', 'https://images.unsplash.com/photo-1606664515524-ed2f786a0bd6?w=600', 'קיה ספורטג׳ ממוסך מורשה. אחריות נוספת זמינה.', 'Kia Sportage from authorized garage. Extended warranty available.'),
  (4, 4, 115000, 28000, 2021, 'Private', true, true, 10, '2027-01-01', 'https://images.unsplash.com/photo-1617469767053-d3b523a0b982?w=600', 'מאזדה CX-5 כמו חדשה. ק״מ נמוך מאוד.', 'Mazda CX-5 like new. Very low mileage.'),
  (5, 5, 61000, 88000, 2018, 'Private', false, true, 6, '2025-11-30', 'https://images.unsplash.com/photo-1590362891991-f776e747a588?w=600', 'הונדה סיוויק תקינה. ק״מ גבוה אבל מטופלת.', 'Honda Civic in working condition. High mileage but maintained.'),
  (6, 3, 74000, 61000, 2019, 'Dealer', true, true, 8, '2026-09-12', 'https://images.unsplash.com/photo-1503736334956-4c8f8e92946d?w=600', 'פולקסווגן גולף שמורה. שירות מלא.', 'Well maintained VW Golf. Full service history.'),
  (7, 6, 79000, 49000, 2020, 'Private', true, true, 9, '2026-07-22', 'https://images.unsplash.com/photo-1494976388531-d1058494cdd8?w=600', 'סקודה אוקטביה יפה מאוד. עור, נאוי.', 'Beautiful Skoda Octavia. Leather interior, navigation.'),
  (8, 5, 42000, 105000, 2017, 'Private', false, false, 5, '2025-06-01', 'https://images.unsplash.com/photo-1549317661-bd32c8ce0db2?w=600', 'פורד פוקוס בסיסי. ק״מ גבוה. מחיר בהתאם.', 'Basic Ford Focus. High mileage. Priced accordingly.');

-- Oracle Scores
INSERT INTO oracle_scores (listing_id, smart_score, reliability_score, projected_annual_maintenance_cost, future_resale_value_24m, confidence_index, negotiation_strategy, end_of_life_warning, persona_match_score) VALUES
  (1, 9.1, 9.0, 2800, 58000, 9.5, 'Great value Toyota. Try negotiating 3-5% below asking.', false, 8.8),
  (2, 8.3, 8.5, 3100, 45000, 8.8, 'Solid Hyundai. Ask for recent service records.', false, 8.2),
  (3, 7.8, 7.5, 4200, 68000, 8.0, 'Dealer listing — push for warranty inclusion.', false, 7.5),
  (4, 9.5, 9.8, 2100, 102000, 9.9, 'Excellent condition Mazda. Worth every shekel.', false, 9.5),
  (5, 6.4, 6.0, 5800, 44000, 7.0, 'Older Honda with high mileage. Budget for maintenance.', false, 6.0),
  (6, 8.0, 8.2, 3800, 58000, 8.5, 'Well-maintained Golf. Compare financing rates.', false, 7.8),
  (7, 8.7, 8.9, 2900, 65000, 9.0, 'Low mileage Skoda. Check for any recalls.', false, 8.5),
  (8, 5.2, 4.8, 7500, 22000, 6.0, 'High mileage. Consider only if budget is very tight.', false, 5.0);

-- Market Price Data (Fair Price Indicator)
INSERT INTO market_prices (make, model, year, mileage_band, price_low, price_avg, price_high, sample_count) VALUES
  ('Toyota', 'Corolla', 2019, '50k-100k', 60000, 70000, 80000, 47),
  ('Hyundai', 'Elantra', 2020, '50k-100k', 48000, 58000, 68000, 31),
  ('Kia', 'Sportage', 2018, '0-50k', 72000, 85000, 95000, 22),
  ('Mazda', 'CX-5', 2021, '0-50k', 105000, 118000, 130000, 18),
  ('Honda', 'Civic', 2018, '50k-100k', 55000, 64000, 74000, 29),
  ('Volkswagen', 'Golf', 2019, '50k-100k', 65000, 75000, 85000, 24),
  ('Skoda', 'Octavia', 2020, '0-50k', 70000, 80000, 92000, 19),
  ('Ford', 'Focus', 2017, '100k+', 34000, 44000, 54000, 35);

-- Vehicle History
INSERT INTO vehicle_history (listing_id, license_plate, previous_owners, accident_count, last_test_date, test_validity_date, is_stolen, has_outstanding_finance, imported) VALUES
  (1, '12-345-67', 1, 0, '2024-08-10', '2026-08-10', false, false, false),
  (2, '23-456-78', 1, 0, '2024-03-15', '2026-03-15', false, false, false),
  (3, '34-567-89', 2, 1, '2024-06-20', '2026-06-20', false, false, false),
  (4, '45-678-90', 1, 0, '2025-01-01', '2027-01-01', false, false, false),
  (5, '56-789-01', 3, 2, '2023-11-30', '2025-11-30', false, true,  false),
  (6, '67-890-12', 2, 0, '2024-09-12', '2026-09-12', false, false, false),
  (7, '78-901-23', 1, 0, '2024-07-22', '2026-07-22', false, false, true),
  (8, '89-012-34', 4, 3, '2023-06-01', '2025-06-01', false, false, false);

-- Reviews
INSERT INTO reviews (listing_id, reviewer_id, reviewee_id, reviewer_role, rating, comment, was_honest, was_on_time, car_matched_description) VALUES
  (1, 4, 1, 'buyer', 5, 'David was amazing. Car was exactly as described. Highly recommended!', true, true, true),
  (1, 1, 4, 'seller', 5, 'Noa was a pleasure to deal with. Serious buyer, paid on time.', true, true, null),
  (2, 6, 2, 'buyer', 4, 'Good experience overall. Car was clean and honest seller.', true, true, true),
  (3, 1, 3, 'buyer', 4, 'AutoMax were professional. Slight delay but car was as described.', true, false, true);

-- Community Posts
INSERT INTO community_posts (author_id, title_he, title_en, body_he, body_en, category, upvotes) VALUES
  (1, 'מה המחיר ההוגן לקורולה 2019 עם 60,000 ק״מ?', 'Fair price for 2019 Corolla with 60k km?', 'ראיתי מחירים שונים מאוד באתרים שונים. מה דעתכם?', 'Seeing very different prices across sites. What do you think?', 'question', 14),
  (3, '5 דברים שכדאי לבדוק לפני קניית רכב יד שנייה', '5 things to check before buying a used car', 'מניסיון של שנים במכירת רכבים, אלו הדברים הכי חשובים...', 'From years of selling cars, these are the most important things...', 'tip', 31),
  (6, 'זהירות מ-Yad2 — ניסיון אישי עם נוכל', 'Watch out on Yad2 — personal scam experience', 'חוויתי לאחרונה ניסיון הונאה. רוצה לשתף כדי להזהיר אחרים.', 'Recently experienced a scam attempt. Sharing to warn others.', 'review', 28);
