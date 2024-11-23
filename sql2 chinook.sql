use chinook;
-- 2.Top-Selling Tracks in the USA:
SELECT 
    t.name AS track_name, -- Top-selling track
    ar.name AS artist_name, -- Top artist
    g.name AS genre_name, -- Most famous genre
    SUM(il.quantity * il.unit_price) AS total_sales -- Total sales for the track
FROM invoice_line il
JOIN invoice i ON il.invoice_id = i.invoice_id
JOIN track t ON il.track_id = t.track_id
JOIN album al ON t.album_id = al.album_id
JOIN artist ar ON al.artist_id = ar.artist_id
JOIN genre g ON t.genre_id = g.genre_id
WHERE i.billing_country = 'USA' -- Restrict to sales in the USA
GROUP BY t.track_id, ar.artist_id, g.genre_id -- Group by track, artist, and genre
ORDER BY total_sales DESC
LIMIT 5; -- Return the top-selling track and associated artist and genre


-- 3. Customer Demographics breakdown (age, gender, location) of Chinook's customer base:
SELECT e.first_name, e.last_name, e.country, 
       YEAR(CURDATE()) - YEAR(e.birthdate) AS age,
       COUNT(i.invoice_id) AS total_purchases
FROM employee e
LEFT JOIN customer c ON e.employee_id = c.support_rep_id
LEFT JOIN invoice i ON c.customer_id = i.customer_id
GROUP BY e.employee_id, e.first_name, e.last_name, e.country;

-- 4. Total Revenue and No. of Invoices for each country, state, and city:
SELECT 
    c.country, 
    COALESCE(c.state, 'Unknown') AS state, 
    COALESCE(c.city, 'Unknown') AS city, 
    SUM(i.total) AS total_revenue, 
    COUNT(i.invoice_id) AS total_invoices
FROM invoice i
JOIN customer c ON i.customer_id = c.customer_id
GROUP BY c.country, c.state, c.city
ORDER BY total_revenue DESC;

SELECT c.country, c.state, c.city, SUM(i.total) AS total_revenue, COUNT(i.invoice_id) AS total_invoices
FROM invoice i
JOIN customer c ON i.customer_id = c.customer_id
WHERE c.state IS NOT NULL
GROUP BY c.country, c.state, c.city
ORDER BY total_revenue DESC;


-- 5. Top 5 customers by total revenue in each country
WITH customer_revenue AS (
    SELECT 
        c.customer_id,
        c.first_name,
        c.last_name,
        c.country,
        SUM(il.quantity * il.unit_price) AS total_revenue
    FROM customer c
    JOIN invoice i ON c.customer_id = i.customer_id
    JOIN invoice_line il ON i.invoice_id = il.invoice_id
    GROUP BY c.customer_id, c.first_name, c.last_name, c.country
),
ranked_customers AS (
    SELECT 
        customer_id,
        first_name,
        last_name,
        country,
        total_revenue,
        RANK() OVER (PARTITION BY country ORDER BY total_revenue DESC) AS revenue_rank
    FROM customer_revenue
)
SELECT 
    customer_id,
    first_name,
    last_name,
    country,
    total_revenue
FROM ranked_customers
WHERE revenue_rank <= 5
ORDER BY country, revenue_rank;


-- 6.Top-Selling Track for Each Customer
WITH customer_track_sales AS (
    SELECT 
        c.customer_id,
        c.first_name,
        c.last_name,
        t.track_id,
        t.name AS track_name,
        SUM(il.quantity * il.unit_price) AS track_revenue
    FROM customer c
    JOIN invoice i ON c.customer_id = i.customer_id
    JOIN invoice_line il ON i.invoice_id = il.invoice_id
    JOIN track t ON il.track_id = t.track_id
    GROUP BY c.customer_id, t.track_id, t.name
),
ranked_tracks AS (
    SELECT 
        customer_id,
        first_name,
        last_name,
        track_id,
        track_name,
        track_revenue,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY track_revenue DESC, t.track_id) AS track_rank
    FROM customer_track_sales t
)
SELECT 
    customer_id,
    first_name,
    last_name,
    track_id,
    track_name,
    track_revenue
FROM ranked_tracks
WHERE track_rank = 1
ORDER BY customer_id;


