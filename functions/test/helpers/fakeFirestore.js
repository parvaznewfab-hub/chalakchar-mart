// Minimal in-memory Firestore fake for unit-testing transactional resolvers
// without a real Firestore emulator (none is set up in this project).
// Implements exactly the subset used by functions/category/*: collection(),
// where()/limit()/get() as a transactional query, doc(), transaction.set(),
// and runTransaction(). Not a general-purpose Firestore mock.

class FakeQuery {
  constructor(db, collectionName, filters = []) {
    this.db = db;
    this.collectionName = collectionName;
    this.filters = filters;
  }

  where(field, op, value) {
    if (op !== "==") throw new Error(`FakeFirestore only supports "==" (got "${op}")`);
    return new FakeQuery(this.db, this.collectionName, [...this.filters, { field, value }]);
  }

  limit() {
    return this;
  }

  _matches() {
    const docs = this.db._collections[this.collectionName] || {};
    return Object.entries(docs)
      .filter(([, data]) => this.filters.every((f) => data[f.field] === f.value))
      .map(([id, data]) => ({ id, data: () => ({ ...data }) }));
  }
}

class FakeDocRef {
  constructor(collectionName, id) {
    this.collectionName = collectionName;
    this.id = id;
  }
}

class FakeCollectionRef {
  constructor(db, name) {
    this.db = db;
    this.name = name;
  }

  doc(id) {
    const docId = id || `auto_${this.db._nextId++}`;
    return new FakeDocRef(this.name, docId);
  }

  where(field, op, value) {
    return new FakeQuery(this.db, this.name).where(field, op, value);
  }
}

class FakeTransaction {
  constructor(db) {
    this.db = db;
    this.writes = [];
  }

  async get(target) {
    if (target instanceof FakeQuery) {
      const docs = target._matches();
      return { empty: docs.length === 0, docs };
    }
    const data = (this.db._collections[target.collectionName] || {})[target.id];
    return { exists: Boolean(data), id: target.id, data: () => (data ? { ...data } : undefined) };
  }

  set(ref, data) {
    this.writes.push({ ref, data });
  }
}

class FakeFirestore {
  constructor() {
    this._collections = {};
    this._nextId = 1;
  }

  collection(name) {
    if (!this._collections[name]) this._collections[name] = {};
    return new FakeCollectionRef(this, name);
  }

  async runTransaction(updateFn) {
    const transaction = new FakeTransaction(this);
    const result = await updateFn(transaction);
    for (const { ref, data } of transaction.writes) {
      this._collections[ref.collectionName][ref.id] = data;
    }
    return result;
  }

  // Test convenience: seed a document directly without going through a transaction.
  _seed(collectionName, id, data) {
    if (!this._collections[collectionName]) this._collections[collectionName] = {};
    this._collections[collectionName][id] = data;
  }
}

module.exports = { FakeFirestore };
