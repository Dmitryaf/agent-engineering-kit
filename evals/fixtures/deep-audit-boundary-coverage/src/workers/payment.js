export async function processNextPayment({ queue, gateway, orders }) {
  const job = queue.lease();
  if (!job) {
    return false;
  }

  await gateway.charge(job.orderId);
  await orders.markPaid(job.orderId);
  queue.ack(job.id);
  return true;
}