-- 7. Are there any patterns or trends in customer purchasing behavior (e.g., frequency of purchases, preferred payment methods, average order value)?
SELECT c.customer_id, c.country, COUNT(i.invoice_id) AS total_purchases, AVG(i.total) AS average_order_value
FROM invoice i
JOIN customer c ON i.customer_id = c.customer_id
GROUP BY c.customer_id, c.country;

-- 8. Customer Churn Rate
WITH 
start_of_year_customers AS 
(
    -- Customers who made a purchase in the first quarter (Jan - Mar 2020)
    SELECT customer_id 
    FROM invoice
    WHERE invoice_date BETWEEN '2020-01-01' AND '2020-03-31'
),
end_of_year_customers AS 
(
    -- Customers who made a purchase in the last quarter (Oct - Dec 2020)
    SELECT customer_id 
    FROM invoice
    WHERE invoice_date BETWEEN '2020-10-01' AND '2020-12-31'
)
SELECT 
    COUNT(DISTINCT start.customer_id) AS total_start_of_year_customers,
    COUNT(DISTINCT end.customer_id) AS total_end_of_year_customers,
    (COUNT(DISTINCT start.customer_id) - COUNT(DISTINCT end.customer_id)) AS lost_customers,
    ((COUNT(DISTINCT start.customer_id) - COUNT(DISTINCT end.customer_id)) / COUNT(DISTINCT start.customer_id)) * 100 AS customer_churn_rate
FROM 
    start_of_year_customers start
LEFT JOIN 
    end_of_year_customers end
    ON start.customer_id = end.customer_id;



-- 9.percentage of total sales contributed by each genre in the USA and identify the best-selling genres and artists:
WITH GenreSales AS (
  SELECT g.name AS genre, SUM(il.quantity) AS total_sales, SUM(il.quantity * t.unit_price) AS total_revenue
  FROM invoice_line il
  JOIN track t ON il.track_id = t.track_id
  JOIN genre g ON t.genre_id = g.genre_id
  JOIN invoice i ON il.invoice_id = i.invoice_id
  JOIN customer as c ON i.customer_id = c.customer_id
  WHERE c.country = 'USA'
  GROUP BY g.name
),

TopSellingArtists AS (
  SELECT a.name AS artist_name, SUM(il.quantity) AS total_sales
  FROM invoice_line il
  JOIN track t ON il.track_id = t.track_id
  JOIN album ON t.album_id = album.album_id
  JOIN artist a ON album.artist_id = a.artist_id  -- Join with artist table
  JOIN genre g ON t.genre_id = g.genre_id
  JOIN invoice i ON il.invoice_id = i.invoice_id
  JOIN customer c ON i.customer_id = c.customer_id 
  WHERE c.country = 'USA'
  GROUP BY a.name
  ORDER BY total_sales DESC
  LIMIT 10
)

SELECT genre, total_sales, (total_sales / (SELECT SUM(total_sales) FROM GenreSales)) * 100 AS percentage_of_total_sales,
       (SELECT artist_name FROM TopSellingArtists WHERE genre = GenreSales.genre ORDER BY total_sales DESC LIMIT 1) AS top_artist
FROM GenreSales
ORDER BY total_sales DESC;

-- 10.Customers Who Purchased Tracks from at Least 3 Genres
SELECT c.customer_id, c.first_name, c.last_name
FROM invoice_line il
JOIN track t ON il.track_id = t.track_id
JOIN genre g ON t.genre_id = g.genre_id
JOIN customer c ON il.invoice_id = c.customer_id
GROUP BY c.customer_id
HAVING COUNT(DISTINCT g.genre_id) >= 3;

-- 11.Ranking Genres Based on Sales Performance in the USA
WITH GenreSales AS (
  SELECT g.name AS genre, SUM(il.quantity) AS total_sales
  FROM invoice_line il
  JOIN track t ON il.track_id = t.track_id
  JOIN genre g ON t.genre_id = g.genre_id
  JOIN invoice i ON il.invoice_id = i.invoice_id
  JOIN customer c ON i.customer_id = c.customer_id
  WHERE c.country = 'USA'
  GROUP BY g.name
)

