import assert from "node:assert/strict";
import test from "node:test";
import { createOrder } from "../src/api/create-order.js";

test("creates one order and publishes one payment job", async () => {
  const saved = [];
  const published = [];
  await createOrder(
    {
      orders: { save: async order => saved.push(order) },
      queue: { publish: async job => published.push(job) }
    },
    "order-1"
  );

  assert.equal(saved.length, 1);
  assert.equal(published.length, 1);
});
