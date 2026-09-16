export const routes = [
  { method: "POST", path: "/orders", handler: "src/api/create-order.js" },
  { method: "GET", path: "/admin/export", handler: "src/admin/export.js" }
];
