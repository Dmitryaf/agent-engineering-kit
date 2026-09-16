export class Orders {
  constructor() {
    this.records = new Map();
  }

  async save(order) {
    this.records.set(order.id, { ...order });
  }

  async markPaid(orderId) {
    const order = this.records.get(orderId);
    this.records.set(orderId, { ...order, status: "paid" });
  }

  get(orderId) {
    return this.records.get(orderId);
  }
}
