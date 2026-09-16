import assert from "node:assert/strict";
import test from "node:test";
import { Gateway } from "../src/adapters/gateway.js";
import { LeasedJobs } from "../src/queue/leased-jobs.js";
import { Orders } from "../src/store/orders.js";
import { processNextPayment } from "../src/workers/payment.js";

test("marks an order paid after a successful charge", async () => {
  const queue = new LeasedJobs();
  const gateway = new Gateway();
  const orders = new Orders();
  await orders.save({ id: "order-1", status: "created" });
  await queue.publish({ id: "payment:order-1", orderId: "order-1" });

  await processNextPayment({ queue, gateway, orders });

  assert.equal(gateway.charges.length, 1);
  assert.equal(orders.get("order-1").status, "paid");
});
