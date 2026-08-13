const express = require("express");
const { pool, init } = require("./db");

const app = express();
app.use(express.json());

const PORT = process.env.PORT || 3001;
const PRODUCT_CATALOG_URL =
  process.env.PRODUCT_CATALOG_URL || "http://localhost:3000";
const FLAT_SHIPPING_CENTS = 500; // simple flat-rate shipping, mirrors a mock shipping quote

app.get("/health", (req, res) => res.json({ status: "ok" }));

// ---------- Cart ----------

app.get("/cart/:userId", async (req, res) => {
  try {
    const { rows } = await pool.query(
      "SELECT product_id, quantity FROM cart_items WHERE user_id = $1",
      [req.params.userId]
    );
    res.json({ userId: req.params.userId, items: rows });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "failed to load cart" });
  }
});

app.post("/cart/:userId", async (req, res) => {
  const { productId, quantity } = req.body || {};
  if (!productId || !quantity || quantity <= 0) {
    return res.status(400).json({ error: "productId and quantity (>0) are required" });
  }
  try {
    await pool.query(
      `INSERT INTO cart_items (user_id, product_id, quantity)
       VALUES ($1, $2, $3)
       ON CONFLICT (user_id, product_id)
       DO UPDATE SET quantity = cart_items.quantity + EXCLUDED.quantity`,
      [req.params.userId, productId, quantity]
    );
    res.status(201).json({ status: "added" });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "failed to add item to cart" });
  }
});

app.delete("/cart/:userId", async (req, res) => {
  try {
    await pool.query("DELETE FROM cart_items WHERE user_id = $1", [req.params.userId]);
    res.json({ status: "cleared" });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "failed to clear cart" });
  }
});

// ---------- Checkout ----------

app.post("/checkout/:userId", async (req, res) => {
  const { email, shippingAddress } = req.body || {};
  if (!email || !shippingAddress) {
    return res.status(400).json({ error: "email and shippingAddress are required" });
  }

  const userId = req.params.userId;

  try {
    const { rows: cartItems } = await pool.query(
      "SELECT product_id, quantity FROM cart_items WHERE user_id = $1",
      [userId]
    );
    if (cartItems.length === 0) {
      return res.status(400).json({ error: "cart is empty" });
    }

    // Look up current prices from the product catalog service
    const items = [];
    let itemTotalCents = 0;
    for (const ci of cartItems) {
      const r = await fetch(`${PRODUCT_CATALOG_URL}/products/${ci.product_id}`);
      if (!r.ok) {
        return res.status(400).json({ error: `unknown product ${ci.product_id}` });
      }
      const product = await r.json();
      const lineTotal = product.priceCents * ci.quantity;
      itemTotalCents += lineTotal;
      items.push({
        productId: product.id,
        name: product.name,
        quantity: ci.quantity,
        unitPriceCents: product.priceCents,
        lineTotalCents: lineTotal,
      });
    }

    const shippingCents = FLAT_SHIPPING_CENTS;
    const totalCents = itemTotalCents + shippingCents;

    // Mock payment authorization (no real payment gateway wired up)
    const transactionId = `mock-txn-${Date.now()}`;

    const { rows: orderRows } = await pool.query(
      `INSERT INTO orders (user_id, email, shipping_address, items, item_total_cents, shipping_cents, total_cents)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING order_id, created_at`,
      [userId, email, shippingAddress, JSON.stringify(items), itemTotalCents, shippingCents, totalCents]
    );

    await pool.query("DELETE FROM cart_items WHERE user_id = $1", [userId]);

    res.status(201).json({
      orderId: orderRows[0].order_id,
      createdAt: orderRows[0].created_at,
      transactionId,
      email,
      shippingAddress,
      items,
      itemTotalCents,
      shippingCents,
      totalCents,
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "checkout failed" });
  }
});

app.get("/orders/:orderId", async (req, res) => {
  try {
    const { rows } = await pool.query("SELECT * FROM orders WHERE order_id = $1", [
      req.params.orderId,
    ]);
    if (rows.length === 0) return res.status(404).json({ error: "order not found" });
    res.json(rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "failed to load order" });
  }
});

init()
  .then(() => {
    app.listen(PORT, () => {
      console.log(`cartcheckoutservice listening on port ${PORT}`);
    });
  })
  .catch((err) => {
    console.error("failed to initialize database:", err);
    process.exit(1);
  });
