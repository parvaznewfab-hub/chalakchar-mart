"use strict";
// Maintenance scripts (supplier text cleanup, image migration) stamp their
// product writes with systemWriteAt. onProductStockUpdated then does nothing
// for that write: no marketing, no low-stock alert (imported products have
// no lowStockAlerted flag, so any write to one with stock <= 5 would alert).

const SYSTEM_WRITE_FIELD = "systemWriteAt";

function stampMs(value) {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

/** True for a write made by a maintenance script. */
function isSystemMaintenanceWrite(before, after) {
  const afterMs = stampMs(after?.[SYSTEM_WRITE_FIELD]);
  return afterMs > 0 && afterMs !== stampMs(before?.[SYSTEM_WRITE_FIELD]);
}

module.exports = { SYSTEM_WRITE_FIELD, isSystemMaintenanceWrite };
