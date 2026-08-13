const express = require("express");
const fs = require("fs");
const path = require("path");

const app = express();
const PORT = process.env.PORT || 3000;

const products = JSON.parse(
  fs.readFileSync(path.join(__dirname, "products.json"), "utf-8")
);

app.get("/health", (req, res) => res.json({ status: "ok" }));

// List all products, optionally filtered by a search query (?q=)
app.get("/products", (req, res) => {
  const q = (req.query.q || "").toLowerCase().trim();
  if (!q) return res.json(products);

  const results = products.filter(
    (p) =>
      p.name.toLowerCase().includes(q) ||
      p.description.toLowerCase().includes(q) ||
      p.categories.some((c) => c.toLowerCase().includes(q))
  );
  res.json(results);
});

// Get a single product by id
app.get("/products/:id", (req, res) => {
  const product = products.find((p) => p.id === req.params.id);
  if (!product) return res.status(404).json({ error: "product not found" });
  res.json(product);
});

app.listen(PORT, () => {
  console.log(`productcatalogservice listening on port ${PORT}`);
});
