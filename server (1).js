require('dotenv').config();
const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
});

// ═══════════════════════════════════════════════════════════
// HEALTH CHECK
// ═══════════════════════════════════════════════════════════
app.get('/', (req, res) => {
  res.json({ status: '🚗 MotoMind v2 API running', version: '2.0.0' });
});

// ═══════════════════════════════════════════════════════════
// LISTINGS — with Fair Price + Vehicle History
// ═══════════════════════════════════════════════════════════
app.get('/api/listings', async (req, res) => {
  try {
    const lang = req.query.lang || 'en';
    const { rows } = await pool.query(`
      SELECT 
        l.id, l.price, l.mileage, l.year, l.image_url,
        l.ownership_type, l.is_gov_verified, l.is_cleared_by_police,
        l.safety_grade, l.test_validity_date,
        CASE WHEN $1 = 'he' THEN l.description_he ELSE l.description_en END AS description,
        cm.make, cm.model, cm.vehicle_type,
        os.smart_score, os.reliability_score,
        os.projected_annual_maintenance_cost,
        os.future_resale_value_24m, os.confidence_index,
        os.negotiation_strategy, os.end_of_life_warning,
        -- Seller Info + Trust
        u.full_name AS seller_name, u.phone AS seller_phone,
        u.id_verified, u.trust_score, u.total_sales, u.member_since,
        u.preferred_language,
        -- Market Price (Fair Price Indicator)
        mp.price_low, mp.price_avg, mp.price_high,
        -- Vehicle History
        vh.previous_owners, vh.accident_count,
        vh.is_stolen, vh.has_outstanding_finance, vh.imported,
        -- Avg seller rating
        ROUND(AVG(r.rating), 1) AS seller_avg_rating,
        COUNT(r.id) AS seller_review_count
      FROM listings l
      JOIN car_models cm ON l.car_model_id = cm.id
      JOIN oracle_scores os ON l.id = os.listing_id
      JOIN users u ON l.seller_id = u.id
      LEFT JOIN market_prices mp 
        ON mp.make = cm.make AND mp.model = cm.model AND mp.year = cm.year
      LEFT JOIN vehicle_history vh ON vh.listing_id = l.id
      LEFT JOIN reviews r ON r.reviewee_id = u.id AND r.reviewer_role = 'buyer'
      WHERE l.status = 'active'
      GROUP BY l.id, cm.id, os.id, u.id, mp.id, vh.id
      ORDER BY os.smart_score DESC
      LIMIT 20
    `, [lang]);

    // Add price position label
    const enriched = rows.map(car => ({
      ...car,
      price_position: getPricePosition(car.price, car.price_low, car.price_avg, car.price_high),
    }));

    res.json(enriched);
  } catch (err) {
    console.error('[listings]', err.message);
    res.status(500).json({ error: 'Could not fetch listings' });
  }
});

// ═══════════════════════════════════════════════════════════
// SINGLE LISTING DETAIL
// ═══════════════════════════════════════════════════════════
app.get('/api/listings/:id', async (req, res) => {
  try {
    const lang = req.query.lang || 'en';
    const { rows } = await pool.query(`
      SELECT 
        l.id, l.price, l.mileage, l.year, l.image_url,
        l.ownership_type, l.is_gov_verified, l.is_cleared_by_police,
        l.safety_grade, l.test_validity_date,
        CASE WHEN $2 = 'he' THEN l.description_he ELSE l.description_en END AS description,
        cm.make, cm.model, cm.vehicle_type,
        os.smart_score, os.reliability_score,
        os.projected_annual_maintenance_cost,
        os.future_resale_value_24m, os.confidence_index,
        os.negotiation_strategy, os.end_of_life_warning,
        u.id AS seller_id, u.full_name AS seller_name, u.phone AS seller_phone,
        u.id_verified, u.trust_score, u.total_sales, u.member_since,
        mp.price_low, mp.price_avg, mp.price_high,
        vh.previous_owners, vh.accident_count, vh.last_test_date,
        vh.test_validity_date AS hist_test_validity,
        vh.is_stolen, vh.has_outstanding_finance, vh.imported, vh.license_plate
      FROM listings l
      JOIN car_models cm ON l.car_model_id = cm.id
      JOIN oracle_scores os ON l.id = os.listing_id
      JOIN users u ON l.seller_id = u.id
      LEFT JOIN market_prices mp 
        ON mp.make = cm.make AND mp.model = cm.model AND mp.year = cm.year
      LEFT JOIN vehicle_history vh ON vh.listing_id = l.id
      WHERE l.id = $1
    `, [req.params.id, lang]);

    if (rows.length === 0) return res.status(404).json({ error: 'Not found' });

    const car = rows[0];
    car.price_position = getPricePosition(car.price, car.price_low, car.price_avg, car.price_high);

    // Get reviews for this seller
    const { rows: reviews } = await pool.query(`
      SELECT r.rating, r.comment, r.reviewer_role, r.was_honest, 
             r.was_on_time, r.car_matched_description, r.created_at,
             u.full_name AS reviewer_name, u.id_verified AS reviewer_verified
      FROM reviews r
      JOIN users u ON r.reviewer_id = u.id
      WHERE r.reviewee_id = $1
      ORDER BY r.created_at DESC
      LIMIT 10
    `, [car.seller_id]);

    car.reviews = reviews;
    res.json(car);
  } catch (err) {
    console.error('[listing detail]', err.message);
    res.status(500).json({ error: 'Could not fetch listing' });
  }
});

