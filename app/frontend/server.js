const express = require("express");
const session = require("express-session");
const path = require("path");

const app = express();
const PORT = process.env.PORT || 80;

const PRODUCT_CATALOG_URL =
  process.env.PRODUCT_CATALOG_URL || "http://localhost:3000";
const CART_CHECKOUT_URL =
  process.env.CART_CHECKOUT_URL || "http://localhost:3001";

app.set("view engine", "ejs");
app.set("views", path.join(__dirname, "views"));
app.use(express.static(path.join(__dirname, "public")));
app.use(express.urlencoded({ extended: true }));
app.use(
  session({
    secret: process.env.SESSION_SECRET || "boutique-demo-secret",
    resave: false,
    saveUninitialized: true,
  })
);

const cents = (c) => `$${(c / 100).toFixed(2)}`;
app.locals.cents = cents;

app.get("/health", (req, res) => res.json({ status: "ok" }));

// ---------- Home / product listing ----------
app.get("/", async (req, res) => {
  try {
    const q = req.query.q ? `?q=${encodeURIComponent(req.query.q)}` : "";
    const r = await fetch(`${PRODUCT_CATALOG_URL}/products${q}`);
    const products = await r.json();
    res.render("index", { products, query: req.query.q || "" });
  } catch (err) {
    console.error(err);
    res.status(502).render("error", { message: "Could not reach product catalog service." });
  }
});

// ---------- Product detail ----------
app.get("/product/:id", async (req, res) => {
  try {
    const r = await fetch(`${PRODUCT_CATALOG_URL}/products/${req.params.id}`);
    if (!r.ok) return res.status(404).render("error", { message: "Product not found." });
    const product = await r.json();
    res.render("product", { product });
  } catch (err) {
    console.error(err);
    res.status(502).render("error", { message: "Could not reach product catalog service." });
  }
});

// ---------- Cart ----------
app.post("/cart/add", async (req, res) => {
  const { productId, quantity } = req.body;
  try {
    await fetch(`${CART_CHECKOUT_URL}/cart/${req.session.id}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ productId, quantity: parseInt(quantity, 10) || 1 }),
    });
    res.redirect("/cart");
  } catch (err) {
    console.error(err);
    res.status(502).render("error", { message: "Could not reach cart service." });
  }
});

app.get("/cart", async (req, res) => {
  try {
    const cartRes = await fetch(`${CART_CHECKOUT_URL}/cart/${req.session.id}`);
    const cart = await cartRes.json();

    const items = [];
    let totalCents = 0;
    for (const ci of cart.items) {
      const pr = await fetch(`${PRODUCT_CATALOG_URL}/products/${ci.product_id}`);
      if (!pr.ok) continue;
      const product = await pr.json();
      const lineTotal = product.priceCents * ci.quantity;
      totalCents += lineTotal;
      items.push({ product, quantity: ci.quantity, lineTotal });
    }

    res.render("cart", { items, totalCents });
  } catch (err) {
    console.error(err);
    res.status(502).render("error", { message: "Could not reach cart or catalog service." });
  }
});

app.post("/cart/clear", async (req, res) => {
  try {
    await fetch(`${CART_CHECKOUT_URL}/cart/${req.session.id}`, { method: "DELETE" });
    res.redirect("/cart");
  } catch (err) {
    console.error(err);
    res.status(502).render("error", { message: "Could not reach cart service." });
  }
});

// ---------- Checkout ----------
app.get("/checkout", (req, res) => {
  res.render("checkout", { error: null });
});

app.post("/checkout", async (req, res) => {
  const { email, shippingAddress } = req.body;
  try {
    const r = await fetch(`${CART_CHECKOUT_URL}/checkout/${req.session.id}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, shippingAddress }),
    });
    const order = await r.json();
    if (!r.ok) {
      return res.status(400).render("checkout", { error: order.error || "Checkout failed." });
    }
    res.render("order-confirmation", { order });
  } catch (err) {
    console.error(err);
    res.status(502).render("error", { message: "Could not reach checkout service." });
  }
});

app.listen(PORT, () => {
  console.log(`frontend listening on port ${PORT}`);
});