SELECT genre, total_sales, RANK() OVER (ORDER BY total_sales DESC) AS genre_rank
FROM GenreSales;

-- 12. Customers with No Purchases in the Last 3 Months
SELECT c.customer_id, c.first_name, c.last_name
FROM customer c
LEFT JOIN invoice i ON c.customer_id = i.customer_id
WHERE i.invoice_id IS NULL OR i.invoice_date < DATE_SUB(CURDATE(), INTERVAL 3 MONTH)
GROUP BY c.customer_id;

-- subjective
-- 1.Recommend the three albums from the new record label that should be prioritised for advertising and promotion in the USA based on genre sales analysis.

WITH top_genres AS (
    SELECT 
        g.genre_id,
        g.name AS genre_name
    FROM genre g
    JOIN track t ON g.genre_id = t.genre_id
    JOIN invoice_line il ON t.track_id = il.track_id
    JOIN invoice i ON il.invoice_id = i.invoice_id
    WHERE i.billing_country = 'USA'
    GROUP BY g.genre_id, g.name
    ORDER BY SUM(il.quantity * il.unit_price) DESC
    LIMIT 3
)
SELECT 
    al.title AS album_title,
    ar.name AS artist_name,
    g.name,
    SUM(il.quantity * il.unit_price) AS total_album_sales
FROM album al
JOIN artist ar ON al.artist_id = ar.artist_id
JOIN track t ON al.album_id = t.album_id
JOIN genre g ON t.genre_id = g.genre_id
JOIN invoice_line il ON t.track_id = il.track_id
JOIN invoice i ON il.invoice_id = i.invoice_id
JOIN top_genres tg ON g.genre_id = tg.genre_id
WHERE i.billing_country = 'USA'
GROUP BY al.album_id, al.title, ar.name, g.name
ORDER BY total_album_sales DESC
LIMIT 3;


-- 2. Top selling genres in other countries 
SELECT 
    i.billing_country,
    g.name AS genre_name,
    SUM(il.quantity * il.unit_price) AS total_sales
FROM invoice_line il
JOIN track t ON il.track_id = t.track_id
JOIN genre g ON t.genre_id = g.genre_id
JOIN invoice i ON il.invoice_id = i.invoice_id
WHERE i.billing_country != 'USA'
GROUP BY i.billing_country, g.genre_id, g.name
ORDER BY i.billing_country, total_sales DESC;
-- OR the below query
WITH country_genre_sales AS (
    SELECT 
        i.billing_country,
        g.name AS genre_name,
        SUM(il.quantity * il.unit_price) AS total_sales,
        RANK() OVER (PARTITION BY i.billing_country ORDER BY SUM(il.quantity * il.unit_price) DESC) AS genre_rank
    FROM invoice_line il
    JOIN track t ON il.track_id = t.track_id
    JOIN genre g ON t.genre_id = g.genre_id
    JOIN invoice i ON il.invoice_id = i.invoice_id
    WHERE i.billing_country != 'USA'
    GROUP BY i.billing_country, g.genre_id, g.name
)
SELECT 
    billing_country,
    genre_name,
    total_sales
FROM country_genre_sales
WHERE genre_rank = 1
ORDER BY billing_country, total_sales DESC;

-- 3. Customer purchasing behaviour
WITH CustomerPurchaseHistory AS (
  SELECT 
    c.customer_id, 
    c.first_name, 
    c.last_name, 
    COUNT(i.invoice_id) AS total_purchases, 
    AVG(i.total) AS average_order_value, 
    MIN(i.invoice_date) AS first_purchase_date
  FROM invoice i
  JOIN customer c ON i.customer_id = c.customer_id
  GROUP BY c.customer_id
)

SELECT 
    customer_id, 
    first_name, 
    last_name, 
    total_purchases, 
    average_order_value, 
    DATEDIFF(CURDATE(), first_purchase_date) AS days_since_first_purchase,
    CASE 
      WHEN DATEDIFF(CURDATE(), first_purchase_date) >= 365 THEN 'Long-Term' 
      ELSE 'New' 
    END AS customer_type
FROM CustomerPurchaseHistory;