// ═══════════════════════════════════════════════════════════
// SMART RECOMMENDATIONS (Quiz)
// ═══════════════════════════════════════════════════════════
app.post('/api/recommendations', async (req, res) => {
  try {
    const { budget, drivingStyle, experienceLevel, lang = 'en' } = req.body;

    if (!budget || !drivingStyle || !experienceLevel) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    let persona = 'Standard';
    if (drivingStyle === 'City') persona = 'Economizer';
    if (drivingStyle === 'Family') persona = 'Safety First';
    if (drivingStyle === 'Performance') persona = 'Enthusiast';

    let orderClause = 'ORDER BY os.smart_score DESC';
    if (persona === 'Safety First') orderClause = 'ORDER BY l.safety_grade DESC, os.reliability_score DESC';
    if (persona === 'Economizer') orderClause = 'ORDER BY os.projected_annual_maintenance_cost ASC, os.future_resale_value_24m DESC';

    const { rows } = await pool.query(`
      SELECT 
        l.id, l.price, l.mileage, l.year, l.image_url,
        l.ownership_type, l.is_gov_verified, l.is_cleared_by_police,
        l.safety_grade, l.test_validity_date,
        CASE WHEN $2 = 'he' THEN l.description_he ELSE l.description_en END AS description,
        cm.make, cm.model,
        os.smart_score, os.reliability_score,
        os.projected_annual_maintenance_cost,
        os.future_resale_value_24m, os.confidence_index,
        os.negotiation_strategy, os.end_of_life_warning,
        u.full_name AS seller_name, u.id_verified, u.trust_score,
        mp.price_low, mp.price_avg, mp.price_high,
        vh.previous_owners, vh.accident_count, vh.is_stolen
      FROM listings l
      JOIN car_models cm ON l.car_model_id = cm.id
      JOIN oracle_scores os ON l.id = os.listing_id
      JOIN users u ON l.seller_id = u.id
      LEFT JOIN market_prices mp 
        ON mp.make = cm.make AND mp.model = cm.model AND mp.year = cm.year
      LEFT JOIN vehicle_history vh ON vh.listing_id = l.id
      WHERE l.price <= $1 * 1.15
        AND l.status = 'active'
        AND (vh.is_stolen = false OR vh.is_stolen IS NULL)
      ${orderClause}
      LIMIT 10
    `, [budget, lang]);

    const enriched = rows.map(car => {
      const age = new Date().getFullYear() - car.year;
      if (persona === 'Safety First' && car.safety_grade < 4) {
        car.negotiation_strategy += ' | ⚠️ Low Safety Grade for Family use.';
      }
      if (age > 18) {
        car.end_of_life_warning = true;
        car.negotiation_strategy += ' | ⚠️ Near Scrapping Age.';
      } else if (age > 12) {
        car.projected_annual_maintenance_cost = Number(car.projected_annual_maintenance_cost) * 1.15;
      }
      if (experienceLevel === 'New' && car.smart_score < 6) {
        car.negotiation_strategy += ' | ℹ️ Better options exist for new drivers.';
      }
      return {
        ...car,
        persona,
        price_position: getPricePosition(car.price, car.price_low, car.price_avg, car.price_high),
      };
    });

    res.json(enriched);
  } catch (err) {
    console.error('[recommendations]', err.message);
    res.status(500).json({ error: 'Could not fetch recommendations' });
  }
});

