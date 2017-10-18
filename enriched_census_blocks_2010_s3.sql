\copy (
WITH cte_census_block_areas AS (
	SELECT
		geoid10 AS geoid10_area,
		CASE 	WHEN SUM(irr_area_sf_cgu_new + other_area_sf_cgu) = 0 THEN null
			ELSE SUM(turf_area_sf_cgu)
		END turf_area_sf,
		CASE 	WHEN SUM(irr_area_sf_cgu_new + other_area_sf_cgu) = 0 THEN null
			ELSE SUM(treeshrub_area_sf_cgu)
		END trees_and_shrubs_area_sf,
		CASE 	WHEN SUM(irr_area_sf_cgu_new + other_area_sf_cgu) = 0 THEN null
			ELSE SUM(irr_area_sf_cgu_new)
		END landscaped_area_sf,
		CASE 	WHEN SUM(irr_area_sf_cgu_new + other_area_sf_cgu) = 0 THEN null
			ELSE SUM(irr_area_sf_cgu_new + other_area_sf_cgu)
		END total_area_sf,
		CASE 	WHEN SUM(irr_area_sf_cgu_new + other_area_sf_cgu) = 0 THEN null
			ELSE SUM(turf_area_sf_cgu) / SUM(irr_area_sf_cgu_new + other_area_sf_cgu)
		END percent_turf,
		CASE 	WHEN SUM(irr_area_sf_cgu_new + other_area_sf_cgu) = 0 THEN null
			ELSE SUM(treeshrub_area_sf_cgu) / SUM(irr_area_sf_cgu_new + other_area_sf_cgu)
		END percent_trees_and_shrubs,
		CASE 	WHEN SUM(irr_area_sf_cgu_new + other_area_sf_cgu) = 0 THEN null
			ELSE SUM(irr_area_sf_cgu_new)/SUM(irr_area_sf_cgu_new + other_area_sf_cgu)
		END percent_landscaped,
		COUNT(assessor_polygon_id) AS parcel_count
		
	FROM assessor_polygons
	WHERE residential = 't'
	GROUP BY geoid10
),

cte_census_blockgroups_2016_with_stats_clean AS (
	SELECT
	cbs.*,
	"percent_less_than_high_school" ed1,
	"percent_high_school_grad_equiv" ed2,
	"percent_some_college" ed3,
	"percent_bachelors_degree" ed4,
	"percent_masters_degree" ed5,
	"percent_professional_degree" ed6,
	"percent_doctorate_degree" ed7
	FROM census_blockgroups_2016_with_stats cbs
),

cte_census_block_geoms_and_group_stats AS (
	SELECT
		b.geom,
		b.geoid10,
		b.countyfp10,

		pop_density_acs_2015,
		avg_hhsize,
		median_hh_income,
		median_year_structure_built,
		(percent_bachelors_degree +
		percent_masters_degree +
		percent_professional_degree +
		percent_doctorate_degree) AS percent_with_college_degree,
		CASE
			WHEN GREATEST(ed1, ed2, ed3, ed4, ed5, ed6, ed7) = ed1
			THEN 'Less than High School | ' || ed1 || '%'
			WHEN GREATEST(ed1, ed2, ed3, ed4, ed5, ed6, ed7) = ed2
			THEN 'High School Graduate (or equivalent) | ' || ed2 || '%'
			WHEN GREATEST(ed1, ed2, ed3, ed4, ed5, ed6, ed7) = ed3
			THEN 'Some College | ' || ed3 || '%'
			WHEN GREATEST(ed1, ed2, ed3, ed4, ed5, ed6, ed7) = ed4
			THEN 'Bachelor''s Degree | ' || ed4 || '%'
			WHEN GREATEST(ed1, ed2, ed3, ed4, ed5, ed6, ed7) = ed5
			THEN 'Master''s Degree | ' || ed5 || '%'
			WHEN GREATEST(ed1, ed2, ed3, ed4, ed5, ed6, ed7) = ed5
			THEN 'Master''s Degree | ' || ed5 || '%'
			WHEN GREATEST(ed1, ed2, ed3, ed4, ed5, ed6, ed7) = ed6
			THEN 'Professional School Degree | ' || ed6 || '%'
			WHEN GREATEST(ed1, ed2, ed3, ed4, ed5, ed6, ed7) = ed7
			THEN 'Doctorate Degree | ' || ed7 || '%'  
			ELSE 'No Data'
		END characteristic_educational_attainment

	FROM census_block_polygons_2010 b, cte_census_blockgroups_2016_with_stats_clean bg
	WHERE left(b.geoid10,12) = geoid
),

mwd_rebates_aggregated AS (
	SELECT geoid10,
		SUM("post_total_sq._feet") AS total_turf_removed_sf,
		AVG("post_total_sq._feet") AS avg_turf_removed_sf,
		COUNT(*) AS rebate_count
	FROM mwd_turf_rebates, census_block_polygons_2010
	WHERE ST_Within(ST_SetSRID(ST_Point(cust_loc_longitude_geocoded, cust_loc_latitude_geocoded), 4326), geom)
		AND pre_review_status = 'APPROVED'
		AND "post_total_sq._feet" > 0
		AND building_type in (	'Single Family Home',
					'Duplex/Triplex/Fourplex',
					'Multi Family / HOA Common Area',
					'Townhome',
					'Mobile Home')
	GROUP BY geoid10
),
census_blocks_with_group_stats AS (
	SELECT
	a.*,
	s.*
	FROM cte_census_block_areas a, cte_census_block_geoms_and_group_stats s
	WHERE a.geoid10_area = s.geoid10
)

SELECT
	c.*,
	m.*, 
	CASE 
		WHEN turf_area_sf = 0 THEN null
		WHEN total_turf_removed_sf IS null THEN 0
		ELSE total_turf_removed_sf/turf_area_sf
	END turf_removed_percent_of_turf_area,
	CASE
		WHEN total_area_sf = 0 THEN null
		WHEN total_turf_removed_sf IS null THEN 0
		ELSE total_turf_removed_sf/total_area_sf
	END turf_removed_percent_of_total_area,
	CASE
		WHEN parcel_count = 0 THEN null
		WHEN rebate_count IS null THEN 0
		ELSE CAST (rebate_count AS FLOAT)/parcel_count
	END percent_parcels_with_rebate,
	CASE
		WHEN rebate_count IS null THEN 0
		ELSE rebate_count
	END rebate_count_filled,
	CASE
		WHEN total_turf_removed_sf is null THEN 0
		ELSE total_turf_removed_sf
	END total_turf_removed_sf_filled,
	CASE
		WHEN avg_turf_removed_sf is null THEN 0
		ELSE avg_turf_removed_sf
	END avg_turf_removed_sf_filled
FROM census_blocks_with_group_stats c
LEFT JOIN mwd_rebates_aggregated m
ON c.geoid10 = m.geoid10
WHERE ST_WITHIN(
	geom,
	(SELECT st_transform(st_setsrid(geom, 3857), 4326) FROM agency_polygons WHERE agencyname = 'Meteropolitan Water District of Southern California')
)
)
TO '~/enriched_census_blocks_2010_s3.csv'
WITH CSV HEADER;