-- 4. product affinity analysis 
WITH GenreArtistAlbumPairs AS (
    SELECT 
        il1.invoice_id, 
        t1.genre_id AS genre1, t2.genre_id AS genre2,
        ar1.artist_id AS artist1, ar2.artist_id AS artist2,
        t1.album_id AS album1, t2.album_id AS album2
    FROM invoice_line il1
    JOIN track t1 ON il1.track_id = t1.track_id
    JOIN album al1 ON t1.album_id = al1.album_id
    JOIN artist ar1 ON al1.artist_id = ar1.artist_id
    JOIN invoice_line il2 ON il1.invoice_id = il2.invoice_id AND il1.track_id != il2.track_id
    JOIN track t2 ON il2.track_id = t2.track_id
    JOIN album al2 ON t2.album_id = al2.album_id
    JOIN artist ar2 ON al2.artist_id = ar2.artist_id
)
-- Genre Co-Purchases
SELECT 
    g1.name AS genre1_name, 
    g2.name AS genre2_name, 
    COUNT(*) AS co_purchases,
    1 AS result_type
FROM GenreArtistAlbumPairs
JOIN genre g1 ON genre1 = g1.genre_id
JOIN genre g2 ON genre2 = g2.genre_id
WHERE genre1 < genre2 -- Avoid duplicate pairs
GROUP BY g1.name, g2.name
HAVING COUNT(*) > 5 -- Only show pairs with significant co-purchases

UNION ALL

-- Artist Co-Purchases
SELECT 
    ar1.name AS artist1_name, 
    ar2.name AS artist2_name, 
    COUNT(*) AS co_purchases,
    2 AS result_type
FROM GenreArtistAlbumPairs
JOIN artist ar1 ON artist1 = ar1.artist_id
JOIN artist ar2 ON artist2 = ar2.artist_id
WHERE artist1 < artist2 -- Avoid duplicate pairs
GROUP BY ar1.name, ar2.name
HAVING COUNT(*) > 5 -- Only show pairs with significant co-purchases

UNION ALL

-- Album Co-Purchases
SELECT 
    al1.title AS album1_name, 
    al2.title AS album2_name, 
    COUNT(*) AS co_purchases,
    3 AS result_type
FROM GenreArtistAlbumPairs
JOIN album al1 ON album1 = al1.album_id
JOIN album al2 ON album2 = al2.album_id
WHERE album1 < album2 -- Avoid duplicate pairs
GROUP BY al1.title, al2.title
HAVING COUNT(*) > 5 -- Only show pairs with significant co-purchases

-- ORDER BY co_purchases DESC (column 3 in the result)
ORDER BY result_type ASC, co_purchases DESC;


-- 5. Regional Market Analysis:
WITH initial_customers AS (
    SELECT 
        billing_country, 
        COUNT(DISTINCT customer_id) AS total_customers 
    FROM invoice
    WHERE invoice_date BETWEEN '2017-01-01' AND '2017-03-31'
    GROUP BY billing_country
),
recent_customers AS (
    SELECT 
        billing_country, 
        COUNT(DISTINCT customer_id) AS recent_customers 
    FROM invoice
    WHERE invoice_date BETWEEN '2020-11-01' AND '2020-12-31'
    GROUP BY billing_country
)
SELECT 
    ic.billing_country, 
    (ic.total_customers - COALESCE(rc.recent_customers, 0)) / ic.total_customers * 100 AS churn_rate
FROM initial_customers ic
LEFT JOIN recent_customers rc ON ic.billing_country = rc.billing_country;
WITH initial_customers_city AS (
    SELECT 
        billing_city, 
        COUNT(DISTINCT customer_id) AS total_customers 
    FROM invoice
    WHERE invoice_date BETWEEN '2017-01-01' AND '2017-03-31'
    GROUP BY billing_city
),
recent_customers_city AS (
    SELECT 
        billing_city, 
        COUNT(DISTINCT customer_id) AS recent_customers 
    FROM invoice
    WHERE invoice_date BETWEEN '2020-11-01' AND '2020-12-31'
    GROUP BY billing_city
)
SELECT 
    ic.billing_city, 
    (ic.total_customers - COALESCE(rc.recent_customers, 0)) / ic.total_customers * 100 AS churn_rate
