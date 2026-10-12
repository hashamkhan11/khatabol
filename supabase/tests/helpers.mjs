// Test harness: a fresh in-memory Postgres (PGlite) with all migrations applied.
import { PGlite } from '@electric-sql/pglite';
import { readFileSync, readdirSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const migrationsDir = join(here, '..', 'migrations');

// Migrations run once per test file; each test then gets a copy of that database.
let template;

async function buildTemplate() {
  const db = new PGlite();
  await db.exec(readFileSync(join(here, 'auth_stub.sql'), 'utf8'));
  for (const file of readdirSync(migrationsDir).filter((f) => f.endsWith('.sql')).sort()) {
    await db.exec(readFileSync(join(migrationsDir, file), 'utf8'));
  }
  const dump = await db.dumpDataDir('none');
  await db.close();
  return dump;
}

export async function freshDb() {
  template ??= await buildTemplate();
  return new Ledger(await PGlite.create({ loadDataDir: template }));
}

class Ledger {
  constructor(db) {
    this.db = db;
  }

  // Creates a Supabase user. Leaves the session as the database admin.
  async createUser() {
    const id = randomUUID();
    await this.db.exec('reset role');
    await this.db.query('insert into auth.users (id) values ($1)', [id]);
    return id;
  }

  // Acts as a signed-in app user from now on (null = signed out).
  async signIn(userId) {
    await this.db.exec('reset role');
    await this.db.query("select set_config('request.jwt.claim.sub', $1, false)", [userId ?? '']);
    await this.db.exec('set role authenticated');
  }

  // Calls a database function with named arguments, like supabase.rpc().
  async rpc(fn, args = {}) {
    const keys = Object.keys(args);
    const params = keys.map((k) => {
      const v = args[k];
      return v !== null && typeof v === 'object' ? JSON.stringify(v) : v;
    });
    const sql = `select * from ${fn}(${keys.map((k, i) => `${k} => $${i + 1}`).join(', ')})`;
    return (await this.db.query(sql, params)).rows;
  }

  // Calls a function that returns a single value.
  async one(fn, args) {
    const [row] = await this.rpc(fn, args);
    return Object.values(row)[0];
  }

  async query(sql, params) {
    return (await this.db.query(sql, params)).rows;
  }

  close() {
    return this.db.close();
  }

  async balance(partyId) {
    const [row] = await this.query('select balance from party_balances where party_id = $1', [partyId]);
    return Number(row.balance);
  }
}

// Converts numeric columns (returned as strings) to numbers for easy asserts.
export function nums(row) {
  return Object.fromEntries(
    Object.entries(row).map(([k, v]) => [k, typeof v === 'string' && /^-?\d+(\.\d+)?$/.test(v) ? Number(v) : v]),
  );
}