// ═══════════════════════════════════════════════════════════
// SUBMIT REVIEW (Two-way)
// ═══════════════════════════════════════════════════════════
app.post('/api/reviews', async (req, res) => {
  try {
    const { listing_id, reviewer_id, reviewee_id, reviewer_role, rating, comment, was_honest, was_on_time, car_matched_description } = req.body;

    if (!listing_id || !reviewer_id || !reviewee_id || !reviewer_role || !rating) {
      return res.status(400).json({ error: 'Missing required fields' });
    }
    if (!['buyer', 'seller'].includes(reviewer_role)) {
      return res.status(400).json({ error: 'reviewer_role must be buyer or seller' });
    }

    const { rows } = await pool.query(`
      INSERT INTO reviews (listing_id, reviewer_id, reviewee_id, reviewer_role, rating, comment, was_honest, was_on_time, car_matched_description)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
      RETURNING *
    `, [listing_id, reviewer_id, reviewee_id, reviewer_role, rating, comment, was_honest, was_on_time, car_matched_description]);

    // Update user trust score
    await pool.query(`
      UPDATE users SET trust_score = (
        SELECT ROUND(AVG(rating)::numeric, 1) FROM reviews WHERE reviewee_id = $1
      ) WHERE id = $1
    `, [reviewee_id]);

    res.status(201).json(rows[0]);
  } catch (err) {
    console.error('[reviews]', err.message);
    res.status(500).json({ error: 'Could not submit review' });
  }
});

// ═══════════════════════════════════════════════════════════
// COMMUNITY FEED
// ═══════════════════════════════════════════════════════════
app.get('/api/community', async (req, res) => {
  try {
    const lang = req.query.lang || 'en';
    const { rows } = await pool.query(`
      SELECT 
        cp.id, cp.category, cp.upvotes, cp.is_pinned, cp.created_at,
        CASE WHEN $1 = 'he' THEN cp.title_he ELSE cp.title_en END AS title,
        CASE WHEN $1 = 'he' THEN cp.body_he ELSE cp.body_en END AS body,
        u.full_name AS author_name, u.id_verified AS author_verified,
        u.trust_score AS author_trust,
        COUNT(cr.id) AS reply_count
      FROM community_posts cp
      JOIN users u ON cp.author_id = u.id
      LEFT JOIN community_replies cr ON cr.post_id = cp.id
      GROUP BY cp.id, u.id
      ORDER BY cp.is_pinned DESC, cp.upvotes DESC, cp.created_at DESC
      LIMIT 30
    `, [lang]);
    res.json(rows);
  } catch (err) {
    console.error('[community]', err.message);
    res.status(500).json({ error: 'Could not fetch community posts' });
  }
});

app.post('/api/community', async (req, res) => {
  try {
    const { author_id, title_he, title_en, body_he, body_en, category } = req.body;
    const { rows } = await pool.query(`
      INSERT INTO community_posts (author_id, title_he, title_en, body_he, body_en, category)
      VALUES ($1, $2, $3, $4, $5, $6) RETURNING *
    `, [author_id, title_he, title_en, body_he, body_en, category || 'question']);
    res.status(201).json(rows[0]);
  } catch (err) {
    console.error('[community post]', err.message);
    res.status(500).json({ error: 'Could not create post' });
  }
});

// ═══════════════════════════════════════════════════════════
// SELLER PROFILE
// ═══════════════════════════════════════════════════════════
app.get('/api/users/:id', async (req, res) => {
  try {
    const { rows } = await pool.query(`
      SELECT 
        u.id, u.full_name, u.avatar_url, u.id_verified, u.id_verified_at,
        u.trust_score, u.total_sales, u.total_purchases, u.member_since,
        u.preferred_language,
        ROUND(AVG(r.rating), 1) AS avg_rating,
        COUNT(r.id) AS review_count
      FROM users u
      LEFT JOIN reviews r ON r.reviewee_id = u.id
      WHERE u.id = $1
      GROUP BY u.id
    `, [req.params.id]);

    if (rows.length === 0) return res.status(404).json({ error: 'User not found' });

    const { rows: reviews } = await pool.query(`
      SELECT r.rating, r.comment, r.reviewer_role, r.was_honest,
             r.was_on_time, r.car_matched_description, r.created_at,
             u.full_name AS reviewer_name, u.id_verified AS reviewer_verified
      FROM reviews r
      JOIN users u ON r.reviewer_id = u.id
      WHERE r.reviewee_id = $1
      ORDER BY r.created_at DESC
    `, [req.params.id]);

    const { rows: listings } = await pool.query(`
      SELECT l.id, l.price, l.year, l.image_url, cm.make, cm.model, l.status
      FROM listings l JOIN car_models cm ON l.car_model_id = cm.id
      WHERE l.seller_id = $1 ORDER BY l.created_at DESC LIMIT 5
    `, [req.params.id]);

    res.json({ ...rows[0], reviews, listings });
  } catch (err) {
    console.error('[user profile]', err.message);
    res.status(500).json({ error: 'Could not fetch profile' });
  }
});

// ═══════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════
function getPricePosition(price, low, avg, high) {
  if (!low || !avg || !high) return 'unknown';
  if (price < low) return 'great_deal';       // Green — below market
  if (price <= avg) return 'fair';            // Blue — at market
  if (price <= high) return 'above_average';  // Yellow — above market
  return 'overpriced';                        // Red — significantly over
}

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`✅ MotoMind v2 API on port ${PORT}`));