FROM initial_customers_city ic
LEFT JOIN recent_customers_city rc ON ic.billing_city = rc.billing_city;
WITH initial_customers_state AS (
    SELECT 
        billing_state, 
        COUNT(DISTINCT customer_id) AS total_customers 
    FROM invoice
    WHERE invoice_date BETWEEN '2017-01-01' AND '2017-03-31'
    GROUP BY billing_state
),
recent_customers_state AS (
    SELECT 
        billing_state, 
        COUNT(DISTINCT customer_id) AS recent_customers 
    FROM invoice
    WHERE invoice_date BETWEEN '2020-11-01' AND '2020-12-31'
    GROUP BY billing_state
)
SELECT 
    ic.billing_state, 
    (ic.total_customers - COALESCE(rc.recent_customers, 0)) / ic.total_customers * 100 AS churn_rate
FROM initial_customers_state ic
LEFT JOIN recent_customers_state rc ON ic.billing_state = rc.billing_state;
SELECT 
    billing_country, 
    COUNT(invoice_id) AS invoice_count, 
    AVG(total) AS average_sales 
FROM invoice
GROUP BY billing_country
ORDER BY COUNT(invoice_id) DESC, AVG(total) DESC;


-- 6. customer risk profiling
WITH CustomerPurchaseData AS (
    SELECT 
        c.customer_id, 
        c.first_name, 
        c.last_name, 
        c.country, 
        COUNT(i.invoice_id) AS total_purchases, 
        SUM(i.total) AS total_spent, 
        MAX(i.invoice_date) AS last_purchase_date
    FROM customer c
    JOIN invoice i ON c.customer_id = i.customer_id
    GROUP BY c.customer_id, c.first_name, c.last_name,c.country
),
CustomerRisk AS (
    SELECT 
        cpd.customer_id,
        cpd.first_name,
        cpd.last_name,
        cpd.country,
        cpd.total_purchases,
        cpd.total_spent,
        DATEDIFF(CURDATE(), cpd.last_purchase_date) AS days_since_last_purchase,
        CASE 
            WHEN DATEDIFF(CURDATE(), cpd.last_purchase_date) > 180 THEN 'High Risk'
            WHEN DATEDIFF(CURDATE(), cpd.last_purchase_date) BETWEEN 90 AND 180 THEN 'Medium Risk'
            ELSE 'Low Risk'
        END AS risk_level
    FROM CustomerPurchaseData cpd
)
SELECT 
    customer_id, 
    first_name, 
    last_name, 
    country, 
    total_purchases, 
    total_spent, 
    days_since_last_purchase, 
    risk_level
FROM CustomerRisk
ORDER BY risk_level DESC, days_since_last_purchase DESC;
SELECT i.customer_id, CONCAT(first_name, " ", last_name) name, billing_country, invoice_date, SUM(total) total_spending, COUNT(invoice_id) num_of_orders FROM invoice i
LEFT JOIN customer c on c.customer_id = i.customer_id
GROUP BY 1,2,3,4
ORDER BY name


-- 7. Customer Lifetime Value Modelling:
-- Query to Calculate CLV Components:

WITH CustomerMetrics AS (
    SELECT 
        c.customer_id, 
        c.first_name, 
        c.last_name, 
        MIN(i.invoice_date) AS first_purchase_date,
        MAX(i.invoice_date) AS last_purchase_date,
        COUNT(i.invoice_id) AS total_purchases, 
        SUM(i.total) AS total_spent,
        DATEDIFF(CURDATE(), MIN(i.invoice_date)) AS customer_tenure,  -- days since first purchase
        DATEDIFF(MAX(i.invoice_date), MIN(i.invoice_date)) AS active_period, -- duration between first and last purchase
        AVG(i.total) AS avg_order_value,  -- average amount spent per purchase
        COUNT(i.invoice_id) / DATEDIFF(MAX(i.invoice_date), MIN(i.invoice_date)) AS purchase_frequency -- purchases per day
    FROM customer c
    JOIN invoice i ON c.customer_id = i.customer_id
    GROUP BY c.customer_id
),
CustomerCLV AS (
    SELECT 
        customer_id, 
        first_name, 
        last_name, 
        customer_tenure, 
        total_purchases, 
        total_spent,
        avg_order_value,
        purchase_frequency,
        -- Calculate CLV: avg_order_value * purchase_frequency * customer_tenure
        (avg_order_value * purchase_frequency * customer_tenure) AS predicted_lifetime_value
    FROM CustomerMetrics
)
SELECT 
    customer_id, 
    first_name, 
    last_name, 
    total_purchases, 
    total_spent, 
    avg_order_value, 
    purchase_frequency, 
    customer_tenure, 
    predicted_lifetime_value
