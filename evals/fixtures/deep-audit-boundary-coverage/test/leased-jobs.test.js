import assert from "node:assert/strict";
import test from "node:test";
import { LeasedJobs } from "../src/queue/leased-jobs.js";

test("redelivers an unacknowledged job after restart", async () => {
  const queue = new LeasedJobs();
  await queue.publish({ id: "payment:order-1", orderId: "order-1" });

  assert.equal(queue.lease().id, "payment:order-1");
  queue.restart();
  assert.equal(queue.lease().id, "payment:order-1");
});
