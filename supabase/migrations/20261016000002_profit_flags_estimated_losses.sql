-- A stock loss recorded before the stock it came from was entered is costed
-- at an estimate, like an early sale, so the profit report now flags it too.

create or replace function profit_report(p_from date, p_to date)
returns table (sales_amount numeric, cost_of_goods_sold numeric, sale_costs numeric, trading_profit numeric,
               commission_income numeric, commission_costs numeric, stock_losses numeric,
               expenses numeric, net_profit numeric, has_estimates boolean)
language plpgsql stable security definer set search_path = public as $$
declare
  v_owner uuid := _current_owner();
begin
  return query
  with d as (
    select * from deals
    where owner_id = v_owner and cancelled_at is null and deal_date between p_from and p_to
  ),
  val as (
    select * from _stock_valuation(v_owner) s where s.move_date between p_from and p_to
  ),
  my_costs as (
    select d.kind, sum(c.amount) as amount
    from d join deal_costs c on c.deal_id = d.id
    where c.charged_to_id is null
    group by d.kind
  ),
  r as (
    select
      coalesce((select sum(goods_amount) from d where kind = 'sale'), 0)                                   as sales,
      coalesce((select sum(cost_out) from val where val.deal_id is not null), 0)                           as cogs,
      coalesce((select amount from my_costs where kind = 'sale'), 0)                                       as sale_costs,
      coalesce((select sum(dc.amount) from deal_commissions dc join d on d.id = dc.deal_id), 0)            as commission,
      coalesce((select amount from my_costs where kind = 'commission'), 0)                                 as commission_costs,
      coalesce((select sum(cost_out) from val where val.adjustment_id is not null and val.weight_kg < 0), 0) as losses,
      coalesce((select sum(x.amount) from expenses x
                where x.owner_id = v_owner and x.cancelled_at is null
                  and x.expense_date between p_from and p_to), 0)                                          as expenses,
      coalesce((select bool_or(cost_estimated) from val), false)                                         as estimated
  )
  select r.sales, r.cogs, r.sale_costs,
         r.sales - r.cogs - r.sale_costs,
         r.commission, r.commission_costs, r.losses, r.expenses,
         r.sales - r.cogs - r.sale_costs + r.commission - r.commission_costs - r.losses - r.expenses,
         r.estimated
  from r;
end $$;
