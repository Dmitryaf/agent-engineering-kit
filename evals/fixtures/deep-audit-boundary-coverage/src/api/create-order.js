export async function createOrder({ orders, queue }, orderId) {
  await orders.save({ id: orderId, status: "created" });
  await queue.publish({ id: `payment:${orderId}`, orderId });
  return { status: "accepted" };
}