FROM CustomerCLV
ORDER BY predicted_lifetime_value DESC;

-- Query to Identify Inactive Customers:
WITH InactiveCustomers AS (
    SELECT 
        c.customer_id, 
        c.first_name, 
        c.last_name, 
        MAX(i.invoice_date) AS last_purchase_date,
        DATEDIFF(CURDATE(), MAX(i.invoice_date)) AS days_since_last_purchase,
        COUNT(i.invoice_id) AS total_purchases,
        SUM(i.total) AS total_spent
    FROM customer c
    JOIN invoice i ON c.customer_id = i.customer_id
    GROUP BY c.customer_id
    HAVING days_since_last_purchase > 180  -- Customers who haven't purchased in 6 months
)
SELECT 
    customer_id, 
    first_name, 
    last_name, 
    total_purchases, 
    total_spent, 
    days_since_last_purchase
FROM InactiveCustomers
ORDER BY days_since_last_purchase DESC;



-- 8. impact on customer acquisition, retention, and overall sales?
-- Measure Impact on Customer Acquisition:
-- Analyze Retention Before and After the Promotion
WITH first_purchase AS (
    SELECT 
        c.customer_id,
        MIN(i.invoice_date) AS first_purchase_date
    FROM customer c
    JOIN invoice i ON c.customer_id = i.customer_id
    GROUP BY c.customer_id
),
retention_analysis AS (
    SELECT 
        f.customer_id,
        DATE_FORMAT(f.first_purchase_date, '%Y-%m') AS acquisition_month,
        COUNT(i.invoice_id) AS purchases_after_acquisition,
        SUM(i.total) AS total_spending_after_acquisition
    FROM first_purchase f
    LEFT JOIN invoice i ON f.customer_id = i.customer_id 
                         AND i.invoice_date > f.first_purchase_date  -- Only purchases after acquisition
    GROUP BY f.customer_id
),
churn_analysis AS (
    SELECT 
        acquisition_month,
        COUNT(customer_id) AS acquired_customers,
        COUNT(CASE WHEN purchases_after_acquisition > 0 THEN 1 END) AS active_customers,  -- Retained customers
        COUNT(CASE WHEN purchases_after_acquisition = 0 THEN 1 END) AS churned_customers -- Customers who churned
    FROM retention_analysis
    GROUP BY acquisition_month
)
SELECT 
    acquisition_month,
    acquired_customers,
    active_customers,
    churned_customers,
    (churned_customers / acquired_customers) AS churn_rate -- Calculate churn rate
FROM churn_analysis
ORDER BY acquisition_month;



-- 10. Alter the Table Album:
ALTER TABLE album ADD COLUMN ReleaseYear INTEGER;

-- 11. understand the purchasing behavior of customers based on their geographical location:
SELECT 
    c.country, 
    COUNT(DISTINCT c.customer_id) AS num_customers, -- Number of customers from each country
    AVG(total_spent_per_customer.total_spent) AS avg_total_spent, -- Average total amount spent by customers
    AVG(total_tracks_per_customer.total_tracks) AS avg_tracks_purchased -- Average number of tracks purchased per customer
FROM customer c
JOIN (
    SELECT 
        i.customer_id,	
        SUM(i.total) AS total_spent
    FROM invoice i
    GROUP BY i.customer_id
) total_spent_per_customer ON c.customer_id = total_spent_per_customer.customer_id
JOIN (
    SELECT 
        i.customer_id, 
        COUNT(il.track_id) AS total_tracks
    FROM invoice_line il
    JOIN invoice i ON il.invoice_id = i.invoice_id
    GROUP BY i.customer_id
) total_tracks_per_customer ON c.customer_id = total_tracks_per_customer.customer_id
GROUP BY c.country
ORDER BY avg_total_spent DESC;







