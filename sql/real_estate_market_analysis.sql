/*
Project: Real Estate Market Analysis

Description:
SQL analysis of real estate listings in Saint Petersburg and Leningrad Region.
The project focuses on listing activity duration, seasonal trends,
property characteristics and business recommendations.

Author: Valeria Polishchuk
Date: June 2026

Tools:
PostgreSQL, SQL
*/



/* =====================================================
   PART 1. LISTING ACTIVITY DURATION ANALYSIS
   ===================================================== */
WITH limits AS (
    SELECT
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
-- Identify listing IDs without outliers, while preserving records with missing values:
filtered_id AS(
    SELECT id
    FROM real_estate.flats
    WHERE
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),

    zadacha1 as (
    	select id,
    		days_exposition,
    		first_day_exposition
    	from real_estate.advertisement),
-- Calculate listing activity segments:
-- less than 1 month,
-- 1-3 months,
-- 3-6 months,
-- more than 6 months
    active_time as (select filtered_id.id,
       	case
    		when days_exposition <= 30 then '1. до месяца'
    		when days_exposition < 90 then '2. до трех месяцев'
    		when days_exposition < 180 then '3. до полугода'
    		when days_exposition >= 180 then '4. более полугода'
    		else 'non category'
    	end as ad_activity_time   	
    from zadacha1
    left join filtered_id on filtered_id.id=zadacha1.id
    where EXTRACT(YEAR FROM first_day_exposition) BETWEEN 2015 AND 2018),
    city_category as (
    	select filtered_id.id,
    		case
    			when city_id ='6X8I' then 'Санкт-Петербург'
    			else 'ЛенОбл'
    		end as region_category,
    		total_area,
    		last_price,
    		rooms,
    		balcony,
    		floor 
    	from real_estate.flats
    	left join filtered_id on filtered_id.id=flats.id
    	left join real_estate.advertisement on filtered_id.id=advertisement.id),	
    pre_total_table as (select distinct region_category,
    	ad_activity_time,
    	COUNT(active_time.id) as amnt_of_ad_by_segment,
    	SUM(last_price)/SUM(total_area) as Average_cost_per_sq_m,
    	ROUND(AVG (total_area)::numeric,2) as average_area,
    	percentile_cont(0.5) WITHIN GROUP (ORDER BY rooms) AS median_number_of_rooms,
    	percentile_cont(0.5) WITHIN GROUP (ORDER BY balcony) AS median_number_of_balcony,
    	percentile_cont(0.5) WITHIN GROUP (ORDER BY floor) AS median_number_of_storeys
    from active_time
    left join city_category on active_time.id=city_category.id
    where region_category is not null
    group by region_category, ad_activity_time
    order by region_category, ad_activity_time)
        select region_category,
    	ad_activity_time,
    	amnt_of_ad_by_segment,
    	ROUND(amnt_of_ad_by_segment/SUM(amnt_of_ad_by_segment) filter (where region_category is not null) over (partition by region_category), 2)*100 as share_of_segment_percent,
    	Average_cost_per_sq_m,
    	average_area,
    	median_number_of_rooms,
    	median_number_of_balcony,
    	median_number_of_storeys
    from pre_total_table
    order by region_category desc, ad_activity_time;
    



/* =====================================================
   PART 2. SEASONAL MARKET ANALYSIS
   ===================================================== */
WITH limits AS (
    SELECT
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
-- Identify listing IDs without outliers while preserving records with missing values:
filtered_id AS(
    SELECT id
    FROM real_estate.flats
    WHERE
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
-- Use listing IDs from the filtered_id CTE, which excludes outliers, for further analysis:
    month_of_sales_and_public as (
    	select filtered_id.id,
    		extract (month from first_day_exposition) as month_of_public,
    		extract(month from(first_day_exposition + days_exposition::integer)) as month_of_sale
    	from filtered_id
    	left join real_estate.advertisement on filtered_id.id=advertisement.id
    	left join real_estate.flats on filtered_id.id=flats.id
    	where extract(year from first_day_exposition) between 2015 and 2018),
    month_of_publication as (
    	select 
    		month_of_public,
    		count(month_of_sales_and_public.id) as number_of_ads_publication,
    		SUM(last_price)/SUM(total_area) as average_cost_of_publication,
    		ROUND(AVG(total_area)::numeric,2) as average_area_publication
    	from month_of_sales_and_public
    	left join real_estate.flats on month_of_sales_and_public.id=flats.id
    	left join real_estate.type on flats.type_id=type.type_id
    	left join real_estate.advertisement on advertisement.id=month_of_sales_and_public.id
    	where type ='город'
    	group by month_of_public),
    month_of_sales as (
    	select 
    		month_of_sale,
    		count(month_of_sales_and_public.id) as number_of_ads_removed,
    		SUM(last_price)/SUM(total_area) as average_sale_cost,
    		ROUND(AVG(total_area)::numeric,2) as average_area_cost
    	from month_of_sales_and_public
    	left join real_estate.flats on month_of_sales_and_public.id=flats.id
    	left join real_estate.type on flats.type_id=type.type_id
    	left join real_estate.advertisement on advertisement.id=month_of_sales_and_public.id
    	where type ='город' and month_of_sale is not null
    	group by month_of_sale)
      select month_of_public as month,
    	number_of_ads_publication,
    	round((number_of_ads_publication/sum(number_of_ads_publication) over ())*100,2) as share_of_publication_by_month,
    	number_of_ads_removed,
    	round((number_of_ads_removed/sum(number_of_ads_removed) over ())*100,2) as share_of_ads_cost_by_month,
    	average_cost_of_publication,
    	average_sale_cost,
    	average_area_publication,
    	average_area_cost
    from month_of_publication
    left join month_of_sales on month_of_sale=month_of_public;
