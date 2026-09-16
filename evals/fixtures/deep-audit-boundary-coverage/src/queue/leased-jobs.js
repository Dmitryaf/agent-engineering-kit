export class LeasedJobs {
  constructor() {
    this.ready = [];
    this.leased = new Map();
  }

  async publish(job) {
    this.ready.push({ ...job });
  }

  lease() {
    const job = this.ready.shift();
    if (!job) {
      return null;
    }
    this.leased.set(job.id, job);
    return { ...job };
  }

  ack(jobId) {
    this.leased.delete(jobId);
  }

  restart() {
    this.ready.push(...this.leased.values());
    this.leased.clear();
  }
}
