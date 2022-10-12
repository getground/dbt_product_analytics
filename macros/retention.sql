{% macro retention(event_stream=None, first_action=None, second_action=None, start_date=None, end_date=None, periods=[0,1,7,14,30,60,120], period_type='day', group_by=None) %}
  {% if event_stream is none %}
    {{ exceptions.raise_compiler_error('parameter \'event_stream\' must be provided')}}
  {% endif %}

  {% if first_action is none %}
    {{ exceptions.raise_compiler_error('parameter \'first_action\' must be provided')}}
  {% endif %}

  {% if second_action is none %}
    {{ exceptions.raise_compiler_error('parameter \'second_action\' must be provided')}}
  {% endif %}

  {% if start_date is none %}
    {{ exceptions.raise_compiler_error('parameter \'start_date\' must be provided')}}
  {% endif %}

  {% if end_date is none %}
    {{ exceptions.raise_compiler_error('parameter \'end_date\' must be provided')}}
  {% endif %}
  
  with event_stream as {{ dbt_product_analytics._select_event_stream(event_stream) }}

  , first_event_users as (
    select distinct
      user_id
      {% if group_by %}, {{ group_by }} as dimension {% endif %}
    from event_stream
    where event_date >= {{ dbt_product_analytics._cast_to_date(start_date) }}
    and event_date < {{ dbt_product_analytics._cast_to_date(end_date) }}
  )

  , first_events as (
    select {% if group_by %} dimension, {% endif %}
    count(*) as unique_users_total
    from first_event_users
    {% if group_by %} group by 1 {% endif %}
  )

  {% for period in periods %}
  , secondary_events_{{ period }} as (
    select {{ period }} as period,
    {% if group_by %} {{ group_by }} as dimension, {% endif %}
    count(distinct user_id) as unique_users
    from event_stream
    where event_type = '{{ second_action }}'
    and event_date >= {{ dbt_product_analytics._dateadd(datepart=period_type, interval=period, from_date_or_timestamp=dbt_product_analytics._cast_to_date(end_date)) }}
    and user_id in (
      select user_id from first_event_users
    )

    group by period {% if group_by %}, dimension {% endif %}
  )
  {% endfor %}

  , final as (
    select 
      period, 
      {% if group_by %} first_events.dimension, {% endif %}
      unique_users,
      1.0 * unique_users / unique_users_total as pct_users
    from first_events
    left join (
      {% for period in periods %}
        select * from secondary_events_{{ period }}
        {% if not loop.last %}
          union all
        {% endif %}
      {% endfor %}
    ) secondary_events on  1 = 1
    {% if group_by %}
      and first_events.dimension = secondary_events.dimension
      where period is not null
    {% endif %}
  )

  select * from final
{% endmacro %}