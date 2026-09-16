export class Gateway {
  constructor() {
    this.charges = [];
    this.loseNextResponse = false;
  }

  async charge(orderId) {
    this.charges.push({ orderId });
    if (this.loseNextResponse) {
      this.loseNextResponse = false;
      throw new Error("gateway response lost after charge");
    }
    return { status: "charged" };
  }
}
