// Ledger rules, tested with real-life examples from the business.
// Run: npm test   (from the supabase folder)
import { afterEach, beforeEach, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { freshDb, nums } from './helpers.mjs';

let L, me, rashid, akram, transporter, cloth;

beforeEach(async () => {
  L = await freshDb();
  me = await L.createUser();
  await L.signIn(me);
  rashid = await L.one('create_party', { p_name: 'Rashid', p_type: 'supplier' });
  akram = await L.one('create_party', { p_name: 'Akram', p_type: 'buyer' });
  transporter = await L.one('create_party', { p_name: 'Bilal Goods', p_type: 'transporter' });
  cloth = await L.one('create_item', { p_name_en: 'Used cloth', p_name_ur: 'پرانا کپڑا' });
});

afterEach(() => L.close());

const deal = (p) => L.one('record_deal', { p: { deal_date: '2026-10-01', ...p } });
const purchase = (p) => deal({ kind: 'purchase', party_id: rashid, item_id: cloth, ...p });
const sale = (p) => deal({ kind: 'sale', party_id: akram, item_id: cloth, ...p });
const profit = async (from = '2026-01-01', to = '2026-12-31') =>
  nums((await L.rpc('profit_report', { p_from: from, p_to: to }))[0]);
const stock = async () => nums((await L.rpc('stock_summary'))[0]);

describe('khata balances', () => {
  test('credit purchase with part payment: we owe the rest', async () => {
    await purchase({ weight_kg: 500, rate: 120, paid_now: 20000 });
    assert.equal(await L.balance(rashid), -40000);
  });

  test('fully credit purchase: we owe the full amount', async () => {
    await purchase({ weight_kg: 500, rate: 120 });
    assert.equal(await L.balance(rashid), -60000);
  });

  test('sale with part payment: buyer owes the rest', async () => {
    await sale({ weight_kg: 200, rate: 150, paid_now: 10000 });
    assert.equal(await L.balance(akram), 20000);
  });

  test('payments go against the running khata, not one bill', async () => {
    await purchase({ weight_kg: 500, rate: 120 });
    await purchase({ weight_kg: 250, rate: 120 });
    await L.rpc('record_payment', { p_party_id: rashid, p_direction: 'out', p_amount: 50000 });
    assert.equal(await L.balance(rashid), -40000);

    await sale({ weight_kg: 100, rate: 150 });
    await L.rpc('record_payment', { p_party_id: akram, p_direction: 'in', p_amount: 15000, p_method: 'bank' });
    assert.equal(await L.balance(akram), 0);
  });

  test('opening balance carries old udhaar into the app', async () => {
    const old = await L.one('create_party', { p_name: 'Saleem', p_opening_balance: 25000 });
    const weOwe = await L.one('create_party', { p_name: 'Nadeem', p_opening_balance: -15000 });
    assert.equal(await L.balance(old), 25000);
    assert.equal(await L.balance(weOwe), -15000);
  });

  test('cancelling a deal reverses every line, including the payment', async () => {
    const id = await purchase({ weight_kg: 500, rate: 120, paid_now: 20000 });
    await L.rpc('cancel_deal', { p_deal_id: id, p_reason: 'wrong party' });

    assert.equal(await L.balance(rashid), 0);
    assert.equal((await L.rpc('party_statement', { p_party_id: rashid })).length, 0);
    const all = await L.rpc('party_statement', { p_party_id: rashid, p_include_cancelled: true });
    assert.equal(all.length, 4);
    await assert.rejects(L.rpc('cancel_deal', { p_deal_id: id }), /already cancelled/);
  });

  test('editing a deal cancels the old one and records the new one', async () => {
    const oldId = await purchase({ weight_kg: 500, rate: 120 });
    const newId = await L.one('replace_deal', {
      p_deal_id: oldId,
      p: { kind: 'purchase', party_id: rashid, item_id: cloth, deal_date: '2026-10-01', weight_kg: 600, rate: 120 },
    });

    assert.equal(await L.balance(rashid), -72000);
    const [d] = await L.query('select replaces_id from deals where id = $1', [newId]);
    assert.equal(d.replaces_id, oldId);
    assert.equal(nums(await stock()).weight_kg, 600);
  });

  test('a wrong payment can be reversed', async () => {
    await purchase({ weight_kg: 500, rate: 120 });
    const pay = await L.one('record_payment', { p_party_id: rashid, p_direction: 'out', p_amount: 10000 });
    await L.rpc('reverse_entry', { p_entry_id: pay, p_reason: 'typed twice' });
    assert.equal(await L.balance(rashid), -60000);
  });

  test('deal lines cannot be reversed one by one', async () => {
    await purchase({ weight_kg: 500, rate: 120 });
    const [line] = await L.query("select id from khata_entries where kind = 'purchase'");
    await assert.rejects(L.rpc('reverse_entry', { p_entry_id: line.id }), /cancel that instead/);
  });

  test('statement shows running balance and balance brought forward', async () => {
    await purchase({ deal_date: '2026-09-10', weight_kg: 100, rate: 100 });
    await purchase({ deal_date: '2026-10-05', weight_kg: 200, rate: 100, paid_now: 5000 });
    await L.rpc('record_payment', { p_party_id: rashid, p_direction: 'out', p_amount: 10000, p_date: '2026-10-06' });

    const rows = (await L.rpc('party_statement', { p_party_id: rashid, p_from: '2026-10-01' })).map(nums);
    assert.deepEqual(rows.map((r) => [r.note, r.amount, r.balance]), [
      ['Balance brought forward', -10000, -10000],
      ['Purchase: Used cloth 200 kg @ 100', -20000, -30000],
      ['Paid on deal — Purchase: Used cloth 200 kg @ 100', 5000, -25000],
      ['Payment made', 10000, -15000],
    ]);
  });
});

describe('deal costs', () => {
  test('freight we pay in cash: no khata line, but cloth costs more', async () => {
    await purchase({ weight_kg: 1000, rate: 100, costs: [{ description: 'Freight', amount: 5000 }] });
    assert.equal(await L.balance(rashid), -100000);
    assert.equal((await stock()).avg_cost, 105);
  });

  test('cost charged to the buyer, paid to transporter on credit', async () => {
    await sale({
      weight_kg: 100, rate: 150,
      costs: [{ description: 'Freight', amount: 3000, charged_to_id: akram, paid_to_id: transporter }],
    });
    assert.equal(await L.balance(akram), 18000);
    assert.equal(await L.balance(transporter), -3000);
    assert.equal((await profit()).sale_costs, 0);
  });

  test('supplier bears freight we paid: reduces what we owe him', async () => {
    await purchase({
      weight_kg: 1000, rate: 100,
      costs: [{ description: 'Freight', amount: 4000, charged_to_id: rashid }],
    });
    assert.equal(await L.balance(rashid), -96000);
    assert.equal((await stock()).avg_cost, 100);
  });

  test('a cost cannot be charged to a party outside the deal', async () => {
    await assert.rejects(
      purchase({ weight_kg: 10, rate: 100, costs: [{ description: 'x', amount: 10, charged_to_id: akram }] }),
      /party of this deal/,
    );
  });
});

describe('commission deals', () => {
  const brokered = (p) => deal({ kind: 'commission', party_id: rashid, buyer_id: akram, item_id: cloth, ...p });

  test('money goes direct between them: only commission is booked', async () => {
    await brokered({
      weight_kg: 1000, rate: 100,
      commissions: [
        { party_id: rashid, mode: 'per_kg', value: 2 },
        { party_id: akram, mode: 'percent', value: 1 },
      ],
    });
    assert.equal(await L.balance(rashid), 2000);
    assert.equal(await L.balance(akram), 1000);
    assert.equal((await profit()).commission_income, 3000);
    assert.equal((await profit()).net_profit, 3000);
    assert.equal((await stock()).weight_kg, 0);
  });

  test('money goes through us: commission is cut from what we pay the seller', async () => {
    await brokered({
      weight_kg: 1000, rate: 100, goods_through_me: true,
      commissions: [{ party_id: rashid, mode: 'per_kg', value: 2 }],
    });
    assert.equal(await L.balance(rashid), -98000);
    assert.equal(await L.balance(akram), 100000);
    assert.equal((await profit()).net_profit, 2000);
  });

  test('fixed commission works without weight or rate', async () => {
    await brokered({ item_id: null, commissions: [{ party_id: akram, mode: 'fixed', value: 5000 }] });
    assert.equal(await L.balance(akram), 5000);
  });

  test('percent commission needs weight and rate', async () => {
    await assert.rejects(
      brokered({ weight_kg: 100, commissions: [{ party_id: akram, mode: 'percent', value: 1 }] }),
      /needs the deal weight and rate/,
    );
  });

  test('commission must come from a party of the deal', async () => {
    await assert.rejects(
      brokered({ commissions: [{ party_id: transporter, mode: 'fixed', value: 100 }] }),
      /seller or the buyer/,
    );
  });

  test('purchase and sale deals cannot carry commission', async () => {
    await assert.rejects(
      purchase({ weight_kg: 10, rate: 1, commissions: [{ party_id: rashid, mode: 'fixed', value: 1 }] }),
      /only be added to a commission deal/,
    );
  });
});

describe('stock and profit', () => {
  test('unsold stock is not a loss', async () => {
    await purchase({ weight_kg: 1000, rate: 100 });
    await sale({ weight_kg: 500, rate: 130 });
    const p = await profit();
    assert.equal(p.trading_profit, 15000);
    assert.deepEqual([(await stock()).weight_kg, (await stock()).stock_value], [500, 50000]);
  });

  test('moving average cost includes our freight', async () => {
    await purchase({ deal_date: '2026-10-01', weight_kg: 1000, rate: 100, costs: [{ description: 'Freight', amount: 5000 }] });
    await purchase({ deal_date: '2026-10-02', weight_kg: 500, rate: 120 });
    await sale({ deal_date: '2026-10-03', weight_kg: 600, rate: 150 });

    const p = await profit();
    assert.equal(p.cost_of_goods_sold, 66000);
    assert.equal(p.trading_profit, 24000);
    const s = await stock();
    assert.deepEqual([s.weight_kg, s.avg_cost, s.stock_value], [900, 110, 99000]);
  });

  test('our costs on a sale reduce profit', async () => {
    await purchase({ weight_kg: 100, rate: 100 });
    await sale({ weight_kg: 100, rate: 130, costs: [{ description: 'Labour', amount: 500 }] });
    assert.equal((await profit()).trading_profit, 2500);
  });

  test('selling before the purchase is entered: allowed, then corrected', async () => {
    await sale({ deal_date: '2026-10-05', weight_kg: 100, rate: 150 });
    assert.equal((await stock()).weight_kg, -100);
    assert.equal((await profit()).has_estimates, true);

    await purchase({ deal_date: '2026-10-01', weight_kg: 100, rate: 100 });
    const p = await profit();
    assert.equal(p.cost_of_goods_sold, 10000);
    assert.equal(p.has_estimates, false);
  });

  test('cancelled deals leave stock and profit', async () => {
    await purchase({ weight_kg: 100, rate: 100 });
    const id = await sale({ weight_kg: 50, rate: 200 });
    await L.rpc('cancel_deal', { p_deal_id: id });
    assert.equal((await stock()).weight_kg, 100);
    assert.equal((await profit()).sales_amount, 0);
  });

  test('opening stock and wastage', async () => {
    await L.rpc('record_stock_adjustment', { p_item_id: cloth, p_weight_kg: 200, p_cost_per_kg: 90, p_date: '2026-09-01' });
    await L.rpc('record_stock_adjustment', { p_item_id: cloth, p_weight_kg: -20, p_date: '2026-10-01', p_reason: 'wet, thrown away' });
    assert.equal((await stock()).weight_kg, 180);
    assert.equal((await profit()).stock_losses, 1800);
    await assert.rejects(
      L.rpc('record_stock_adjustment', { p_item_id: cloth, p_weight_kg: 10 }),
      /added_stock_needs_cost/,
    );
  });

  test('profit only counts the chosen dates', async () => {
    await purchase({ deal_date: '2026-09-01', weight_kg: 200, rate: 100 });
    await sale({ deal_date: '2026-09-15', weight_kg: 100, rate: 120 });
    await sale({ deal_date: '2026-10-15', weight_kg: 100, rate: 140 });
    assert.equal((await profit('2026-09-01', '2026-09-30')).trading_profit, 2000);
    assert.equal((await profit('2026-10-01', '2026-10-31')).trading_profit, 4000);
  });

  test('expenses reduce net profit; expense on credit goes to the khata', async () => {
    await purchase({ weight_kg: 100, rate: 100 });
    await sale({ weight_kg: 100, rate: 150 });
    await L.rpc('record_expense', { p_category: 'Rent', p_amount: 1000, p_date: '2026-10-01' });
    const id = await L.one('record_expense', {
      p_category: 'Labour', p_amount: 700, p_date: '2026-10-01', p_paid_to_id: transporter,
    });
    assert.equal((await profit()).net_profit, 3300);
    assert.equal(await L.balance(transporter), -700);

    await L.rpc('cancel_expense', { p_expense_id: id });
    assert.equal((await profit()).net_profit, 4000);
    assert.equal(await L.balance(transporter), 0);
  });
});

describe('safety', () => {
  test('khata lines cannot be edited or deleted, even by the admin', async () => {
    await purchase({ weight_kg: 10, rate: 100 });
    await assert.rejects(L.query('update khata_entries set amount = 1'), /permission denied/);
    await assert.rejects(L.query('delete from khata_entries'), /permission denied/);

    await L.db.exec('reset role');
    await assert.rejects(L.query('update khata_entries set amount = 1'), /cannot be changed or deleted/);
    await assert.rejects(L.query('delete from deals'), /cannot be deleted/);
    await assert.rejects(L.query('update deals set rate = 1'), /only be cancelled/);
  });

  test('the app cannot write to tables directly', async () => {
    await assert.rejects(
      L.query("insert into parties (owner_id, name) values ($1, 'x')", [me]),
      /permission denied/,
    );
  });

  test('another user cannot see or use my data', async () => {
    await purchase({ weight_kg: 10, rate: 100 });
    const other = await L.createUser();
    await L.signIn(other);

    assert.equal((await L.query('select * from parties')).length, 0);
    assert.equal((await L.query('select * from khata_entries')).length, 0);
    assert.equal((await L.query('select * from party_balances')).length, 0);
    await assert.rejects(purchase({ weight_kg: 1, rate: 1 }), /supplier not found/);
    await assert.rejects(L.rpc('party_statement', { p_party_id: rashid }), /party not found/);
  });

  test('signed-out callers are refused', async () => {
    await L.signIn(null);
    await assert.rejects(L.rpc('create_party', { p_name: 'x' }), /Not signed in/);
  });

  test('internal helpers cannot be called by the app', async () => {
    await assert.rejects(
      L.rpc('_add_entry', {
        p_owner: me, p_party: rashid, p_date: '2026-10-01', p_amount: 1, p_kind: 'adjustment',
        p_note: 'x', p_source: 'app', p_source_ref: null,
      }),
      /permission denied/,
    );
  });

  test('archived parties keep history but take no new entries', async () => {
    await purchase({ weight_kg: 10, rate: 100 });
    await L.rpc('set_party_archived', { p_id: rashid, p_archived: true });
    assert.equal(await L.balance(rashid), -1000);
    await assert.rejects(purchase({ weight_kg: 1, rate: 1 }), /archived/);
  });

  test('bad input is rejected with a clear reason', async () => {
    await assert.rejects(purchase({ weight_kg: -5, rate: 100 }), /weight_must_be_positive/);
    await assert.rejects(deal({ kind: 'sale', party_id: akram, weight_kg: 5, rate: 1 }), /trade_needs_item_weight_rate/);
    await assert.rejects(purchase({ weight_kg: 5, rate: 1, paid_now: -1 }), /cannot be negative/);
    await assert.rejects(L.rpc('record_payment', { p_party_id: rashid, p_direction: 'in', p_amount: 0 }), /must be positive/);
  });
});
